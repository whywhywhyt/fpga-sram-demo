"""Mathematical limits, not measured camera color accuracy."""
import json
from pathlib import Path
R=Path(__file__).resolve().parents[1]
def tone(p):
    peak=max(p)
    s=0 if peak<=8 else (peak-8)*4 if peak<40 else 128 if peak<85 else (3*(255-peak)+3)//4
    return tuple((c*(256+s)+128)//256 for c in p)
gray=[tone((x,x,x))[0] for x in range(256)]
assert all(a<=b for a,b in zip(gray,gray[1:]))
assert gray[0]==0 and gray[-1]==255
assert gray[:9]==list(range(9))
assert max(y-x for x,y in enumerate(gray))<=48
rows=[]
for name,p in [('dark neutral',(16,16,16)),('gray64',(64,64,64)),('gray128',(128,128,128)),('gray192',(192,192,192)),
    ('red',(96,24,20)),('green',(20,96,24)),('blue',(20,24,96)),('yellow',(96,90,20)),('skin',(128,88,64)),('white',(255,255,255))]:
    q=tone(p);rows.append(dict(name=name,input=p,output=q))
    for i in range(3):
        assert p[i]<=q[i]<=255 and q[i]<=p[i]*1.5+0.5
        for j in range(3):assert abs(q[i]*p[j]-q[j]*p[i])<=(p[i]+p[j])/2
(R/'reports/tone_synthetic_assessment.json').write_text(json.dumps(dict(
    measured_camera_validation=False,peak_monotonic=True,maximum_gray_lift=max(y-x for x,y in enumerate(gray)),
    max_gain=1.5,reference_cases=rows,gray_lut=gray),indent=2),encoding='utf-8')
print('PASS tone math: monotonic 256-level neutral ramp, preserved near-black and white, maximum +48 codes, common gain <=1.5')
