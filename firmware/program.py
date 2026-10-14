"""A bounded firmware builder, not a general assembly-language parser."""
from pathlib import Path
import hashlib
import json

def immediate(op, rd, rs1, value):
    if not (0 <= rd < 16 and 0 <= rs1 < 16 and -(1 << 19) <= value < (1 << 19)):
        raise ValueError('Invalid register or signed 20-bit immediate')
    return (op << 28) | (rd << 24) | (rs1 << 20) | (value & 0xfffff)

def register(fn, rd, a, b):
    if not all(0 <= n < 16 for n in (rd,a,b)) or not 0 <= fn < 8:
        raise ValueError('Invalid R-type fields')
    return (rd << 24) | (a << 20) | (b << 16) | fn

class Program:
    def __init__(self): self.items=[]; self.labels={}; self.fixups=[]
    def emit(self, word, text): self.items.append((word,text))
    def label(self, name):
        if name in self.labels: raise ValueError('Duplicate label: '+name)
        self.labels[name]=len(self.items)
    def i(self, op, d, a, v, text=''):
        self.emit(immediate(op,d,a,v),text or f'op{op:X} R{d}, R{a}, {v}')
    def r(self, fn, d, a, b):
        self.emit(register(fn,d,a,b), f'{["ADD","SUB","AND","OR","XOR","SLT","SLL","SRL"][fn]} R{d}, R{a}, R{b}')
    def branch(self, op, b, a, label):
        self.fixups.append((len(self.items),op,b,a,label))
        self.emit(0,f'{"BEQ" if op==6 else "BNE"} R{a}, R{b}, {label}')
    def jump(self, label):
        self.fixups.append((len(self.items),8,0,0,label)); self.emit(0,'J '+label)
    def words(self):
        words=[w for w,_ in self.items]
        for pc,op,b,a,label in self.fixups:
            offset=self.labels[label]-pc
            if op==8:
                if not -(1<<23)<=offset<(1<<23): raise ValueError('Jump out of range')
                words[pc]=(8<<28)|(offset&0xffffff)
            else: words[pc]=immediate(op,b,a,offset)
        if len(words)>256: raise ValueError('Firmware exceeds instruction memory')
        return words

def temperature_firmware():
    p=Program()
    # r1 sensor base; r2 UART base; r3 circular index; r4 sum; r5 warm-up count;
    # r6 sample; r7 outgoing sample; r8 scratch; r9 average; r10 alarm;
    # r11 processed count; r12/r13 scratch; r14 average shift; r15 GPIO address.
    p.i(1,1,0,0x100,'ADDI R1, R0, SENSOR_BASE')
    p.i(1,2,0,0x110,'ADDI R2, R0, UART_BASE')
    p.i(1,14,0,4); p.i(1,15,0,0x130)
    p.label('clear_ring'); p.i(5,0,3,0); p.i(1,3,3,1); p.i(10,8,3,16)
    p.branch(7,0,8,'clear_ring'); p.i(1,3,0,0)
    for address in range(32,36): p.i(5,0,0,address)
    p.i(1,13,0,2); p.i(5,13,15,0)
    p.label('poll'); p.i(4,8,1,0); p.i(2,8,8,1); p.branch(6,0,8,'poll')
    p.i(4,6,1,1); p.i(4,7,3,0); p.i(5,6,3,0)
    p.r(1,4,4,7); p.r(0,4,4,6)
    p.i(1,3,3,1); p.i(2,3,3,15); p.i(1,11,11,1)
    p.i(10,8,5,16); p.branch(6,0,8,'warm_done'); p.i(1,5,5,1)
    p.label('warm_done'); p.r(7,9,4,14)
    p.i(10,8,5,16); p.branch(7,0,8,'finish'); p.branch(6,0,10,'alarm_off')
    p.i(10,8,9,751); p.branch(6,0,8,'finish')
    p.i(1,10,0,0); p.i(4,8,0,35); p.i(1,8,8,1); p.i(5,8,0,35); p.jump('event')
    p.label('alarm_off'); p.i(10,8,9,800); p.branch(7,0,8,'finish')
    p.i(1,10,0,1); p.i(4,8,0,34); p.i(1,8,8,1); p.i(5,8,0,34)
    p.label('event'); p.i(3,13,10,2); p.i(5,13,15,0)
    p.i(1,13,0,0xa5); p.i(5,13,2,2); p.i(5,10,2,2)
    p.i(2,13,9,255); p.i(5,13,2,2); p.i(1,12,0,8); p.r(7,13,9,12); p.i(5,13,2,2)
    p.label('finish'); p.i(5,9,0,33); p.i(5,11,0,32); p.jump('poll')
    return p

def write_image(path, words):
    Path(path).write_text(''.join(f'{w:08x}\n' for w in words+[0xf0000000]*(256-len(words))), encoding='ascii', newline='\n')

def build(root):
    out=Path(root)/'build'; out.mkdir(exist_ok=True)
    p=temperature_firmware(); words=p.words(); write_image(out/'firmware.hex',words)
    (out/'firmware.lst').write_text('\n'.join(f'{pc:03x}: {w:08x}  {p.items[pc][1]}' for pc,w in enumerate(words))+'\n')
    manifest={'instruction_words':len(words),'image_sha256':hashlib.sha256((out/'firmware.hex').read_bytes()).hexdigest(),
              'labels':p.labels,'window':16,'alarm_on_deci_c':800,'alarm_off_deci_c':750}
    (Path(root)/'reports/firmware.json').write_text(json.dumps(manifest,indent=2))
    return manifest
