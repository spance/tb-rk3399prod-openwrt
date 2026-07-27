# OpenWrt 适配说明

## 基线与配置

- OpenWrt：`v25.12.5`，commit `f0a60eee2fe051741c643ea6118718aae1ef17fb`。
- Linux：OpenWrt 官方 `6.12.94`。
- target/subtarget：`rockchip/armv8`。
- `configs/openwrt.config`：唯一正式目标配置，PCIe host/PHY/供电默认启用。
- `configs/feeds.conf`：只启用当前镜像需要的 `packages` 和 `luci` 两个 feed，并分别锁定到 OpenWrt 25.12.5 官方源码使用的精确 commit；routing、telephony 和 video feed 不下载。

板级 profile、持久化镜像规则、DTB Makefile 和必要的内核 binding 修改统一由 `patches/openwrt/0001-tb-rk3399prod-board-support.patch` 加入。完整板级设备树不嵌入补丁；`dts/` 是唯一权威来源，`make init` 调用 `scripts/sync-openwrt-dts.sh`，从 Rockchip target 的 `KERNEL_PATCHVER` 自动确定 `files-<版本>` 目录并逐文件覆写。板级启动服务和 UCI 初始值以 `rootfs/` 为唯一来源，由 `scripts/sync-openwrt-rootfs.sh` 同步到 Rockchip base-files。修改这些文件后重新执行 `make init` 再构建，不需要手工刷新重复补丁。

`configs/openwrt.config` 刻意只保留 target、正式设备 profile、SquashFS、强制 initramfs、Dropbear 外部 SFTP 和 musl 八项选择：板级软件包、内核选项和镜像规则属于 profile 的组成部分，应由同一份 OpenWrt 补丁原子维护，避免 `.config` 再保存一份容易漂移的展开结果。`CONFIG_TARGET_INITRAMFS_FORCE` 只保证每次同时生成 TF/串口恢复 FIT，不会让正式 `openwrt.img` 使用易失的 initramfs 根文件系统。

官方预编译 `.ko` 与本项目内核配置不兼容，不能靠覆盖包管理哈希安全加载。工程不修改 OpenWrt 的模块 ABI 和仓库逻辑；需要增加驱动时，将对应标准 OpenWrt kmod 加入设备 profile 后重新构建完整固件。

## 硬件范围

- UART2：1500000 n8。
- 4×Cortex-A53 + 2×Cortex-A72、cpufreq/OPP、TSADC/thermal；强制启用 CPU frequency cooling，使 thermal zone 可以通过 cpufreq cooling device 降频。
- RK3399 DesignWare 硬件 watchdog；`procd` 负责喂狗，板级 DTS 显式提供 16 项 timeout-period 计数表。
- RK809、TCS4525/TCS4526、CPU/GPU/核心电源轨。
- TF：4-bit、50 MHz、Rockchip IDMAC。
- eMMC：HS400 Enhanced Strobe、ADMA；为避免写入负载下反复进入 CQE recovery，使用 Linux 已有的 `SDHCI_QUIRK_BROKEN_CQE` 默认关闭 CQE。
- RTL8211E 千兆以太网：RGMII，TX/RX delay `0x28/0x20`。
- 网络调优：GMAC IRQ 动态绑定到第一颗 Cortex-A72，并在 LAN `ifup` 后及 S99 阶段幂等恢复；fw4 软件 flow offload 默认开启，硬件 flow offload 保持关闭。
- USB2 EHCI/OHCI、两组 USB3 控制器、板载 Hub 电源和复位；蓝色 Type-A 口已实测高速读写。Type-C 连接器对外固定为 5 V source/host，DWC3_0 内部使用 role-switch 管理断开时的 xHCI/core/PHY 关闭与重连恢复；TCPM 先给出方向，PHY 再在上电路径中配置对应 lanes。C 口首次插入、同向重插、翻转重插、UAS/`5000M` 和 exFAT 高速读写均已通过，详见 [USB Type-C SuperSpeed 主机](USB-TYPE-C.md)。
- PCIe：默认启用，Gen1、x4 host，位于独立的 x4 板对板插座，并允许通过合适的转接板连接 x1 端点；无端点时 training timeout 与原厂 BSP 一致。
- HDMI console：内建 Rockchip DRM、VOPB、DW-HDMI、fbdev/fbcon，保留 UART2 并增加 `tty1` 键盘登录；详细设计和验收见 [HDMI Linux console](HDMI-CONSOLE.md)。
- 无线、蓝牙、摄像、音频、图形桌面、GPU 和 NPU 不纳入当前目标，也不打包 `rtw88`、mac80211 或无线固件。

Mini-PCIe 插座的机械外形不代表本板提供 PCIe 电气连接：它只适用于走 USB2 的 LTE 模块。若以后在独立 x4 插座改装 PCIe 有线网卡，应按具体型号增加 `igb`、`igc` 或 `r8169` 等驱动，并完成枚举、吞吐、错误计数和长时间稳定性验收。

