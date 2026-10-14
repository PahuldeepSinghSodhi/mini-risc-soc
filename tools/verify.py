"""Application oracle, directed SoC fixtures, and reproducible workload analysis."""
from collections import deque
import csv
import hashlib
import json
from pathlib import Path
import random
import statistics
from firmware.program import Program, write_image
from tools.metadata import metadata

def mixed_workload():
    rng=random.Random(14)
    return ([600+rng.randint(-8,8) for _ in range(64)]+[1200]+[600]*31+
            [900+rng.randint(-8,8) for _ in range(96)]+
            [785+rng.randint(-30,30) for _ in range(96)]+[650]*96+[600]*128)

def expected(samples):
    """Recompute the complete window sum, independently of firmware's rolling sum."""
    window=deque([0]*16,maxlen=16);alarm=0;rows=[];events=[]
    for n,(index,value) in enumerate(samples,1):
        window.append(value);average=sum(window)//16
        next_alarm=alarm
        if n>=16:
            if not alarm and average>=800: next_alarm=1
            elif alarm and average<=750: next_alarm=0
        if next_alarm!=alarm: events.append((index,next_alarm,average))
        alarm=next_alarm;rows.append((index,average,alarm))
    return rows,events

def run_stream(root, execute, samples, name, interval=1024):
    raw=Path(root)/'reports/raw';raw.mkdir(parents=True,exist_ok=True)
    sample_file=raw/(name+'.samples');trace=raw/(name+'.csv')
    sample_file.write_text(''.join(f'{v}\n' for v in samples))
    output=execute([f'--samples={sample_file}',f'--interval={interval}',f'--trace={trace}'])
    result=json.loads(output.strip().splitlines()[-1])
    with trace.open() as f: records=list(csv.DictReader(f))
    records=[{k:(v if k=='event' else int(v)) for k,v in row.items()} for row in records]
    offers=[r for r in records if r['event']=='offer']
    accepted=[r for r in offers if r['extra']]
    predicted,events=expected([(r['index'],r['value']) for r in accepted])
    actual=[(r['index'],r['value'],r['extra']) for r in records if r['event']=='processed']
    if actual!=predicted: raise AssertionError(f'{name}: application averages/alarm mismatch')
    alarms=[r for r in records if r['event']=='alarm']
    if [(r['index'],r['value']) for r in alarms]!=[(i,a) for i,a,_ in events]:
        raise AssertionError(f'{name}: GPIO transition mismatch')
    uart=[b for _,alarm,average in events for b in (0xa5,alarm,average&255,average>>8)]
    if result['uart']!=uart: raise AssertionError(f'{name}: serial event records mismatch')
    if not (result['accepted']==result['processed']==len(predicted) and
            result['dropped']==len(offers)-len(accepted) and result['high_water']<=16):
        raise AssertionError(f'{name}: dropped/processed accounting mismatch')
    final=predicted[-1][1] if predicted else 0
    memory=result['memory']
    if [memory[str(a)] for a in range(32,36)]!=[len(predicted),final,sum(a for _,a,_ in events),sum(1-a for _,a,_ in events)]:
        raise AssertionError(f'{name}: firmware RAM statistics mismatch')
    arrival={r['index']:r['cycle'] for r in accepted}
    pops={r['index']:r['cycle'] for r in records if r['event']=='pop'}
    done={r['index']:r['cycle'] for r in records if r['event']=='processed'}
    if set(pops)!=set(arrival) or len(pops)!=len(accepted): raise AssertionError('Missing/duplicated pop')
    service=[done[i]-pops[i] for i in done]
    result.update(name=name,interval_cycles=interval,seed=14,
        metadata=metadata(root),
        workload_sha256=hashlib.sha256(sample_file.read_bytes()).hexdigest(),
        mean_processing_cycles=statistics.mean(service) if service else 0,
        max_processing_cycles=max(service,default=0),
        mean_queue_cycles=statistics.mean(pops[i]-arrival[i] for i in pops) if pops else 0,
        alarm_latency_cycles=[r['cycle']-arrival[r['index']] for r in alarms],
        alarm_events=[{'sample_index':i,'state':a,'average_deci_c':v} for i,a,v in events],
        cycles_per_offered_sample=interval,application_matches=True)
    # Separate filter delay from service delay in the known zero-drop mixed scenario.
    if samples==mixed_workload() and not result['dropped']:
        onset=next((r for r in alarms if r['index']>=96 and r['value']==1),None)
        if onset:
            result['overheat_filter_delay_samples']=onset['index']-96
            result['overheat_filter_delay_cycles']=arrival[onset['index']]-arrival[96]
    (raw/(name+'.json')).write_text(json.dumps(result,indent=2))
    return result

