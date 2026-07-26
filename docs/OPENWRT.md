# OpenWrt 适配说明

## 基线与配置

- OpenWrt：`v25.12.5`，commit `f0a60eee2fe051741c643ea6118718aae1ef17fb`。
- Linux：OpenWrt 官方 `6.12.94`。
- target/subtarget：`rockchip/armv8`。
- `configs/openwrt.config`：唯一正式目标配置，PCIe host/PHY/供电默认启用。
- `configs/feeds.conf`：只启用当前软件包集合所需的 `packages` feed，并锁定到 25.12.5 官方发布使用的精确 commit；LuCI 等未使用 feed 不下载。

板级 profile、持久化镜像规则、DTB Makefile 和必要的内核 binding 修改统一由 `patches/openwrt/0001-tb-rk3399prod-board-support.patch` 加入。完整板级设备树不嵌入补丁；`dts/` 是唯一权威来源，`make init` 调用 `scripts/sync-openwrt-dts.sh`，从 Rockchip target 的 `KERNEL_PATCHVER` 自动确定 `files-<版本>` 目录并逐文件覆写。板级启动服务和 UCI 初始值以 `rootfs/` 为唯一来源，由 `scripts/sync-openwrt-rootfs.sh` 同步到 Rockchip base-files。修改这些文件后重新执行 `make init` 再构建，不需要手工刷新重复补丁。

## 硬件范围

- UART2：1500000 n8。
- 4×Cortex-A53 + 2×Cortex-A72、cpufreq/OPP、TSADC/thermal；强制启用 CPU frequency cooling，使 thermal zone 可以通过 cpufreq cooling device 降频。
- RK3399 DesignWare 硬件 watchdog；`procd` 负责喂狗，板级 DTS 显式提供 16 项 timeout-period 计数表。
- RK809、TCS4525/TCS4526、CPU/GPU/核心电源轨。
- TF：4-bit、50 MHz、Rockchip IDMAC。
- eMMC：HS400 Enhanced Strobe、ADMA；为避免写入负载下反复进入 CQE recovery，使用 Linux 已有的 `SDHCI_QUIRK_BROKEN_CQE` 默认关闭 CQE。
- RTL8211E 千兆以太网：RGMII，TX/RX delay `0x28/0x20`。
- 网络调优：GMAC IRQ 动态绑定到第一颗 Cortex-A72，并在 LAN `ifup` 后及 S99 阶段幂等恢复；fw4 软件 flow offload 默认开启，硬件 flow offload 保持关闭。
- USB2 EHCI/OHCI、两组 USB3 控制器、板载 Hub 电源和复位；蓝色 Type-A 口已实测高速读写。Type-C 使用固定 host 的 DWC3_0/xHCI、tcphy0、I2C8 FUSB302 和 TCPM orientation switch，连接器固定为 5 V source/host；正反两组 SuperSpeed lane 在 PHY 上电时预配置，热换向只切换 GRF 方向位。C 口冷启动 UAS/`5000M` 已实测，自动换向重连待新镜像验收，详见 [USB Type-C SuperSpeed 主机](USB-TYPE-C.md)。
- PCIe：默认启用，Gen1、x4 host，位于独立的 x4 板对板插座，并允许通过合适的转接板连接 x1 端点；无端点时 training timeout 与原厂 BSP 一致。
- HDMI console：内建 Rockchip DRM、VOPB、DW-HDMI、fbdev/fbcon，保留 UART2 并增加 `tty1` 键盘登录；详细设计和验收见 [HDMI Linux console](HDMI-CONSOLE.md)。
- 无线、蓝牙、摄像、音频、图形桌面、GPU 和 NPU 不纳入当前目标，也不打包 `rtw88`、mac80211 或无线固件。

