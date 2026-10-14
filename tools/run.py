"""Reproducible native RTL workflow. No global PATH or system SDK modifications."""
from __future__ import annotations
import argparse
import hashlib
import importlib.metadata
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import sys
import urllib.request
import venv
import zipfile

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
BUILD = ROOT / 'build'
REPORTS = ROOT / 'reports'
VENV = ROOT / '.venv'
SDK_VERSION = '10.0.28000.2705'

def command(args, *, env=None, log=None):
    args = [str(a) for a in args]
    args[0] = shutil.which(args[0], path=(env or os.environ).get('PATH')) or args[0]
    result = subprocess.run(args, cwd=ROOT, env=env,
                            capture_output=True, text=True, errors='replace')
    if log:
        path = Path(log); path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(result.stdout + result.stderr, encoding='utf-8')
    if result.returncode:
        raise RuntimeError(f"Command failed ({result.returncode}): {args}\n{result.stdout[-5000:]}\n{result.stderr[-5000:]}")
    return result.stdout + result.stderr

def sdk_setup():
    sdk = BUILD / 'tools' / 'sdk'
    system = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Windows Kits/10'
    if (system / 'Include').exists() and (system / 'Lib').exists():
        return
    sdk.mkdir(parents=True, exist_ok=True)
    for package in ('microsoft.windows.sdk.cpp', 'microsoft.windows.sdk.cpp.x64'):
        folder = sdk / package
        if (folder / 'c').exists():
            continue
        archive = sdk / (package + '.nupkg')
        print(f'Downloading project-local {package} {SDK_VERSION}', flush=True)
        urllib.request.urlretrieve(f'https://api.nuget.org/v3-flatcontainer/{package}/{SDK_VERSION}/{package}.{SDK_VERSION}.nupkg', archive)
        with zipfile.ZipFile(archive) as z:
            for entry in z.infolist():
                if not (folder / entry.filename).resolve().is_relative_to(folder.resolve()):
                    raise RuntimeError('Unsafe archive path')
            z.extractall(folder)

def environment():
    env = os.environ.copy()
    scripts = Path(sys.executable).parent
    import verilator
    vroot = Path(verilator.__file__).parent
    env['VERILATOR_ROOT'] = str(vroot)
    env['PATH'] = str(scripts) + os.pathsep + env.get('PATH', '')
    if os.name == 'nt':
        program = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)'))
        vswhere = program / 'Microsoft Visual Studio/Installer/vswhere.exe'
        vs = command([vswhere, '-latest', '-products', '*', '-requires',
                      'Microsoft.VisualStudio.Component.VC.Tools.x86.x64', '-property', 'installationPath']).strip()
        if not vs:
            raise RuntimeError('Visual Studio x64 C++ tools are required.')
        vc = sorted((Path(vs) / 'VC/Tools/MSVC').iterdir())[-1]
        local = BUILD / 'tools/sdk/microsoft.windows.sdk.cpp/c'
        if local.exists():
            inc_root = local / 'Include'
            version = sorted(p.name for p in inc_root.iterdir())[-1]
            lib_root = BUILD / 'tools/sdk/microsoft.windows.sdk.cpp.x64/c'
            sdk_bin = local / 'bin' / version / 'x64'
        else:
            sdk_root = program / 'Windows Kits/10'
            inc_root = sdk_root / 'Include'
            if not inc_root.exists(): raise RuntimeError('Windows SDK missing. Run setup.')
            version = sorted(p.name for p in inc_root.iterdir())[-1]
            lib_root = sdk_root / 'Lib' / version
            sdk_bin = sdk_root / 'bin' / version / 'x64'
        env['PATH'] = os.pathsep.join([str(vc / 'bin/Hostx64/x64'), str(sdk_bin), env['PATH']])
        env['INCLUDE'] = ';'.join(str(p) for p in [vc / 'include', *[inc_root / version / n for n in ('ucrt','shared','um','winrt')]])
        env['LIB'] = ';'.join(str(p) for p in [vc / 'lib/x64', lib_root / 'ucrt/x64', lib_root / 'um/x64'])
        env['CC'] = env['CXX'] = 'cl'
        env['MINIRISC_SDK_VERSION'] = version
        env['MINIRISC_SDK_SOURCE'] = 'project-local NuGet' if local.exists() else 'installed Windows SDK'
    return env, vroot

