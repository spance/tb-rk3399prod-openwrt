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
| eMMC `boot_linux` | 待实机写入验收 | 已生成 64 MiB ext2 镜像；含 `boot.scr` 和 initramfs FIT |
| 千兆网 | 链路确认，压测中 | RTL8211E，1000/full，RX/TX flow control |
| USB2 | 已确认枚举 | 两组 EHCI/OHCI 和板载 Hub |
| USB3 | 已确认枚举 | xHCI SuperSpeed 和板载 SuperSpeed Hub |
| PCIe | 控制器确认 | host/PHY/电源正常进入 probe；无端点时 training timeout 与原厂一致 |
| NPU | 不要求 | 未纳入 OpenWrt 完成条件 |
| Wi-Fi/蓝牙 | 不要求 | 保持禁用 |

尚未完成的最终验收：千兆网 30–60 分钟压力测试、USB3 实际存储传输、TF/eMMC 长时间读写、CPU 满载温控、PCIe 网卡实物枚举、正式 eMMC 系统安装和回滚。
