# OpenWrt 适配说明

## 基线与配置

- OpenWrt：`v25.12.5`，commit `f0a60eee2fe051741c643ea6118718aae1ef17fb`。
- Linux：OpenWrt 官方 `6.12.94`。
- target/subtarget：`rockchip/armv8`。
- `configs/openwrt.config`：唯一正式配置，PCIe host/PHY/供电默认启用。

此前无 PCIe 的 base profile 仅用于开发调试，现已删除。唯一构建入口是 `patches/openwrt/0001-tb-rk3399prod-board-support.patch`；`dts/` 是新增 DTS/DTSI 的审阅副本，不由脚本重复复制到源码树。

## 硬件范围

- UART2：1500000 n8。
- 4×Cortex-A53 + 2×Cortex-A72、cpufreq/OPP、TSADC/thermal。
- RK809、TCS4525/TCS4526、CPU/GPU/核心电源轨。
- TF：4-bit、50 MHz、Rockchip IDMAC。
- eMMC：HS400 Enhanced Strobe、CQE、ADMA。
- RTL8211E 千兆以太网：RGMII，TX/RX delay `0x28/0x20`。
- USB2 EHCI/OHCI、USB3 xHCI、板载 Hub 电源和复位。
- PCIe：默认启用，Gen1、x4 host，允许连接 x1 端点；无端点时 training timeout 与原厂 BSP 一致。
- Wi-Fi、蓝牙、显示、摄像、音频和 NPU 不纳入目标。

PCIe 网卡型号确定后，需在 PCIe 配置中增加对应的 `igb`、`igc` 或 `r8169` 等驱动，并完成枚举、吞吐、错误计数和长时间稳定性验收。

## 临时启动

```text
mmc dev 1
setenv fitaddr 0x10000000
fatload mmc 1:1 ${fitaddr} openwrt.bin
setenv bootargs console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xff1a0000 loglevel=8
bootm ${fitaddr}
```

当前配置特意设置 `IMAGES :=` 并构建 initramfs FIT，用于先验证启动和硬件。它不是已经验收的 eMMC 系统盘镜像。