def tool_manifest():
    from tools.metadata import metadata
    env, vr = environment()
    data = {'packages': {n: importlib.metadata.version(n) for n in
            ('verilator','yowasp-yosys','yowasp-runtime','cmake','ninja','wasmtime')},
            'python': sys.version, 'platform': sys.platform,
            'verilator_binary': command([vr / 'bin' / ('verilator_bin.exe' if os.name == 'nt' else 'verilator_bin'), '--version'], env=env).strip(),
            'yosys': command(['yowasp-yosys','-V'], env=env).strip()}
    if os.name == 'nt':
        data['compiler'] = 'MSVC'
        for config in (BUILD/'native-msvc/CMakeFiles').glob('*/CMakeCXXCompiler.cmake'):
            match=re.search(r'set\(CMAKE_CXX_COMPILER_VERSION "([^"]+)"\)',config.read_text())
            if match: data['compiler_version']=match.group(1)
        data['sdk_headers_version'] = env['MINIRISC_SDK_VERSION']
        data['sdk_source'] = env['MINIRISC_SDK_SOURCE']
        if env['MINIRISC_SDK_SOURCE'] == 'project-local NuGet':
            data['sdk_package_version'] = SDK_VERSION
        data['sdk_archive_sha256']={p.name:hashlib.sha256(p.read_bytes()).hexdigest()
            for p in (BUILD/'tools/sdk').glob('*.nupkg')}
    REPORTS.mkdir(exist_ok=True)
    data['metadata']=metadata(ROOT)
    (REPORTS / 'toolchain.json').write_text(json.dumps(data, indent=2), encoding='utf-8')
    return data

def rtl_sources():
    return [ROOT/'rtl/mini_risc_pkg.sv', *sorted(p for p in (ROOT/'rtl').glob('*.sv') if p.name != 'mini_risc_pkg.sv')]

def build_models(models):
    env, vr = environment()
    for model in models:
        sources = [ROOT/'sim/smoke.sv'] if model == 'smoke' else rtl_sources()
        if model == 'unit_top': sources.append(ROOT/'sim/unit_top.sv')
        digest = hashlib.sha256(b''.join(p.read_bytes() for p in sources)).hexdigest()
        out = BUILD/'generated'/model
        stamp = out/'source.sha256'
        if not stamp.exists() or stamp.read_text() != digest:
            if out.exists():
                if not out.resolve().is_relative_to((BUILD/'generated').resolve()):
                    raise RuntimeError('Refusing to clean outside generated workspace')
                shutil.rmtree(out)
            out.mkdir(parents=True)
            args = [vr/'bin'/('verilator_bin.exe' if os.name == 'nt' else 'verilator_bin'),
                    '--cc','--assert','--top-module',model,'--Mdir',out]
            if os.name == 'nt': args += ['--compiler','msvc']
            args += [str(p.relative_to(ROOT)) for p in sources]
            command(args, env=env, log=BUILD/'logs'/f'{model}_verilate.log')
            stamp.write_text(digest)
    command(['cmake','-S','.', '-B','build/native-msvc','-G','Ninja',
             '-DCMAKE_BUILD_TYPE=Release', f'-DVROOT={vr.as_posix()}'],env=env,log=BUILD/'logs/configure.log')
    command(['cmake','--build','build/native-msvc','-j','4','--target',
             *[m+'_sim' for m in models]],env=env,log=BUILD/'logs/build.log')

def executable(model):
    return BUILD/'native-msvc'/(model+'_sim'+('.exe' if os.name == 'nt' else ''))

def smoke():
    build_models(['smoke'])
    print(command([executable('smoke')]).strip())
    env, _ = environment()
    text = command(['yowasp-yosys','-Q','-T','-p',
                    'read_slang -j 1 sim/smoke.sv --top smoke; synth -top smoke -noabc; check -assert; stat'],
                   env=env,log=BUILD/'logs/synthesis_smoke.log')
    if 'Found and reported 0 problems.' not in text or '$_DFF_' not in text:
        raise RuntimeError('Synthesis smoke did not produce expected evidence')
    tool_manifest()
    print('PASS Slang/Yosys synthesis smoke')

def prepare():
    from firmware.program import build
    build(ROOT)
    build_models(['mini_risc_cpu','unit_top','mini_risc_soc'])
    tool_manifest()

def soc_execute(args):
    return command([executable('mini_risc_soc'), *args])

