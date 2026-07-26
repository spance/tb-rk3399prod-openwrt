# 硬件状态

本表依据适配期间采集的原厂和 OpenWrt 启动日志整理；原始调试日志不纳入清理后的工程。板级固定参数和以后升级时的回归检查项见 `HARDWARE-REFERENCE.md`。

| 项目 | 状态 | 关键结果 |
|---|---|---|
| UART2 | 已确认 | ttyS2，1500000 n8，earlycon 正常 |
| CPU | 已确认 | 4×A53 + 2×A72 全部上线，两个 cpufreq domain |
| PMIC | 已确认 | RK809；vdd_center、vdd_cpu_l、vdd_cpu_b、vdd_gpu 正常 |
| 温控 | 已确认 | CPU/GPU thermal zone、TSADC 正常 |
| TF | 已确认启动 | Linux 50 MHz/4-bit/IDMAC；U-Boot 25 MHz/PIO 可靠读取 FIT |
| eMMC | 已确认启动 | 29.1 GiB，HS400 Enhanced Strobe、CQE、ADMA |
| eMMC 正常系统 | 待实机写入验收 | 224 MiB `openwrt.img` 内含启动容器和 SquashFS rootfs；首次启动自动建立 ext4 `/overlay` |
| 千兆网 | 链路确认，压测中 | RTL8211E，1000/full，RX/TX flow control |
| USB2 | 已确认枚举 | 两组 EHCI/OHCI 和板载 Hub |
| USB3 | 已确认枚举 | xHCI SuperSpeed 和板载 SuperSpeed Hub |
| HDMI console | 软件已纳入，待实机验收 | DRM/VOPB/DW-HDMI、fbcon、`tty1` 和 USB HID 已加入；串口继续保留 |
| PCIe | 控制器确认 | host/PHY/电源正常进入 probe；无端点时 training timeout 与原厂一致 |
| RTL8822CE Wi-Fi | 软件已纳入，待实机验收 | profile 包含 `rtw88_8822ce` 及其固件依赖；待确认 PCIe 枚举、双频无线和稳定性 |
| NPU | 不要求 | 未纳入 OpenWrt 完成条件 |
| 板载 Wi-Fi/蓝牙 | 不要求 | 保持禁用；RTL8822CE 的蓝牙 USB 功能也不启用 |

尚未完成的最终验收：千兆网 30–60 分钟压力测试、USB3 实际存储传输、TF/eMMC 长时间读写、CPU 满载温控、HDMI 显示/键盘/拔插与重启、RTL8822CE 实物枚举和无线压力测试、正式 eMMC 系统安装、overlay 跨重启持久化和回滚。
