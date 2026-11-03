from pathlib import Path
import random,json
from awb_reference import CycleReference,ratio

root=Path(__file__).resolve().parent
rng=random.Random(20261017)
model=CycleReference();cycles=0;frames=0;valid_outputs=0
out=(root/'awb_unit_vectors.txt').open('w')
def emit(rst=1,user=0,valid=0,last=0,pixels=None):
    global cycles,valid_outputs
    pixels=pixels or [(0,0,0)]*4
    data=int.from_bytes(bytes(v for p in pixels for v in p),'big')
    ov,ol,ou,od,gr,gb=model.tick(rst,user,valid,last,data)
    valid_outputs+=ov;cycles+=1
    out.write(f'{rst} {user} {valid} {last} {data:024x} {ov} {ol} {ou} {od:024x} {gr:04x} {gb:04x}\n')
def frame(kind=0,combined=False,gap=160,groups=64):
    global frames
    frames+=1
    if not combined:
        emit(user=1)
        for _ in range(rng.randrange(0,12)):emit()
    for g in range(groups):
        if g%7==2:
            for _ in range(rng.randrange(1,4)):emit()
        if kind==0:p=[(72+i*11,120+i*7,180-i*9) for i in range(4)]
        elif kind==1:p=[(180-i*13,120+i*7,72+i*9) for i in range(4)]
        elif kind==2:p=[(255,255,255),(0,0,0),(255,4,4),(4,4,255)]
        elif kind==3:p=[(40,150,40),(50,200,50),(150,50,150),(240,20,20)]
        else:p=[tuple(rng.randrange(256) for _ in range(3)) for i in range(4)]
        emit(user=int(combined and g==0),valid=1,last=int(g%8==7),pixels=p)
    for _ in range(gap):emit()
for _ in range(4):emit(rst=0)
frame(0,combined=True);frame(0);frame(1);frame(2);frame(3);frame(4)
frame(1,gap=0,groups=23) # incomplete frame discarded at the next SOF
frame(0,combined=True)
frame(4,gap=0) # reset cancels in-flight pixels and division
for _ in range(3):emit(rst=0)
frame(1,combined=True)
for i in range(30):frame(i%5,combined=bool(i%2),gap=[0,83,84,85,160][i%5])
# Keep a neutral reference while large colored targets change.
# Distinct lanes, all four target colors, clipped/dark exclusions, total
# neutral dropout and lighting transitions exercise actual gain adaptation.
neutral=(96,128,88)
for target in [(190,64,50),(55,185,50),(55,65,195),(185,170,50)]:
    for _ in range(5):
        frames+=1
        emit(user=1)
        for g in range(64):
            emit(valid=1,last=int(g%8==7),pixels=[neutral,neutral,target,target])
        for _ in range(170):emit()
for _ in range(5):
    frames+=1
    emit(user=1)
    for g in range(64):
        emit(valid=1,last=int(g%8==7),pixels=[(200,55,55)]*4)
    for _ in range(170):emit()
for n in range(36):
    frames+=1
    emit(user=1)
    p=[(112,128,104),(127+n%2,128,128),(0,0,0),(255,240,250)]
    for g in range(64):emit(valid=1,last=int(g%8==7),pixels=p)
    for _ in range(170):emit()

for _ in range(200):emit()
out.close()
with (root/'ratio_vectors.txt').open('w') as f:
    cases=[(0,0,0),(0,1,1),(1,0,10),(1,10,0),(1000000,2000000,250000),
           ((1<<28)-1,1,(1<<28)-1),(1,(1<<28)-1,1)]
    cases.extend(tuple(rng.randrange(1<<28) for _ in range(3)) for _ in range(505))
    for g,r,b in cases:f.write(f'{g:x} {r:x} {b:x} {ratio(g,r):x} {ratio(g,b):x}\n')
(root/'awb_unit_reference.json').write_text(json.dumps({'cycles':cycles,'frame_requests':frames,
    'valid_output_beats':valid_outputs,'divider_cases':len(cases),'full_frame_beats':64},indent=2))
print('AWB_UNIT_REFERENCE_GENERATED',cycles,frames,valid_outputs,len(cases))
