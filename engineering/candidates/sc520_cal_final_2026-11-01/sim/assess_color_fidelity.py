"""Synthetic illuminant stress cases; NOT camera measurements or color calibration."""
from pathlib import Path
import json
from awb_reference import acceptable,frame_gains,correction,smooth

ROOT=Path(__file__).resolve().parents[1]
neutral=(96,128,88)
targets={"red":(190,64,50),"green":(55,185,50),
         "blue":(55,65,195),"yellow":(185,170,50)}

def old_target(pixels):
    pool=[p for p in pixels if 48<=sum(p)<720 and min(p)>=max(p)//4]
    return tuple(min(16384,max(2048,sum(p[1] for p in pool)*4096//
                  sum(p[k] for p in pool))) for k in (0,2))

rows=[]
for name,target in targets.items():
    pixels=[neutral]*128+[target]*384
    old=old_target(pixels)
    new=frame_gains(pixels)
    assert acceptable(neutral) and not acceptable(target)
    want=(128*4096//96,128*4096//88)
    assert new==want
    co,cn=correction(neutral,old),correction(neutral,new)
    err_old=max(co)-min(co);err_new=max(cn)-min(cn)
    assert err_new<=1 and err_new<err_old
    rows.append({"target":name,"old_gains":old,"new_gains":new,
                 "old_neutral_rgb":co,"new_neutral_rgb":cn,
                 "old_neutral_channel_spread":err_old,"new_neutral_channel_spread":err_new})

assert frame_gains([targets["red"]]*512,active=want,acquired=True) is None
assert not acceptable((255,240,250)) and not acceptable((10,10,10))
assert not acceptable((239,239,119)) and acceptable((239,239,120))
assert not acceptable((240,240,240))
for current in (2048,4096,8192,16384):
    for delta in (-5000,-513,-512,-25,-24,-1,0,1,24,25,511,512,513,5000):
        nxt=smooth(current,current+delta)
        assert abs(nxt-current)<=64
        if abs(delta)<=24:assert nxt==current
        elif delta>0:assert current<nxt<=current+delta
        else:assert current+delta<=nxt<current
gain=4096
for _ in range(200):gain=smooth(gain,6144)
assert abs(gain-6144)<=24

(ROOT/"reports/color_fidelity_synthetic.json").write_text(json.dumps({
    "scope":"Synthetic known RGB illuminant cases only; no real sensor calibration/visual claim",
    "scenes":rows,"max_per_frame_gain_step_q12":64,"deadband_q12":24,
    "reference_dropout_holds":True,"all_passed":True},indent=2),encoding="utf-8")
print("SYNTHETIC_COLOR_FIDELITY_ASSESSMENT_PASSED")