def test():
    from tools.metadata import metadata
    from tools.verify import soc_tests, application_tests
    suites=[]
    for model in ('mini_risc_cpu','unit_top'):
        data=json.loads(command([executable(model)]).strip().splitlines()[-1])
        suites.append(data); print(f"PASS {data['suite']}: {data['passed']} cases")
    mmio=soc_tests(ROOT,soc_execute)
    apps=application_tests(ROOT,soc_execute)
    result={'suites':suites,'mmio':mmio,'application':apps,
            'metadata':metadata(ROOT),
            'total_passed':sum(s['passed'] for s in suites)+len(mmio)+len(apps),
            'coverage_note':'Directed scenarios and seeded tests; not a code-coverage or formal-proof percentage.'}
    (REPORTS/'tests.json').write_text(json.dumps(result,indent=2))
    print(f"PASS SoC: {len(mmio)} MMIO cases, {len(apps)} application cases; total {result['total_passed']}")

def demo():
    from tools.verify import mixed_workload,run_stream
    data=run_stream(ROOT,soc_execute,mixed_workload(),'demo',1024)
    (REPORTS/'demo.json').write_text(json.dumps(data,indent=2))
    print(f"PASS demo: {data['processed']} processed, {data['dropped']} dropped, {len(data['alarm_events'])} alarm transitions")
    return data

def benchmark():
    from tools.metadata import metadata
    from tools.verify import mixed_workload,run_stream
    rows=[run_stream(ROOT,soc_execute,mixed_workload(),f'interval_{n}',n)
          for n in (16,32,64,128,256,512,1024)]
    zero=[r['interval_cycles'] for r in rows if r['dropped']==0]
    result={'workload_samples':512,'seed':14,'rows':rows,
            'metadata':metadata(ROOT),
            'smallest_tested_zero_drop_interval_cycles':min(zero) if zero else None,
            'note':'Finite-workload sweep, not a proven universal maximum throughput. Idle polling and UART events are included.'}
    (REPORTS/'benchmark.json').write_text(json.dumps(result,indent=2))
    print(f"PASS benchmark: smallest tested zero-drop interval = {result['smallest_tested_zero_drop_interval_cycles']} cycles")
    return result

def synth():
    from tools.metadata import metadata
    env,_=environment();results={}
    sources=' '.join(p.relative_to(ROOT).as_posix() for p in rtl_sources())
    for top in ('mini_risc_cpu','mini_risc_soc'):
        script=(f'read_slang -j 1 {sources} --top {top}; '
                f'synth -top {top} -noabc -run begin:coarse; '
                f'write_json build/{top}_coarse.json; '
                f'synth -top {top} -noabc -run fine:check; check -assert; '
                f'tee -o reports/{top}_stat.json stat -json')
        log=command(['yowasp-yosys','-Q','-T','-p',script],env=env,log=REPORTS/f'{top}_synthesis.log')
        if 'Found and reported 0 problems.' not in log:
            raise RuntimeError(f'{top}: synthesis check evidence missing')
        stat=json.loads((REPORTS/f'{top}_stat.json').read_text())['design']
        coarse=json.loads((BUILD/f'{top}_coarse.json').read_text())
        memories=[]
        for module in coarse['modules'].values():
            for name,memory in module.get('memories',{}).items():
                memories.append({'name':name,'width':memory['width'],'words':memory['size'],
                                 'bits':memory['width']*memory['size'],
                                 'kind':'inferred decode ROM' if name.startswith('$') else 'declared memory'})
        sequential=sum(n for typ,n in stat['num_cells_by_type'].items() if typ.startswith(('$_DFF','$_SDFF','$_DLATCH')))
        if any('LATCH' in typ.upper() for typ in stat['num_cells_by_type']):
            raise RuntimeError(f'{top}: unexpected latch inferred')
        results[top]={'generic_cells':stat['num_cells'],'sequential_bit_cells':sequential,
                      'cell_types':stat['num_cells_by_type'],'coarse_memories':memories,
                      'mapped_memory_bits':stat['num_memory_bits'],'check_passed':True}
        print(f"PASS synthesis {top}: {stat['num_cells']} generic cells, {sequential} sequential bit cells")
    result={'flow':'read_slang; synth coarse; synth fine -noabc; check -assert; stat',
            'metadata':metadata(ROOT),
            'note':'Technology-independent primitive counts, no ABC/library/FPGA mapping, placement, timing or power analysis.',
            'tops':results}
    (REPORTS/'synthesis.json').write_text(json.dumps(result,indent=2))
    return result

