# USB驱动与故障排查

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
