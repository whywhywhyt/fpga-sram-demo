"""Independent integer AWB reference, not a translation of serial divider RTL."""
def acceptable(pixel):
    return sum(pixel)>=96 and max(pixel)<240 and min(pixel)>=(max(pixel)+1)//2

def ratio(green,channel):
    return min(16384,max(2048,(green*4096)//channel)) if channel else 4096

def correction(pixel,gains):
    red,green,blue=pixel
    return min(255,red*gains[0]//4096),green,min(255,blue*gains[1]//4096)

def smooth(current,target):
    delta=target-current
    return current+(0 if abs(delta)<=24 else max(-64,min(64,delta//8)))

def frame_gains(pixels,active=(4096,4096),acquired=False,minimum=128):
    sums=[0,0,0];count=0
    for pixel in pixels:
        if acceptable(pixel):
            count+=1
            for c in range(3):sums[c]+=pixel[c]
    if count<minimum or sums[0]==0 or sums[2]==0:return None
    target=(ratio(sums[1],sums[0]),ratio(sums[1],sums[2]))
    return tuple(smooth(v,t) for v,t in zip(active,target)) if acquired else target

class CycleReference:
    """Direct sums/division; 3-stage stats snapshot then gain ready at +84."""
    def __init__(self,beats=64):self.beats=beats;self.clock=-1;self.reset()
    def reset(self):
        self.active=(4096,4096);self.pending=None;self.acquired=False
        self.collecting=False;self.pixels=[];self.groups=0
        self.jobs={};self.busy_until=-1;self.outputs={}
    def tick(self,rst,user,valid,last,word):
        self.clock+=1;c=self.clock
        if not rst:self.reset();return 0,0,0,0,4096,4096
        old_active=self.active;was_acquired=self.acquired
        if user:
            self.outputs.clear();self.collecting=True;self.pixels=[];self.groups=0
            if self.pending is not None:
                self.active=self.pending;self.acquired=True;self.pending=None
        # Three statistic registers precede the 80-cycle calculator/capture.
        if c in self.jobs:
            target=self.jobs.pop(c)
            self.pending=tuple(smooth(v,t) for v,t in zip(old_active,target)) if was_acquired else target
        pixels=[tuple((word>>shift>>offset)&255 for offset in (16,8,0)) for shift in (72,48,24,0)]
        if valid:
            processed=[correction(p,self.active) for p in pixels]
            packed=int.from_bytes(bytes(v for p in processed for v in p),'big')
            self.outputs[c+64]=(1,last,packed)
            if self.collecting:
                self.pixels.extend(pixels);self.groups+=1
                if self.groups==self.beats:
                    self.collecting=False
                    if c+3>self.busy_until:
                        target=frame_gains(self.pixels,minimum=max(128,(self.beats*4+127)//128))
                        if target is not None:self.jobs[c+84]=target;self.busy_until=c+83
        ov,ol,od=self.outputs.pop(c,(0,0,0))
        return ov,ol,user,od,*self.active