Mini-PCIe 插座的机械外形不代表本板提供 PCIe 电气连接：它只适用于走 USB2 的 LTE 模块。若以后在独立 x4 插座改装 PCIe 有线网卡，应按具体型号增加 `igb`、`igc` 或 `r8169` 等驱动，并完成枚举、吞吐、错误计数和长时间稳定性验收。

## 内置维护工具

- 存储：`lsblk`、`blkid`、`blockdev`、`fdisk`、`fstrim`、`findmnt`（由 `mount-utils` 提供）、`mmc-utils`；内置 FAT32 与 exFAT 文件系统驱动，覆盖常见 U 盘和移动硬盘。
- 板级与进程：`lscpu`、`wdctl`、`htop`、`lsof`、`strace`。
- 网络：完整功能的 `ip`（以 `ip-full` 替换默认 `ip-tiny`）、`ss`、`ethtool`、`iperf3`、`tcpdump-mini`。
- 通用数据访问：`curl`、`ca-bundle`、`jq`。

BusyBox 已能满足的基础命令不重复引入 GNU coreutils；不预装编辑器、编译器、LuCI 或长期运行的附加服务。上述工具用于本机维护和故障定位，不改变默认网络服务或启动流程。

网络性能基线、flow offload 适用边界、ARMv8 AES-CE、Rockchip Crypto 取舍和未来多队列/RSS 策略见 [网络性能与加速策略](NETWORK-PERFORMANCE.md)。

## 正常启动与持久化 overlay

正式 `openwrt.img` 开头的 ext2 启动容器中，FIT 只包含 Linux 内核和 DTB。启动脚本使用稳定的 GPT 标签指定根文件系统：

```text
root=PARTLABEL=rootfs rootwait rootfstype=squashfs fstools_overlay_fstype=ext4
```

`openwrt.img` 的 96 MiB 偏移处是固定 128 MiB 的 rootfs 载体，开头为 OpenWrt SquashFS。整个组合镜像从 LBA `0x6000` 写入后，该载体正好覆盖原厂 `rootfs@0x36000` 分区的前 128 MiB；内核仍把整个 grow 分区作为根块设备。首次启动时，OpenWrt `fstools` 根据 SquashFS 实际结束位置建立 loop 设备，自动用 `mkfs.ext4` 格式化后面的全部剩余空间，并挂载为 `/overlay`。`fstools_overlay_fstype=ext4` 很重要：`fstools` 对大容量块设备的 `auto` 策略会选择 F2FS，本工程显式固定 ext4，以匹配已打包的格式化工具和当前稳定性目标。因此安装软件、UCI 配置及 `/etc` 修改能够跨重启保存。

设备 profile 显式加入 `e2fsprogs`，保证首次启动存在 `mkfs.ext4`；Rockchip armv8 内核基线已内建 loop、SquashFS、ext4 和 overlayfs 所需支持。SquashFS 内容由 `check-size 120m` 约束，载体补齐到 128 MiB，预留的 8 MiB 清零区确保旧 overlay 超级块不会在重装后被误识别；内容超限时构建直接失败。

构建脚本将匹配的启动容器和 rootfs 原子地组合成一个 `openwrt.img`，避免升级时错配。重新写入它会清空旧 overlay 的起始元数据并在下一次启动重建，等同于恢复出厂；升级前应另行导出配置。

## initramfs 恢复启动

```text
mmc dev 1
setenv fitaddr 0x10000000
fatload mmc 1:1 ${fitaddr} openwrt-rockchip-armv8-toybrick_tb-rk3399prod-initramfs-kernel.bin
setenv bootargs console=tty0 console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xff1a0000 loglevel=8
bootm ${fitaddr}
```

配置会额外保留强制 initramfs FIT 作为 TF/串口恢复镜像，并将它复制到 `out/openwrt/`；它不会放入正式 `openwrt.img`，也不会挂载持久化 overlay。正式组合镜像使用正常 FIT。两种 FIT 都加载到安全地址 `0x10000000` 后执行 `bootm`。