两个容易被误判为冗余的内核选项需要保留：`CONFIG_USB_GADGET=y` 是 DWC3 dual-role 框架的构建依赖，但连接器 DTS 固定为 host/source 且 gadget-only 模式关闭，产品不会暴露 USB gadget；`CONFIG_DEBUG_FS=y` 用于 FUSB302/TCPM 事件环和 `tb-typec-diag` 的升级排障，只向本机 root 提供诊断接口。若未来删除 Type-C 板外补丁且不再需要事件环，才应一起评估移除 debugfs 和诊断工具。

## 内置维护工具

- 存储与文件：`lsblk`、`blkid`、`blockdev`、`fdisk`、`fstrim`、`findmnt`（由 `mount-utils` 提供）、`mmc-utils`、GNU `stat`、`file`、`find`、`xargs`、`tree`、`less` 和 `base64`；内置 FAT32 与 exFAT 文件系统驱动，覆盖常见 U 盘和移动硬盘。
- 板级与进程：`lscpu`、`wdctl`、`htop`、`lsof`、`strace`。
- 网络：完整功能的 `ip`（以 `ip-full` 替换默认 `ip-tiny`）、`ss`、`ethtool`、`iperf3`、`tcpdump-mini`，以及 TUN、INET socket diagnostics 和 nftables TPROXY 内核模块。
- DNS/DHCP：以 `dnsmasq-full` 替换默认 `dnsmasq`，保留 UCI 配置路径，并提供 DHCPv6、DNSSEC、authoritative DNS、nftset、conntrack 和 TFTP 能力。
- Shell、脚本、传输与归档：`bash`、`python3-light`、`openssh-sftp-server`、`unzip`；SFTP 子系统与系统现有 Dropbear SSH 服务配合，不额外引入完整 OpenSSH daemon。`python3-light` 提供 Python 解释器和常用标准库，并保持与 OpenWrt 的 musl ABI 和软件包生命周期一致。
- 通用数据访问：`curl`、`ca-bundle`、`jq`。

基础镜像只为 BusyBox 缺失或功能明显不足的文件操作引入独立 GNU 工具，不安装完整 coreutils/findutils 元包，也不预装编辑器或编译器。`dnsmasq-full` 继续使用 OpenWrt 原有 `/etc/config/dhcp` 和启动服务，其额外能力只有在对应配置中启用后才改变网络行为。

正式配置显式固定 `CONFIG_USE_MUSL=y`。上述工具全部由固定的 OpenWrt 25.12.5 `packages`/`luci` feed 面向目标架构编译，依赖的 `libc` 是 OpenWrt musl 1.2.5，不安装或链接 glibc；`file` 只额外依赖 `libmagic`，`less` 依赖 `libncursesw6`，SFTP 服务端只依赖 musl `libc`。

## LuCI Web 管理

正式 profile 内置 `luci-ssl`，以及 Base、Firewall、APK 软件包管理三个界面的简体中文语言包。它通过依赖带入 `luci-light`、完整管理页面、Firewall 页面、Bootstrap 主题、APK 软件包管理、`uhttpd`、`uhttpd-mod-ubus` 和 RPC 组件。首次启动完成后可通过 LAN 地址访问：

```text
https://192.168.1.1/
```

若 LAN 地址已经调整，应使用实际地址。首次打开时浏览器会提示设备生成的自签名证书；确认地址属于本机后再继续。LuCI 与 SSH 使用同一个 root 账户和密码，因此部署后应立即设置强密码。

这里选择 `luci-ssl`，而不是普通 `luci` 元包：普通元包还会加入 attended sysupgrade，而本项目尚未实现与自定义组合镜像匹配的 sysupgrade 流程。Web 页面中的 APK 软件包管理可以使用，但不要把任何通用固件升级入口当成本板的刷写方式；完整镜像和 boot-only 更新边界仍以 [eMMC 部署与验收](EMMC-INSTALL.md) 为准。

## 脚本运行时策略

- 固件内置 `python3-light`，作为唯一的系统 Python；需要几乎完整的标准库时执行 `apk add python3`，由 APK 在现有解释器上补齐拆分模块。
- `uv` 只用于基于 `/usr/bin/python3` 创建虚拟环境和管理应用依赖，不负责安装或升级系统解释器。建议使用 `uv --no-managed-python`，或者设置 `UV_PYTHON_DOWNLOADS=never` 与 `UV_PYTHON_PREFERENCE=only-system`。
- Ruby 不属于板级功能或启动依赖，因此不固化到基础镜像；需要时使用匹配当前 OpenWrt 版本和架构的软件源执行 `apk add ruby ruby-yaml`。YJIT 能力由软件包构建配置决定而不是安装位置决定，可用 `ruby --yjit -e 'p RubyVM::YJIT.enabled?'` 验证。
- 完整重刷 `openwrt.img` 会重建 overlay，因此通过 APK、uv 或其他方式按需安装的软件都应视为可重建的应用状态，不应成为未记录的板级依赖。

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
