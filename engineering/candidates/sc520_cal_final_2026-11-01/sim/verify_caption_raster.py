"""Compare RTL HDMI overlay pixels with independently laid out complete fonts."""
from pathlib import Path
import json
from PIL import Image, ImageDraw, ImageChops

HERE = Path(__file__).resolve().parent
REPORTS = HERE.parent/'reports'
reference = json.loads((HERE/'caption_reference.json').read_text(encoding='utf-8'))
CODES = reference['codes']
ROWS = reference['rows']
BG = (88, 96, 104)
PANEL = (16, 24, 32)
WHITE = (240, 244, 248)
BLUE = (64, 159, 255)
# Accepted Latin 5x7 reference, expressed independently of the production mux.
LATIN = {
 '0':'01110100011100110101100111000101110',
 '1':'01110001000010000100001000110000100',
 '2':'11111010000010000010000011000101110',
 '3':'11110000010000101110000010000111110',
 '4':'00010000101111110010010100011000010',
 '5':'11110000010000111110100001000011111',
 '6':'01110100011000111110100001000001110',
 '7':'01000010000100000100000100000111111',
 '8':'01110100011000101110100011000101110',
 '9':'01110000010000101111100011000101110',
 'O':'01110100011000110001100011000101110',
 'N':'10001100111001110101110011100110001',
 'F':'10000100001000011110100001000011111',
}

def tile(char):
    im = Image.new('1', (16, 16))
    if char in CODES:
        rows = ROWS[str(CODES[char])]
        for y in range(16):
            for x in range(16):
                im.putpixel((x,y), (rows[y]>>(15-x))&1)
    elif char == ':':
        ImageDraw.Draw(im).rectangle((6,4,7,5), fill=1)
        ImageDraw.Draw(im).rectangle((6,10,7,11), fill=1)
    elif char in LATIN:
        bits = int(LATIN[char], 2)
        for y in range(14):
            row = (bits >> ((y//2)*5))&31
            for x in range(2,12):
                im.putpixel((x,y), (row>>(4-(x-2)//2))&1)
    elif char != ' ':
        raise ValueError(char)
    return im

def text(im, xy, value, ink=WHITE, scale=1):
    x,y = xy
    for char in value:
        mask = tile(char)
        if scale != 1:
            mask = mask.resize((16*scale,16*scale), Image.Resampling.NEAREST)
        im.paste(ink, (x,y,x+mask.width,y+mask.height), mask)
        x += 16*scale

def rect(im, xy):
    x0,y0,x1,y1 = xy
    ImageDraw.Draw(im).rectangle((x0,y0,x1-1,y1-1), fill=PANEL)

names = ['彩色原图','灰度图像','二值图像','边缘检测','图像增强','颜色形状识别','运动检测','卡通画面']
walls = ['待开启','采集中','流光','绘画','定格','重新采集','涟漪','关闭']
cals = ['未校准','采集中','计算中','ON','未校准','失败','ON','未校准']
checks = 0
for f in range(8):
    expected = Image.new('RGB', (1280,720), BG)
    rect(expected, (180,24,396 if f==5 else 332,72))
    text(expected, (192,32), names[f], scale=2)
    if f in (2,3,4,5,7):
        rect(expected, (184,80,264 if f==4 else 296,112))
        text(expected, (192,88), {2:'阈值:104',3:'阈值:112',4:'强度:中',5:'色差:040',7:'阈值:096'}[f])
    rect(expected, (16,672,144,704))
    ink = (96,224,160) if f in (3,6)  else (255,152,96) if f==5 else (255,208,128)
    text(expected, (24,680), '校色: '+cals[f], ink)
    wall_text = '灯墙:'+walls[f]
    left = 1256-len(wall_text)*16
    rect(expected, (left-8,672,1264,704))
    text(expected, (left,680), wall_text, BLUE)
    if f == 6:
        rect(expected, (944,56,1264,88))
        text(expected, (952,64), '运动量 123')
        draw = ImageDraw.Draw(expected)
        draw.rectangle((1120,68,1247,75),fill=(40,52,64))
        draw.rectangle((1120,68,1151,75),fill=(255,208,96))
    actual = Image.open(REPORTS/f'caption_rtl_{f}.ppm').convert('RGB')
    assert actual.size == (1280,720)
    for region in [(176,16,416,120),(0,664,224,712),(992,664,1280,712),(936,48,1272,96)]:
        # Logo ends at x=176, latency ends at y=48; neither belongs here.
        difference = ImageChops.difference(actual.crop(region), expected.crop(region))
        if difference.getbbox():
            difference.save(REPORTS/f'caption_mismatch_{f}.png')
            raise AssertionError(f'frame {f} region {region}: incorrect glyph, padding, width or color; local difference {difference.getbbox()}')
        checks += (region[2]-region[0])*(region[3]-region[1])
    actual.save(REPORTS/f'caption_rtl_{f}.png')

# Use actual RTL output crops, enlarged with nearest-neighbor pixels, for QA.
sheet = Image.new('RGB', (864,840), (32,40,48))
for slot,f in enumerate((0,4,5,7)):
    actual = Image.open(REPORTS/f'caption_rtl_{f}.png')
    sheet.paste(actual.crop((176,16,416,120)).resize((480,208), Image.Resampling.NEAREST), (0,slot*210))
    sheet.paste(actual.crop((1088,664,1280,712)).resize((384,96),Image.Resampling.NEAREST), (480,slot*210+20))
sheet.save(REPORTS/'字幕实际RTL预览.png')
result = dict(passed=True, compared_pixels=checks, modes=8, wall_states=8, cal_off_retained=False, wall_rgb='409fff', source='RTL output after HDMI panels; unchanged Logo separately covered by full composite regression')
(REPORTS/'caption_pixel_verification.json').write_text(json.dumps(result, ensure_ascii=False, indent=2), encoding='utf-8')
print(f'PASS independent caption pixels: {checks} exact pixels; complete glyphs, title/strength/wall margins, all wall strings blue, CAL OFF removed')