def soc_tests(root, execute):
    root=Path(root);folder=root/'build/fixtures';folder.mkdir(parents=True,exist_ok=True)
    p=Program();p.i(1,1,0,0x100);p.i(1,2,0,0x110);p.i(1,3,0,0x130)
    p.i(1,4,0,2);p.i(5,4,3,0)
    p.i(4,5,1,1);p.i(5,5,0,40);p.i(4,6,1,1);p.i(5,6,0,41)
    p.i(4,7,1,0);p.i(5,7,0,42);p.i(4,7,0,0x120);p.i(5,7,0,43)
    p.i(4,7,0,0x121);p.i(5,7,0,44);p.i(1,4,0,3);p.i(5,4,3,0)
    p.i(4,7,3,0);p.i(5,7,0,45);p.i(1,4,0,0xa5);p.i(5,4,2,2)
    p.i(4,7,2,1);p.i(5,7,0,46);p.i(4,7,2,0);p.i(5,7,0,47);p.emit(0xf0000000,'HALT')
    image=folder/'mmio.hex';write_image(image,p.words());sf=folder/'mmio.samples';sf.write_text('111\n222\n')
    r=json.loads(execute([f'+imem={image}','--mode=halt','--loopback=1',f'--samples={sf}','--interval=64','--start-delay=200']).strip().splitlines()[-1])
    assert r['fault']==0 and r['halted']==1 and r['uart']==[165]
    assert [r['memory'][str(i)] for i in (40,41,42,45,46)]==[111,222,0,3,165]
    assert r['memory']['43']>0 and r['memory']['44']>0
    tests=[{'name':'mmio_sensor_blocking_uart_loopback_counters_gpio','passed':True}]
    for op,address in [(5,0x100),(5,0x101),(5,0x120),(4,0x112),(4,0x104),(4,0x20000)]:
        image=folder/f'fault_{op}_{address:x}.hex';p=Program();p.i(op,1,0,address);p.emit(0xf0000000,'HALT');write_image(image,p.words())
        r=json.loads(execute([f'+imem={image}','--mode=halt']).strip().splitlines()[-1])
        assert r['fault']==3 and r['fault_pc']==0 and r['gpio']==0
        tests.append({'name':f'mmio_fault_{op}_{address:x}','passed':True})
    # TX register writes block when its FIFO fills and must eventually all complete once.
    p=Program();p.i(1,1,0,0x110)
    for value in range(24):p.i(1,2,0,value);p.i(5,2,1,2)
    p.emit(0xf0000000,'HALT');image=folder/'tx_blocking.hex';write_image(image,p.words())
    r=json.loads(execute([f'+imem={image}','--mode=halt']).strip().splitlines()[-1])
    assert r['fault']==0 and r['uart']==list(range(24))
    tests.append({'name':'mmio_tx_full_wait_exactly_once','passed':True})
    return tests

def application_tests(root,execute):
    cases={'normal':[600]*64,'warmup_hot':[1000]*15,'threshold_exact':[800]*16,
           'isolated_spike':[600]*32+[1200]+[600]*32,
           'hysteresis':[800]*16+[775]*32+[750]*16,
           'recovery':[900]*16+[650]*32,
           'threshold_noise':[790,810]*32,'mixed':mixed_workload(),
           'overload':mixed_workload()}
    results=[]
    for name,samples in cases.items():
        result=run_stream(root,execute,samples,'test_'+name,1 if name=='overload' else 1024)
        if name!='overload': assert result['dropped']==0
        else: assert result['dropped']>0
        results.append(result)
    return results
