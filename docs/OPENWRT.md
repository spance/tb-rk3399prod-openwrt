# OpenWrt 适配说明

## 基线与配置

- OpenWrt：`v25.12.5`，commit `f0a60eee2fe051741c643ea6118718aae1ef17fb`。
- Linux：OpenWrt 官方 `6.12.94`。
- target/subtarget：`rockchip/armv8`。
- `configs/openwrt.config`：唯一正式配置，PCIe host/PHY/供电默认启用。

此前无 PCIe 的 base profile 仅用于开发调试，现已删除。板级和持久化镜像配置由 `patches/openwrt/0001-tb-rk3399prod-board-support.patch`、`0002-tb-rk3399prod-persistent-overlay.patch` 依次加入；`dts/` 是新增 DTS/DTSI 的审阅副本，不由脚本重复复制到源码树。

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

## 正常启动与持久化 overlay

正常 `boot_linux.img` 内的 FIT 只包含 Linux 内核和 DTB。启动脚本使用稳定的 GPT 标签指定根文件系统：

```text
root=PARTLABEL=rootfs rootwait rootfstype=squashfs fstools_overlay_fstype=ext4
```

`rootfs.img` 是固定 128 MiB 的写入载体，开头为 OpenWrt SquashFS。它只用于覆盖原厂 `rootfs@0x36000` 分区的前 128 MiB；内核仍把整个 grow 分区作为根块设备。首次启动时，OpenWrt `fstools` 根据 SquashFS 实际结束位置建立 loop 设备，自动用 `mkfs.ext4` 格式化后面的全部剩余空间，并挂载为 `/overlay`。`fstools_overlay_fstype=ext4` 很重要：`fstools` 对大容量块设备的 `auto` 策略会选择 F2FS，本工程显式固定 ext4，以匹配已打包的格式化工具和当前稳定性目标。因此安装软件、UCI 配置及 `/etc` 修改能够跨重启保存。

设备 profile 显式加入 `e2fsprogs`，保证首次启动存在 `mkfs.ext4`；Rockchip armv8 内核基线已内建 loop、SquashFS、ext4 和 overlayfs 所需支持。SquashFS 内容由 `check-size 120m` 约束，载体补齐到 128 MiB，预留的 8 MiB 清零区确保旧 overlay 超级块不会在重装后被误识别；内容超限时构建直接失败。

`boot_linux.img` 和 `rootfs.img` 是匹配的一组，升级时必须同时写入。重新写入 `rootfs.img` 会清空旧 overlay 的起始元数据并在下一次启动重建，等同于恢复出厂；升级前应另行导出配置。

## initramfs 恢复启动

```text
mmc dev 1
setenv fitaddr 0x10000000
fatload mmc 1:1 ${fitaddr} openwrt-rockchip-armv8-toybrick_tb-rk3399prod-initramfs-kernel.bin
setenv bootargs console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xff1a0000 loglevel=8
bootm ${fitaddr}
```

配置会额外保留强制 initramfs FIT 作为 TF/串口恢复镜像，但它不会放入正式 `boot_linux.img`，也不会挂载持久化 overlay。正式 `boot_linux.img` 使用正常 FIT。两种 FIT 都加载到安全地址 `0x10000000` 后执行 `bootm`。
