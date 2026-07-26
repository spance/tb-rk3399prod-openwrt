# 硬件状态

本表依据适配期间采集的原厂和 OpenWrt 启动日志整理；原始调试日志不纳入清理后的工程。板级固定参数和以后升级时的回归检查项见 `HARDWARE-REFERENCE.md`。

| 项目 | 状态 | 关键结果 |
|---|---|---|
| UART2 | 已确认 | ttyS2，1500000 n8，earlycon 正常 |
| CPU | 已确认 | 4×A53 + 2×A72 全部上线，两个 cpufreq domain |
| PMIC | 已确认 | RK809；vdd_center、vdd_cpu_l、vdd_cpu_b、vdd_gpu 正常 |
| 温控 | 已确认 | CPU/GPU thermal zone、TSADC 及 A53/A72 两个 cpufreq cooling device 正常绑定；6 核满载 90 秒稳定，最高约 55.6 °C，未故意加热到降频点 |
| 硬件 watchdog | 已确认运行 | RK3399 DesignWare watchdog 已由 `procd` 启用，30 秒超时、5 秒喂狗；DTS 显式提供与 Linux 驱动回退值一致的 TOP 表 |
| TF | 已确认读写 | Linux 50 MHz/4-bit/IDMAC，实测约 5.9 MiB/s 写、18.8 MiB/s 读；U-Boot 25 MHz/PIO 可靠读取 FIT |
| eMMC | 已确认启动，CQE 已禁用 | 29.1 GiB，HS400 Enhanced Strobe、ADMA；正式内核使用 `SDHCI_QUIRK_BROKEN_CQE`，实机确认 `cmdq_en=0`；256 MiB 写入、同步与校验后 CQE recovery、MMC I/O 和 ext4 错误均为 0 |
| eMMC 正常系统 | 已确认启动 | 224 MiB `openwrt.img` 已从 eMMC 正常启动；SquashFS + 约 28.4 GiB ext4 `/overlay` 正常挂载 |
| 千兆网 | 已确认 | RTL8211E，1000/full；两个方向各 1800 秒均为 941 Mbit/s、197 GiB，硬件错误计数为 0 |
| 网络调优 | 已确认 | GMAC IRQ 在开机及接口 `ifup` 后均绑定 CPU4/A72，复测 942/941 Mbit/s、0 重传；S99 服务作为兜底，fw4 软件 flowtable 正常生成 |
| USB2 | 已确认枚举 | 两组 EHCI/OHCI 和板载 Hub |
| USB3 Type-A | 已确认高速读写 | 多种设备以 `5000M` 枚举；Lexar E300 2 TB/UAS 的 4 GiB direct read 约 319 MiB/s，测试后无新增 USB/UAS/SCSI 错误 |
| USB3 Type-C | 硬件高速已确认，自动重连待验收 | 正反插 CC/角色/VBUS 正常，`usb-role-switch` 可随插拔删除/重建 xHCI。完整重绑 FUSB302、DWC3 和 `tcphy0` 后 Lexar E300 以 UAS/5000M 枚举，4 GiB direct read 约 367 MB/s（350 MiB/s），无 USB/UAS/SCSI/I/O 错误。代码已修复同方向缓存及 PHY 初始化期间误入 USB2-only 路由两个问题，待新镜像完成交替方向热插拔、长时读写和 Loader 回归 |
| HDMI console | 已确认 | DRM/VOPB/DW-HDMI、fbcon 和 Linux 文本 console 已在显示器输出；串口继续保留 |
| PCIe | 控制器确认，端点待验收 | host/PHY/电源正常进入 probe；当前独立 x4 插座没有端点，training timeout 符合预期 |
| Mini-PCIe | USB2-only | 面向 LTE 模块，没有 PCIe lane；不作为 PCIe 端点插槽使用 |
| NPU | 不要求 | 未纳入 OpenWrt 完成条件 |
| Wi-Fi/蓝牙 | 不要求 | 保持禁用，不打包无线驱动或固件 |

尚未完成的最终验收：新版 Type-C role-switch 的正反插/热插拔/长时 SuperSpeed 读写及 Loader 回归、eMMC 更长时间读写、HDMI 拔插与反复重启、overlay 回滚，以及在独立 x4 插座安装第二网卡后的 PCIe 枚举、真实 LAN/WAN NAT 与软件 flow offload A/B 测试。
