"""Export the exact verified SRAM filming build; never connect to hardware."""
from pathlib import Path
from datetime import datetime, timezone, timedelta
import hashlib
import html
import json
import re
import shutil
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
ASSETS = Path(__file__).resolve().parent
NAME = 'sc520_cal_final_2026-11-01'
SOURCE = ROOT/'candidates'/NAME
STAMP = datetime.now(timezone(timedelta(hours=8))).strftime('%Y%m%d_%H%M%S')
OUT = ROOT/'handoffs'/('FPGA_SRAM_Demo_'+STAMP)
OUT.mkdir(parents=True, exist_ok=False)
CANDIDATE = OUT/'engineering/candidates'/NAME

def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def sha(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        for b in iter(lambda:f.read(1048576),b''): h.update(b)
    return h.hexdigest()
def write(rel,text,bom=True):
    p=OUT/rel; p.parent.mkdir(parents=True,exist_ok=True)
    p.write_text(text,encoding='utf-8-sig' if bom else 'utf-8',newline='')
def copy(source,dest):
    dest.parent.mkdir(parents=True,exist_ok=True); shutil.copy2(source,dest)

b=read(SOURCE/'reports/build_receipt.json')
s=read(SOURCE/'reports/simulation_receipt.json')
v=read(SOURCE/'reports/offline_validation_receipt.json')
assert b['completed'] and b['timing_passed'] and v['passed'] and s['all_passed'] and len(s['suites'])==40
assert b['bit_sha256']==v['bit_sha256']
receipts=sorted((SOURCE/'reports').glob('interactive_sram_*/receipt.json'),key=lambda p:p.parent.name)
receipt=receipts[-1]; r=read(receipt)
assert r['sram_downloaded'] and r['done_passed'] and not r['flash_written']
assert r['bit_sha256'].lower()==b['bit_sha256'].lower()

# Preserve every source/IP, .al reference and hash-verified regression dependency.
# Rebuilds start from synthesis, so intermediate databases and wave caches are omitted.
project=SOURCE/'candidate/sc520_shapes'
for p in project.rglob('*'):
    if not p.is_file(): continue
    rel=p.relative_to(project)
    if 'camera_to_dsi_display_Runs' in rel.parts:
        if p.suffix.lower() in {'.db','.timing','.logw'}: continue
        if p.name.startswith('td_') and p.suffix=='.log': continue
    copy(p,CANDIDATE/'candidate/sc520_shapes'/rel)
for p in (SOURCE/'sim').rglob('*'):
    if not p.is_file():continue
    rel=p.relative_to(SOURCE/'sim')
    if any(k.startswith('work') or k=='__pycache__' for k in rel.parts) or p.suffix in {'.pyc','.wlf'}:continue
    copy(p,CANDIDATE/'sim'/rel)
required_reports={'build_receipt.json','simulation_receipt.json','offline_validation_receipt.json',
 'scope_audit.json','source_changes.patch','caption_pixel_verification.json','simulation_resume_evidence.json',
 'validation_plan.json','td_20261101_151410_syn_1.log','td_20261101_151410_phy_1.log'}
required_reports.update(x['log'] for x in s['suites'])
for name in required_reports:copy(SOURCE/'reports'/name,CANDIDATE/'reports'/name)
for p in (SOURCE/'reports').glob('*.png'):copy(p,CANDIDATE/'reports'/p.name)
for rel,h in s['sha256'].items():
    target=CANDIDATE/rel
    if not target.exists():copy(SOURCE/rel,target)
    assert sha(target)==h.lower(),rel
for rel,h in b['source_sha256'].items():assert sha(CANDIDATE/'candidate/sc520_shapes'/rel)==h.lower(),rel
for suite in s['suites']:assert sha(CANDIDATE/'reports'/suite['log'])==suite['log_sha256'].lower()
for raw in re.findall(r'<File\s+Path="([^"]+)"',(project/'td_project/camera_to_dsi_display.al').read_text(encoding='utf-8-sig')):
    assert (CANDIDATE/'candidate/sc520_shapes/td_project'/html.unescape(raw)).is_file(),raw
for p in (SOURCE/'tools').glob('*'):
    if p.is_file():copy(p,CANDIDATE/'tools'/p.name)
shutil.copytree(ROOT/'candidates/sc520_lightwall_2026-10-23/tools/xpack-openocd-0.12.0-7',OUT/'hardware/openocd')
copy(ASSETS/'portable_sram.ps1',OUT/'tools/portable_sram.ps1')
copy(ASSETS/'make_package.py',OUT/'engineering/package_exporter.py')
phy=project/'td_project/camera_to_dsi_display_Runs/phy_1'
copy(phy/'camera_to_dsi_display.bit',OUT/'sram/demo.bit')
copy(receipt.parent/'candidate.svf',OUT/'sram/demo.svf')
copy(receipt.parent/'candidate_done.svf',OUT/'sram/done.svf')
copy(receipt,OUT/'evidence/source_board_sram_receipt.json')
copy(receipt.parent/'program.log',OUT/'evidence/source_board_program.log')
copy(receipt.parent/'generate.log',OUT/'evidence/source_board_svf_generation.log')
for name in ('build_receipt.json','simulation_receipt.json','offline_validation_receipt.json','scope_audit.json','caption_pixel_verification.json'):
    copy(SOURCE/'reports'/name,OUT/'evidence'/name)
copy(phy/'camera_to_dsi_display_phy.area',OUT/'evidence/final_area.rpt')
copy(phy/'final_timing.rpt',OUT/'evidence/final_timing.rpt')
assert sha(OUT/'sram/demo.bit')==b['bit_sha256'].lower()
assert sha(OUT/'sram/demo.svf')==r['generated_svf_sha256'].lower()
assert sha(OUT/'sram/done.svf')==r['done_svf_sha256'].lower()
write('sram/transport.cfg','''adapter driver ftdi
ftdi vid_pid 0x0403 0x6042
ftdi channel 0
ftdi layout_init 0x0008 0x000b
transport select jtag
adapter speed 1000
jtag newtap fpga tap -irlen 8 -expected-id 0x4808f0e7
''',False)
write('sram/program.cfg','''source [find transport.cfg]
init
svf demo.svf -quiet
svf done.svf -quiet
echo SRAM_AND_DONE_PASSED
shutdown
''',False)
write('sram/verify.cfg','''source [find transport.cfg]
# Deliberately exits BEFORE init; does not open USB or access FPGA.
echo PORTABLE_CONFIG_OK_NO_HARDWARE
shutdown
''',False)
metadata=dict(package='FPGA SRAM filming handoff',candidate=NAME,created_at=datetime.now(timezone(timedelta(hours=8))).isoformat(),
 sram_only=True,flash_commands_included=False,bit_sha256=sha(OUT/'sram/demo.bit'),svf_sha256=sha(OUT/'sram/demo.svf'),
 done_svf_sha256=sha(OUT/'sram/done.svf'),source_board_receipt_time=r['timestamp'],
 source_board_sram_done_passed=True,receiving_board_tested=False,visual_accepted=False,
 source_snapshot_included=True,
 device='PH1P35MDG324 -3',board='HX1P35A',usb_vid_pid='0403:6042',jtag_id='0x4808F0E7',
 calibration_coefficients_persist=False,setup_wns_ns=b['setup_wns_ns'],hold_wns_ns=b['hold_wns_ns'],
 slice=b['slice'],eram=b['eram'],dsp=b['dsp'],simulation_suites=40,
 entrypoint='01_download_sram.cmd',requires=['Windows 10/11 x64','Windows PowerShell 5.1','A/MI_00 WinUSB; B/MI_01 FTDIBUS'])
write('VERSION.json',json.dumps(metadata,ensure_ascii=False,indent=2))
for filename,option in [('01_download_sram.cmd',''),('02_validate_only.cmd',' -ValidateOnly'),('03_check_connection.cmd',' -CheckConnection')]:
    write(filename,'\r\n'.join(['@echo off','setlocal','cd /d "%~dp0"',
      '"%SystemRoot%\\System32\\WindowsPowerShell\\v1.0\\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0tools\\portable_sram.ps1"'+option,
      'set "FPGA_RESULT=%ERRORLEVEL%"','echo.','if not "%FPGA_RESULT%"=="0" echo FAILED. See message above and the logs folder.',
      'pause','exit /b %FPGA_RESULT%','']),False)
write('00_先读我_下载与展示.txt',f'''FPGA全功能SRAM拍摄版交接包（2026-11-01）

本包是刚才在原开发板下载成功的同一版本：{NAME}。
只临时下载到SRAM，不写Flash。断电或复位后须按实际状态重新下载、重新采白。

【队友最快使用流程】
1. 将整个ZIP解压到本地短路径，例如 C:\\FPGA_DEMO。不要在ZIP内部直接双击，不要只单独转发bit或cmd。
2. 给HX1P35A开发板独立供电，用有数据功能的USB线连接开发板下载口与电脑。
   摄像头和HDMI用于展示；仅SRAM下载不需要连接灯板。
3. 双击 02_validate_only.cmd，成功应显示 OFFLINE_VALIDATION_PASSED_NO_HARDWARE_ACCESSED。
4. 双击 03_check_connection.cmd，成功应显示 A=WINUSB、B=FTDIBUS。
   新电脑若驱动不匹配，先看 03_USB驱动与故障排查.md；本包不会自动改驱动。
5. 双击 01_download_sram.cmd，最后出现 SUCCESS: SRAM and DONE passed 才表示下载成功。
   本包已附OpenOCD、预生成SVF、DONE校验及已编译bit；直接展示无需TD、Python、ModelSim或重新编译。
6. 等10秒，短按K2回原图。用均匀照明的白纸覆盖整个画面，同时按K1+K2约2秒，
   全部松开后保持白场不动约1秒，左下角ON表示校色启用。没有CAL OFF。
7. 移开白纸，短按K1依次展示八图像模式。灯墙默认关闭，长按K3约2秒打开；
   在原图下清空互动区，短按K3采灯墙背景。灯墙采背景与白纸校色是两件事。
8. 拍摄期间保持开发板独立供电，不按复位。USB若只作下载可在成功后拔下；靠USB供电则不能拔。

【包内主要内容】
01_download_sram.cmd：SRAM下载并校验DONE
02_validate_only.cmd：离线校验文件、资源时序证据和便携工具，不访问USB
03_check_connection.cmd：读取USB连接与驱动状态，不下载
01_全部功能与按键.md、02_全功能拍摄流程.md：操作和拍摄顺序
03_USB驱动与故障排查.md：新电脑驱动、No hardware及CAL FAIL排查
04_硬件接线与重编译.md：已验证接线、TD工程入口和后续编译说明
05_给接续工程师或AI.md：版本边界与未完成事项
sram：当前bit、SRAM SVF与DONE SVF
hardware/openocd：便携下载工具及原始许可证
engineering：完整源代码、IP、引脚/时序约束、仿真向量/脚本及最终报告
evidence：原开发板下载成功记录（历史凭据，不代表接收板已测试）
logs：运行下载入口后自动生成队友电脑自己的日志与成功回执

本版主要变化：完整清晰中文字幕、紧凑黑框、蓝色灯墙状态；CAL OFF已移除，
K2长短按均只回原图，有效白场系数持续应用；灯墙长K3开关。请勿混用旧包K1开灯、K3长按清屏等操作。

已通过40套回归和最终时序；Slice {b['slice']}/21216，ERAM {b['eram']}/108，DSP {b['dsp']}/40，
Setup {b['setup_wns_ns']:+.3f}ns，Hold {b['hold_wns_ns']:+.3f}ns。物理时序余量很小，修改后必须重新综合布线与验证。
原板最近下载成功时间：{r['timestamp']}。
bit SHA256：{b['bit_sha256']}。
原工程完整保留；此次仅导出文件，不重新下载或改变当前板的运行状态。
''')
write('01_全部功能与按键.md','''# 当前全功能与按键

本文件适用于 `sc520_cal_final_2026-11-01`。普通短按小于半秒，松手后执行；不要套用10月31日旧包的长K1开灯操作。

## 图像与处理

摄像头实时采集，DDR缓存，HDMI 1280×720显示。八模式依次是：彩色原图、灰度、二值化、Prewitt边缘、图像增强、颜色形状识别、运动检测、卡通化。启动默认边缘模式，短K2随时回原图。

图像处理含自动白平衡、按键触发白场标定与空间色彩补偿、显示中间调提亮、温和降噪及三档增强。白场校色不是全自动寻找白纸：需先摆好均匀白纸再按键。降噪和提亮不代表噪点、偏色已经完全消除。

颜色识别支持红、黄、绿、蓝；形状支持圆、三角、矩形，含未知分类，正方形归矩形。目标框按颜色显示，框附近显示颜色、形状和中心坐标，最多显示4个目标。建议实体红块移动展示坐标，电脑大色块和实心几何图案静态展示类别。传统颜色分割、连通域和几何特征，没有使用CNN或YOLO。

运动检测显示主要变化区域框及运动量。运动量不是实际物理速度；处理延时也不是摄像头到人眼的完整延迟。卡通化显示颜色分层与边缘描线。

## 按键总表

|操作|功能|
|---|---|
|短K1|原图→灰度→二值→边缘→增强→识别→运动→卡通→原图|
|短K2或单独长K2|回彩色原图，不关闭校色|
|K1+K2同时约2秒，全部松开|采白校色，成功后持续应用；按久不清表|
|单独长K3约2秒，任意图像模式|灯墙开/关；重新开启回流光|
|二值/边缘/识别/卡通，短K3/K4|对应阈值增加/减少；运动模式无此短按调参|
|增强，短K3/K4|增强低/中/高升档/降档|
|原图且灯墙开，短K4|流光→绘画→定格→彩虹涟漪→流光|
|流光/定格/涟漪，短K3|采背景，并返回流光|
|绘画，短K3|落笔/抬笔|
|绘画，长K4约1秒|换笔色并抬笔；之后短K3落笔|
|绘画，K3+K4同时约1秒|清屏并抬笔；之后短K3落笔|

## 校色

采白前固定摄像头和光照，白纸覆盖整个视场，避开手影、彩色边缘、反光和过曝；K1+K2约2秒全部松开，保持约1秒等待ON。采集中/计算中不是完成；FAIL表示此次采样不满足条件，调整白场后重采。失败重采保留已有有效系数，但失败提示仍需处理。

本版不提供CAL OFF，也不假装启动就有校色系数。断电/复位/重新下载后需要重新采白。采白自动算系数，无需逐色手动调RGB，同一光照下切换模式不用重新校色。

视频可说：“左下角ON表示白场校色已启用，用于减轻画面不同位置的偏色，让颜色更自然、均匀。”

## 灯墙四状态

双16×16灯板组成横向32×16。灯墙默认关闭，软件关灯会发送黑帧，外部5V仍存在。先K2回原图，长K3打开，固定机位、清空互动区，短K3采背景。

- 流光：空场全黑；物体进入对应区域有青色轮廓，移动留彩色拖尾，停住当前位置保持，离开渐隐。颜色由程序生成，不要求物体本身是青色。
- 绘画：用红色小卡片/笔帽作定位物，在HDMI画布区域内移动。先看定位十字，再短K3落笔，慢画横线、弧线或波浪；抬笔可移动而不连线。笔色青→蓝→紫→红→橙→绿，与红色定位物的颜色分开。
- 定格：保持画布，适合作品特写。
- 彩虹涟漪：前景互动，红色起点和彩虹色带扩散渐隐；保留已认可的原彩虹方案。

绘画取景区域为摄像画面约x320～959、y200～519，映射32×16；红色目标建议约4～6厘米、哑光、背景无其它红物。分辨率适合粗轮廓与简单符号，不适合精细字迹。遮挡和照明变化也可能被背景比较当作前景，不是专用手分类。

摄像头机位或照明变化后应重采灯墙背景。白纸校色与空场采背景需依次进行，不要拿白纸当灯墙空背景。
''')
guide=(ROOT/'reports/2026-11-01_全功能拍摄流程与按键.md').read_text(encoding='utf-8-sig')
guide=guide[:guide.index('## 录制时的版本记录')]+'''## 版本记录

本包当前版本和位流哈希见VERSION.json。队友下载成功后，自己的凭据位于logs/日期时间/receipt.json。
evidence目录是原开发板的成功记录，不等于接收板已下载或视觉验收。
'''
guide=guide.replace('`reports/color_test_cards_20261031/known_colors_shapes.html`','`test_cards/known_colors_shapes.html`')
write('02_全功能拍摄流程.md',guide)
cards=ROOT/'reports/color_test_cards_20261031'
if cards.exists():shutil.copytree(cards,OUT/'test_cards')
write('03_USB驱动与故障排查.md','''# USB驱动与故障排查

下载仅需开发板供电及电脑USB下载线，灯板不影响电脑是否找到下载器。摄像头、HDMI和灯板用于展示效果。

## 接收电脑所需驱动

便携入口使用USB `VID_0403&PID_6042`，接口A `MI_00` 为 **WinUSB**，接口B `MI_01` 为 **FTDIBUS**。这与TD默认D2XX驱动的要求可能不同。已经能通过本包连接检查的电脑保持驱动不动。

新电脑建议先用开发板厂家/TD官方驱动或[FTDI官方VCP驱动](https://ftdichip.com/drivers/vcp-drivers/)识别设备，再检查两接口。只有当A驱动不是WinUSB导致本包报Driver mismatch时，才需要手动将A改为WinUSB。

可使用[Zadig官方网站](https://zadig.akeo.ie/)的工具，以管理员身份运行，Options→List All Devices，准确选择硬件ID `0403:6042`、Interface 0 / `MI_00` / 通道A，目标驱动选WinUSB。确认没有选到通道B、USB Composite父设备或别的USB设备，再执行安装。B保留FTDIBUS。驱动安装只在需要时手动完成；本包任何cmd/ps1都不会替换驱动。

本包不内置TD或驱动安装程序，便携下载工具的运行仍依赖上述USB驱动正确安装。若不愿更改现有TD驱动，可以在已安装TD的电脑通过TD下载器选`sram/demo.bit`执行SRAM下载；不要选择Flash编程。此方法以该电脑的TD硬件识别结果为准。

## 常见故障

|现象|处理|
|---|---|
|USB-JTAG not ready / No hardware|确认开发板供电，接的是下载口，数据线支持传输，换USB口并等几秒后重跑03_check_connection.cmd；不要先改工程|
|Driver mismatch|查看报出的A/B驱动服务，按上文配置；不要误改B或复合父设备|
|能识别USB但JTAG/读取ID失败|关闭TD下载器、其它OpenOCD或占用下载口的软件，再检查板供电和线缆；不更改器件ID或强制忽略失败|
|File changed or incomplete|重新完整解压原ZIP；不要混用旧bit、旧SVF、旧脚本；不要从ZIP内直接运行|
|Windows阻止执行|先确认收到的是本交接包并完整解压；cmd使用系统Windows PowerShell及仅本次进程的ExecutionPolicy Bypass，无需改全局策略；单位策略限制需由该电脑管理者处理|
|CAL FAIL|白纸铺满视场，光照均匀、不过曝，不用电脑彩色图案或普通场景采白；K1+K2约2秒全部松开，再保持白场1秒|
|灯墙全黑|默认关闭；长K3约2秒打开，K2原图，空场短K3采背景后伸手。再核对灯板5V、共地、信号线及第二板串接|
|仅一块灯板亮|检查第一块DOUT到第二块DIN及第二块独立5V/GND，断电后修线；本包输出512颗灯的数据|
|下载后恢复旧画面|断电会丢SRAM，板上Flash启动旧工程属于预期；重新下本包SRAM，不必改Flash|

成功依据是 `SUCCESS: SRAM and DONE passed` 和本机 `logs/.../receipt.json`。DONE通过只证明下载与状态读取成功，实时画面、校色、按键和双板显示仍需现场观察。
''')
write('04_硬件接线与重编译.md',f'''# 硬件接线与后续工程

目标硬件：HX1P35A；器件PH1P35MDG324，速度等级-3；SC520CS摄像头；HDMI显示器；两块WS2812B 16×16灯板横向32×16。

|节点|连接|
|---|---|
|FPGA P5 / J1第15脚|已验证转换模块3.3V侧输入通道|
|该通道对应5V侧输出|第一灯板DIN|
|第一灯板DOUT|第二灯板DIN|
|两块灯板5V|外部5V适配器正极并联分线，各自供电|
|两块灯板GND|外部5V适配器负极|
|FPGA J1第30脚GND、模块中央GND|与灯板GND和适配器负极共地|
|模块电源|沿用已验证3V3/5V接法；不把5V信号接普通FPGA IO|

模块具体通道按原实物已确认的3.3V输入→5V输出方向，不依据缺失照片推测A/B命名。灯板主电源用独立电源线，杜邦线用于信号；不要用FPGA的3V3给灯板供电。改线时开发板和灯板电源都关闭。双板电流依赖亮度，本工程有限亮，不按适配器额定值推断双板不限亮满白也可运行。

## 工程入口

`engineering/candidates/{NAME}/candidate/sc520_shapes/td_project/camera_to_dsi_display.al`

源文件、IP、引脚和时序约束使用该工程中的相对路径，已核对所有.al文件引用存在。工具版本Anlogic TD 6.2.1 / 6.2.168116；建议把整个交接包放到短英文路径，打开.al后从综合开始构建。仿真使用ModelSim Intel Starter 18.1或兼容环境；sim目录保留全部40套既有检查的脚本、向量和成功日志，原modelsim.ini中安装库路径需适配本机。

工程tools下原构建/时序脚本为工程追溯保留，含原电脑工具目录和短盘符处理。换电脑重新编译时先设置实际TD路径，不要直接运行原program_sram.ps1；展示下载统一使用包根目录01_download_sram.cmd。

省略了可再生的布局/综合数据库、仿真work和波形；完整源码、IP、约束、最终bit、area/timing报告及证据均已保留。修改源码后，旧SVF/bit仅代表此次冻结版本；必须重新编译通过、生成新SRAM SVF并重新校验，不能只改源码后继续用旧成功回执。

当前最终资源Slice {b['slice']}/21216，ERAM {b['eram']}/108，DSP {b['dsp']}/40；Setup {b['setup_wns_ns']:+.3f}ns，Hold {b['hold_wns_ns']:+.3f}ns，TNS均0。时序余量较小，不能放松约束冒充闭合。
''')
write('05_给接续工程师或AI.md','''# 冻结状态与接续边界

唯一展示版本为sc520_cal_final_2026-11-01，bit哈希见VERSION.json。此版从已下载成功的完整字幕工程派生，删除CAL OFF和长K2旁路、超长K1+K2清表。只改按键/校色启用策略/状态字幕，未借此变更校色公式、检测、灯效或亮度算法。

校色采用现有五点二维平滑空间补偿，不把本版宣传为新完成的九分区算法。自动白平衡与人工放置白纸、按键触发自动标定应分开说明。无有效启动系数时显示未校准，不能只改ON文字。无效重采不覆盖旧有效表；系数仅易失保存，没有Flash持久化。

40套回归中18套针对改动重新执行，22套核对依赖源码、向量与日志哈希后继承；并有字幕逐像素验证、最终资源/时序检查。源开发板已经SRAM/DONE成功，接收电脑的下载和实际显示结果需要自己检查。不要把历史source_board_receipt当作本机已成功下载，也不要把DONE当作视觉验收。

其它框稳定性/颜色形状/画质的进一步优化按用户要求暂停，当前不继续增加功能。历史偏暗和白场一致性已有改善反馈，但噪点、残余偏色和形状误识仍不等于彻底解决。不要把未实现功能写成已完成：没有CNN/YOLO、声音输出、可靠人员安全停机、任意手势分类或精细书写。

接收者只需展示时，使用根目录cmd；无需重编译。不自动改驱动，不写Flash，不随意改引脚/时钟或放松时序。原开发端的源码、旧位流和运行状态此次导出均保持。
''')
write('engineering/README.md','''# 工程快照

展示入口位于包根目录01_download_sram.cmd，使用固定已验证SVF，无TD依赖。
这里保留源码/IP、约束、仿真和最终证据。reports中的原电脑绝对路径与sram_downloaded字段是历史构建/下载记录，不代表接收电脑的状态。
省略可再生中间数据库与仿真work；改源码需从综合重建，不使用旧Resume。
''')

# Keep the primary handoff extractable on Windows systems with legacy MAX_PATH.
# The complete source/IP snapshot is retained as one optional nested ZIP, while
# the root package remains short enough to run the SRAM downloader immediately.
source_dir = OUT/'engineering'
source_zip = OUT/'工程源码_可选.zip'
with zipfile.ZipFile(source_zip,'w',compression=zipfile.ZIP_DEFLATED,compresslevel=6) as z:
    for p in sorted(source_dir.rglob('*')):
        if p.is_file(): z.write(p,Path('engineering')/p.relative_to(source_dir))
shutil.rmtree(source_dir)
for rel in ('00_先读我_下载与展示.txt','04_硬件接线与重编译.md'):
    p=OUT/rel
    s=p.read_text(encoding='utf-8-sig')
    s=s.replace('engineering：完整源代码、IP、引脚/时序约束、仿真向量/脚本及最终报告',
                '工程源码_可选.zip：完整源代码、IP、引脚/时序约束、仿真向量/脚本及最终报告（可选）')
    s=s.replace('`engineering/candidates/{NAME}/candidate/sc520_shapes/td_project/camera_to_dsi_display.al`',
                '`工程源码_可选.zip` 内的 `engineering/candidates/{NAME}/candidate/sc520_shapes/td_project/camera_to_dsi_display.al`')
    p.write_text(s,encoding='utf-8-sig',newline='')

manifest={p.relative_to(OUT).as_posix():sha(p) for p in sorted(OUT.rglob('*')) if p.is_file()}
write('MANIFEST_SHA256.json',json.dumps(manifest,ensure_ascii=False,indent=2))
export=dict(output=str(OUT),timestamp=STAMP,candidate=NAME,bit_sha256=b['bit_sha256'],file_count=len(manifest),
 source_sram_receipt=str(receipt),package_validation_pending=True,desktop_delivery_pending=True,hardware_accessed=False)
export_path=ROOT/'reports'/('SRAM交接包导出_'+STAMP+'.json')
export_path.write_text(json.dumps(export,ensure_ascii=False,indent=2),encoding='utf-8')
print(json.dumps(export,ensure_ascii=False,indent=2))
