# 硬件状态

本表依据适配期间采集的原厂和 OpenWrt 启动日志整理；原始调试日志不纳入清理后的工程。板级固定参数和以后升级时的回归检查项见 `HARDWARE-REFERENCE.md`。

| 项目 | 状态 | 关键结果 |
|---|---|---|
| UART2 | 已确认 | ttyS2，1500000 n8，earlycon 正常 |
| CPU | 已确认 | 4×A53 + 2×A72 全部上线，两个 cpufreq domain |
| PMIC | 已确认 | RK809；vdd_center、vdd_cpu_l、vdd_cpu_b、vdd_gpu 正常 |
| 温控 | 软件已修复，待新镜像验收 | CPU/GPU thermal zone、TSADC 读数正常；正式配置强制启用 `CONFIG_CPU_FREQ_THERMAL`，待重刷后验证 CPU cooling device 和满载降频 |
| 硬件 watchdog | 已确认运行 | RK3399 DesignWare watchdog 已由 `procd` 启用，30 秒超时、5 秒喂狗；DTS 显式提供与 Linux 驱动回退值一致的 TOP 表 |
| TF | 已确认读写 | Linux 50 MHz/4-bit/IDMAC，实测约 5.9 MiB/s 写、18.8 MiB/s 读；U-Boot 25 MHz/PIO 可靠读取 FIT |
| eMMC | 已确认启动 | 29.1 GiB，HS400 Enhanced Strobe、CQE、ADMA |
| eMMC 正常系统 | 已确认启动 | 224 MiB `openwrt.img` 已从 eMMC 正常启动；SquashFS + 约 28.4 GiB ext4 `/overlay` 正常挂载 |
| 千兆网 | 已确认 | RTL8211E，1000/full；两个方向各 1800 秒均为 941 Mbit/s、197 GiB，硬件错误计数为 0 |
| 网络调优 | 软件已修复，待新镜像重启验收 | GMAC IRQ 已验证迁移至 CPU4/A72，复测 942/941 Mbit/s、0 重传；接口 `ifup` hotplug 会在开机及网络重启后恢复绑核，S99 服务作为兜底；fw4 软件 flowtable 可正常生成 |
| USB2 | 已确认枚举 | 两组 EHCI/OHCI 和板载 Hub |
| USB3 | 已确认读写 | ADATA 设备以 5000 Mbit/s 枚举；实测约 13.8 MiB/s 写、105.8 MiB/s 读 |
| HDMI console | 已确认 | DRM/VOPB/DW-HDMI、fbcon 和 Linux 文本 console 已在显示器输出；串口继续保留 |
| PCIe | 控制器确认 | host/PHY/电源正常进入 probe；无端点时 training timeout 与原厂一致 |
| RTL8822CE Wi-Fi | 软件已纳入，待实机验收 | profile 包含 `rtw88_8822ce` 及其固件依赖；待确认 PCIe 枚举、双频无线和稳定性 |
| NPU | 不要求 | 未纳入 OpenWrt 完成条件 |
| 板载 Wi-Fi/蓝牙 | 不要求 | 保持禁用；RTL8822CE 的蓝牙 USB 功能也不启用 |

尚未完成的最终验收：TF/eMMC 长时间读写、CPU 满载温控、HDMI 键盘/拔插与反复重启、RTL8822CE 实物枚举和无线压力测试、overlay 跨重启持久化和回滚，以及安装第二网卡后的真实 LAN/WAN NAT 与软件 flow offload A/B 测试。
