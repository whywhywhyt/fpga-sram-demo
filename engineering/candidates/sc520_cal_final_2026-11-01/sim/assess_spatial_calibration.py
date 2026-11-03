"""Independent synthetic white-field assessment; never uses photographed RGB."""
from pathlib import Path
import json, math
R=Path(__file__).resolve().parents[1]
def raw(x,y,level=100):
    def linear(a,m,z):
        if x<=128:return a
        if x>=1152:return z
        return a+(m-a)*(x-128)/512 if x<=640 else m+(z-m)*(x-640)/512
    return tuple(round(v*level/100) for v in (linear(128,80,96),100+(y%3)-1,linear(96,72,128)))
samples=[[(x,y) for y in range(92,629,4) for x in range(k-64,k+64,16)] for k in (128,640,1152)]
sums=[[sum(raw(x,y)[c] for x,y in band)*4 for c in range(3)] for band in samples]
knots=[(g*4096//r,g*4096//b) for r,g,b in sums]
global_sum=[sum(raw(x,360)[c] for x in range(1280)) for c in range(3)]
global_gain=(global_sum[1]*4096//global_sum[0],global_sum[1]*4096//global_sum[2])
def interp(x,c):
    if x<=128:return knots[0][c]
    if x>=1152:return knots[2][c]
    a=0 if x<=640 else 1;start=(128,640)[a]
    return knots[a][c]+(knots[a+1][c]-knots[a][c])*(x-start)//512
def out(pixel,gain):
    return min(255,pixel[0]*gain[0]//4096),pixel[1],min(255,pixel[2]*gain[1]//4096)
results=[]
for level in (60,100,140):
    before=[];after=[];points=[]
    for x in range(0,1280,4):
        p=raw(x,360,level)
        a=out(p,global_gain);b=out(p,(interp(x,0),interp(x,1)))
        before.extend((a[0]-a[1],a[2]-a[1]));after.extend((b[0]-b[1],b[2]-b[1]))
        if x in (128,640,1152):points.append(dict(x=x,raw=p,global_awb=a,spatial=b))
    rmse=lambda e:math.sqrt(sum(v*v for v in e)/len(e))
    # Three-knot linear gain interpolation approximates an inverse color field;
    # include one output code for 8-bit input/output quantization at low levels.
    assert rmse(after)<rmse(before)*.2+1.0
    results.append(dict(level=level,global_white_chroma_rmse=rmse(before),
                        spatial_white_chroma_rmse=rmse(after),max_local_chroma_error=max(map(abs,after)),samples=points))
report=dict(synthetic_only=True,hardware_validated=False,calibration_knots_q4_12=knots,
    independent_raw_sums=sums,samples_per_zone_per_capture=len(samples[0])*4,
    assessments=results,limitation='Constructed smooth horizontal color field; real optical or mixed-light cast may differ. Not an observed improvement or calibrated physical coefficient set.')
(R/'reports/spatial_synthetic_assessment.json').write_text(json.dumps(report,indent=2),encoding='utf-8')
print('SPATIAL_SYNTHETIC_ASSESSMENT_PASSED_ONLY_SYNTHETIC')
print(json.dumps(results,indent=2))
