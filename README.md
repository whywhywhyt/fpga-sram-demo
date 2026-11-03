# FPGA 全功能 SRAM 展示工程

本仓库导入 2026-11-01 交接包中的最新工程 **`sc520_cal_final_2026-11-01`**，保留完整源码、IP、约束、仿真、历史验证材料和便携 SRAM 下载工具。仓库应保持 **Private（私有）**。

## 工程入口

- TD 工程：[camera_to_dsi_display.al](engineering/candidates/sc520_cal_final_2026-11-01/candidate/sc520_shapes/td_project/camera_to_dsi_display.al)
- RTL、约束和 IP：`engineering/candidates/sc520_cal_final_2026-11-01/candidate/sc520_shapes/`
- 仿真：`engineering/candidates/sc520_cal_final_2026-11-01/sim/`
- 构建脚本和历史报告：同版本目录下的 `tools/` 和 `reports/`
- 交接版本和固件哈希：[VERSION.json](VERSION.json)

目标硬件为 HX1P35A（PH1P35MDG324 -3）与 SC520CS 摄像头；开发工具版本为 Anlogic TD 6.2.1 / 6.2.168116。重新编译时建议将仓库克隆到较短的英文路径，并从综合开始重建。原构建脚本可能含原电脑路径，使用前需按本机环境调整。

## 原交接资料

- [先读我：下载与展示](00_先读我_下载与展示.txt)
- [全部功能与按键](01_全部功能与按键.md)
- [全功能拍摄流程](02_全功能拍摄流程.md)
- [USB 驱动与故障排查](03_USB驱动与故障排查.md)
- [硬件接线与重编译](04_硬件接线与重编译.md)
- [工程状态与交接说明](05_给接续工程师或AI.md)

直接展示的入口是根目录 `01_download_sram.cmd`；离线文件检查入口是 `02_validate_only.cmd`。`sram/` 保存已编译 bit 和 SVF，`hardware/openocd/` 保存便携下载工具及原始许可，`test_cards/` 保存测试图卡。

## 导入和验证范围

导入时保留交接包文件原始字节，并将 `工程源码_可选.zip` 展开到 `engineering/`，便于直接浏览和版本管理；原源码 ZIP 仍保留以满足原交接包清单校验。已核验原 `MANIFEST_SHA256.json` 的全部文件哈希和 TD 工程文件引用，记录见 [IMPORT_VERIFICATION.json](IMPORT_VERIFICATION.json)。

`evidence/`、`reports/` 内的仿真、时序、资源和 SRAM 下载记录来自原交接包，属于历史证据。本次 Git 导入未重新综合、运行仿真或操作硬件，不表示接收电脑已通过实机或视觉验收。当前固件仅用于 SRAM 下载，掉电后不保留。