def summary():
    from tools.metadata import metadata
    if not all((REPORTS/n).exists() for n in ('tests.json','benchmark.json','demo.json','synthesis.json')):return
    tests=json.loads((REPORTS/'tests.json').read_text());bench=json.loads((REPORTS/'benchmark.json').read_text())
    demo_data=json.loads((REPORTS/'demo.json').read_text());syn=json.loads((REPORTS/'synthesis.json').read_text())
    current=metadata(ROOT)
    if any(r.get('metadata')!=current for r in (tests,bench,demo_data,syn)):
        (REPORTS/'RESULTS.md').write_text('# Results need regeneration\n\nSource or firmware fingerprints differ between reports. Run `python tools/run.py all`.\n')
        print('Combined report withheld: evidence fingerprints differ; run all.')
        return
    firmware=json.loads((REPORTS/'firmware.json').read_text())
    text=['# Measured MiniRISC results','',f"Regression: **{tests['total_passed']} passing cases/suites**. Component suites contain multiple checks; this is not a coverage percentage.",
          '',f"Firmware: {firmware['instruction_words']} words; SHA-256 `{firmware['image_sha256']}`.",
          f"Implementation fingerprint: `{current['source_sha256']}`.",
          '',f"Demo: {demo_data['processed']} samples processed; {demo_data['dropped']} dropped; {len(demo_data['alarm_events'])} alarm transitions.",
          f"Overheat filtering delay: {demo_data.get('overheat_filter_delay_samples')} sample intervals, measured separately from queue/CPU latency.",
          f"Qualifying-sample arrival to GPIO transition: {demo_data['alarm_latency_cycles']} cycles.",
          '', '## Fixed 512-sample workload, seed 14','',
          '| Input interval (cycles) | Processed | Dropped | FIFO peak | Mean processing cycles (pop to completion) |',
          '|---:|---:|---:|---:|---:|']
    for r in bench['rows']:text.append(f"| {r['interval_cycles']} | {r['processed']} | {r['dropped']} | {r['high_water']} | {r['mean_processing_cycles']:.2f} |")
    text += ['',f"Smallest **tested** zero-drop interval: {bench['smallest_tested_zero_drop_interval_cycles']} cycles. This finite sweep does not prove a maximum sustainable rate for every workload.",
             '', '## Generic synthesis, no ABC or target library','',
             '| Design | Primitive cells | Sequential bit cells |', '|---|---:|---:|']
    for top,r in syn['tops'].items():text.append(f"| {top} | {r['generic_cells']} | {r['sequential_bit_cells']} |")
    text += ['', 'Memories are reported before mapping in synthesis.json and expanded into generic logic/storage for these counts. Simulation debug ports are excluded from synthesis.',
             'These are not FPGA LUT/BRAM utilization, physical area, maximum frequency, or power measurements.',
             '', 'Raw inputs, CSV execution traces, and per-run JSON are in raw/. Tool versions are in toolchain.json.',
             'Full logs and per-type synthesis statistics are retained beside this report. All timings are simulated cycles.', '']
    (REPORTS/'RESULTS.md').write_text('\n'.join(text))

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=['setup','test','demo','benchmark','synth','all'])
    args=parser.parse_args()
    os.chdir(ROOT); BUILD.mkdir(exist_ok=True); REPORTS.mkdir(exist_ok=True)
    vp=VENV/('Scripts/python.exe' if os.name=='nt' else 'bin/python')
    if Path(sys.executable).resolve() != vp.resolve():
        if not vp.exists():
            if args.action != 'setup': raise RuntimeError('Run python tools/run.py setup first.')
            venv.create(VENV,with_pip=True)
        return subprocess.call([str(vp),str(Path(__file__)),args.action],cwd=ROOT)
    if args.action=='setup':
        print(command([sys.executable,'-m','pip','install','--disable-pip-version-check','-r','requirements-tools.txt']))
        if os.name=='nt': sdk_setup()
        smoke()
    else:
        prepare()
        if args.action in ('test','all'): test()
        if args.action in ('demo','all'): demo()
        if args.action in ('benchmark','all'): benchmark()
        if args.action in ('synth','all'): synth()
        summary()
    return 0

if __name__=='__main__':
    try: sys.exit(main())
    except (RuntimeError, subprocess.SubprocessError) as exc:
        print(str(exc),file=sys.stderr); sys.exit(1)
