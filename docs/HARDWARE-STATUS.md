# 硬件状态

本表只记录可复现的实机结论；原始调试日志和设备唯一信息不纳入工程。固定连线、参数和升级不变量见 [硬件参考](HARDWARE-REFERENCE.md)，专项测试方法见相应设计文档。

当前结论：本板的 OpenWrt 基础硬件使能已经达到工程交付条件。RTL8125BG 已完成软件集成，但第二网卡和真实双口 NAT 仍需新镜像与实卡闭环，不能由“控制器 probe 成功”替代验收；更长周期耐久测试仍属于量产前补充验证。

| 项目 | 状态 | 关键结果 |
|---|---|---|
| UART2 | 已确认 | ttyS2，1500000 n8，earlycon 正常 |
| CPU | 已确认 | 4×A53 + 2×A72 全部上线，两个 cpufreq domain |
| DDR / trust | 已确认固定 800 MHz 启动链 | UART 确认 DDR bin v1.30、miniloader v1.26，trust 为 BL31 v1.35/BL32 v2.12；双通道各 2 GiB、32-bit、双 CS。五组 GET/ROUND 精确返回，1.5 GiB `00/ff/aa/55` 四图样写读校验和三次软重启通过；未启用 SET/DFI/devfreq governor |
| PMIC | 已确认 | RK809；vdd_center、vdd_cpu_l、vdd_cpu_b、vdd_gpu 正常 |
| 温控 | 已确认 | CPU/GPU thermal zone、TSADC 及 A53/A72 两个 cpufreq cooling device 正常绑定；6 核满载 90 秒稳定，最高约 55.6 °C，未故意加热到降频点 |
| 硬件 watchdog | 已确认故障复位 | RK3399 DesignWare watchdog 由 `procd` 启用，30 秒超时、5 秒喂狗；停止喂狗后整机按期掉线并以新 boot ID 重启，overlay、网络、LuCI 和 Type-C UAS 均自动恢复 |
| 板载 LED | 已确认 | `leds-gpio` 驱动蓝 GPIO2_A5、红 GPIO2_A4、绿 GPIO2_A3；三路逐一亮灭通过，OpenWrt aliases 分别表达启动、failsafe/升级和运行状态，正常状态为蓝灭、红灭、绿亮 |
| TF | 已确认读写 | Linux 50 MHz/4-bit/IDMAC，实测约 5.9 MiB/s 写、18.8 MiB/s 读；U-Boot 25 MHz/PIO 可靠读取 FIT |
| eMMC | 已确认启动，CQE 已禁用；PHY 电气对齐待复测 | 29.1 GiB，HS400 Enhanced Strobe、ADMA；正式内核使用 `SDHCI_QUIRK_BROKEN_CQE`，实机确认 `cmdq_en=0`；256 MiB 写入、同步与校验后 CQE recovery、MMC I/O 和 ext4 错误均为 0。DTS 已按 Toybrick 4.4 BSP 显式启用 strobe 内部下拉，待新镜像确认启动、链路和错误计数 |
| eMMC 正常系统 | 已确认启动 | 224 MiB `openwrt.img` 已从 eMMC 正常启动；SquashFS + 约 28.4 GiB ext4 `/overlay` 正常挂载 |
| 千兆网 | 已确认 | RTL8211E，1000/full；两个方向各 1800 秒均为 941 Mbit/s、197 GiB，硬件错误计数为 0 |
| 网络调优 | GMAC 已确认；RTL8125 待验收 | GMAC IRQ 绑定 CPU4/A72，复测 942/941 Mbit/s、0 重传；新策略按 PCI ID 将 RTL8125 单 IRQ 绑定 CPU5；S99 与所有接口 `ifup` 幂等恢复，fw4 软件 flowtable 正常生成 |
| USB2 | 已确认枚举 | 两组 EHCI/OHCI 和板载 Hub |
| USB3 Type-A | 已确认高速读写 | 多种设备以 `5000M` 枚举；M.2/UAS 实测约 340–360 MB/s，测试后无新增 USB/UAS/SCSI 错误 |
| USB3 Type-C | 已确认热插拔和高速读写 | 首次插入、同向重插和翻转重插均以 UAS/`5000M` 枚举；方向、角色、xHCI 创建/销毁、父子 runtime PM 和 PHY 收放顺序正确。exFAT 上 8 GiB direct 写约 300–320 MiB/s、direct 读约 340 MiB/s，完整数据比较通过；测试窗口无 `connect-debounce`、PHY timeout、xHCI/UAS/SCSI/I/O/exFAT 错误，SCSI I/O 错误计数未增长 |
| HDMI console | 已确认 | DRM/VOPB/DW-HDMI、fbcon 和 Linux 文本 console 已在显示器输出；串口继续保留 |
| PCIe / RTL8125BG | 软件适配完成，实卡待验收 | host 改为 Gen2 x4，RTL8125BG 目标协商 Gen2 x1；镜像内置主线 `r8169`、`rtl8125b-2.fw`、CPU5 IRQ 策略和 `tb-rtl8125-diag`；尚未记录实卡枚举/吞吐证据 |
| Mini-PCIe | USB2-only | 面向 LTE 模块，没有 PCIe lane；不作为 PCIe 端点插槽使用 |
| NPU | 不要求 | 未纳入 OpenWrt 完成条件 |
| Wi-Fi/蓝牙 | 不要求 | 保持禁用，不打包无线驱动或固件 |

watchdog 故障测试在同步文件系统后，通过 procd 控制接口停止 keepalive，保持 `magicclose=false`，随后观察网络掉线和新 boot ID 上线。该测试会有意重启设备，只能在确认没有写入任务时执行；本次复位后所有关键服务与外设均自行恢复。

## 已知边界

- Type-C 在当前测试范围内已通过工程验收；量产前仍建议执行 20～50 次方向交替/快速重插，以及至少 1～4 小时或 100 GiB 连续 I/O。Loader 刷写本版镜像后仍正常，Linux 侧改造不触及 BootROM、miniloader 或 U-Boot 的刷机协议。
- RTL8125BG 软件路径已经就绪，但在实卡验证前仍不得把 2.5GbE 标为已确认。必须验证 `10ec:8125`、`r8169`、固件加载、`5.0 GT/s x1`、CPU5 IRQ、AER/错误计数、冷/热启动、双向吞吐和真实 LAN/WAN NAT；流程见 [PCIe RTL8125BG 2.5GbE](PCIE-RTL8125.md)。
- eMMC 更长时间读写、HDMI 多次拔插/重启及 overlay 备份恢复流程仍可在量产验收中补充。
- 无线/蓝牙、GPU 图形桌面、HDMI 音频和 NPU 是明确的非目标，不应作为当前固件缺陷。

## 允许的预期日志

在没有 PCIe 端点时可以出现 PCIe link training timeout；安装 RTL8125BG 后仍然 timeout、回退 Gen1 或出现 AER 则必须调查。OpenWrt 的 GPIO 按键事件模块 `gpio_button_hotplug` 会产生 out-of-tree taint，它与使用内建 `leds-gpio` 的板载 LED 无关，也不表示内核故障。除此之外，电源/regulator probe、eMMC/MMC I/O、GMAC/PHY、Type-C PMA/PIPE、xHCI/UAS/SCSI 和文件系统错误都应视为回归并调查。
