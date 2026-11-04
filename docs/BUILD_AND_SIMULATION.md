# 重新编译与仿真

冻结版本为 `sc520_cal_final_2026-11-01`。下文为复现入口；本次仓库整理没有重新综合、运行40套仿真或访问USB设备。

## 先核验文件

在仓库根目录执行（Python 3.9+，标准库即可）：

```powershell
python tools/verify_repository.py
```

可保存独立记录：

```powershell
python tools/verify_repository.py --json logs/repository_check.json
```

核验覆盖原清单、展开源码与原ZIP一致性、TD源文件引用、构建输入、仿真输入/成功日志及固件。没有连接板卡或写入Flash。

## TD 重新编译

1. 克隆到短英文路径；建议 `C:/f/fpga-sram-demo`。
2. 安装 Anlogic TD 6.2.1 / 6.2.168116，并满足其设备支持及许可要求。
3. 打开 `engineering/candidates/sc520_cal_final_2026-11-01/candidate/sc520_shapes/td_project/camera_to_dsi_display.al`。
4. 通过工程文件清单从综合开始构建，随后布局布线，检查最终建立/保持时间与TNS。不要把目录内所有RTL文件重新批量加入工程。
5. 原 `tools/build.ps1` 和 `close_timing.ps1` 保留了原电脑盘符、TD路径及Resume逻辑，仅作追溯；换机器先适配真实环境，不直接依赖旧Resume数据库。
6. 修改源码后，旧BIT、SVF与回执均只代表冻结版本。重新编译通过后生成新的SRAM SVF并记录新哈希，不能只修改源码继续使用旧成功回执。

工程 `.al` 为TD输出的原生XML式格式，含TD专用选项文本；本仓库核验只读其中File引用，保留冻结字节，不用通用XML序列化工具重写。

## ModelSim 仿真

工作目录：

```powershell
cd engineering/candidates/sc520_cal_final_2026-11-01/sim
```

安装 ModelSim Intel Starter 18.1 或兼容仿真器后，先适配 `modelsim.ini` 中指向原电脑安装目录的库映射，再使用相应DO脚本。例如：

```powershell
vsim -c -do run_caption_font.do
vsim -c -do run_spatial_calibration.do
vsim -c -do run_paint_colors.do
```

上述命令是仿真入口，不是声称本次已经重跑。完整既有检查列表和日志SHA256见根目录 `evidence/simulation_receipt.json`，其中记录40套检查并明确区分继承、恢复核验及针对性运行；日志与输入文件已在本次完整性检查中核对。

原 `reproduce_old_failure.do` 用于复现旧问题，不属于“新版本应该全部成功”的默认测试入口。不可直接把所有DO文件无差别作为通过套件。

## SRAM 展示

根目录三个CMD分别用于下载、只核验文件、检查连接。使用其调用的 `tools/portable_sram.ps1`；不要直接运行原工程追溯目录中的 `program_sram.ps1`。

展示包依赖 Windows PowerShell 5.1。优先从Windows资源管理器双击对应CMD，或显式用系统 `powershell.exe`；不同PowerShell环境下的驱动枚举和模块加载不应混同。

下载是SRAM易失配置。工程不包含Flash写入流程；断电或重下后重采白场，灯墙需要先打开并按流程采背景。
