# TB-RK3399ProD OpenWrt

面向 Toybrick TB-RK3399ProD 的可复现 OpenWrt 板级适配工程。

**OpenWrt 25.12.5 · Linux 6.12.94 · AArch64 · LuCI HTTPS · eMMC 持久化系统 · 千兆网络与 USB 3.0 实机验收**

本项目把厂商 Linux 4.4 的板级行为迁移到现代 OpenWrt/Linux 架构，并提供经过实机验证的 U-Boot、设备树、内核驱动补丁、系统配置和镜像构建流程。仓库只保存适配所需的可维护增量；上游源码、工具链、设备信息、调试日志和构建产物均不提交。

## 项目亮点

- **现代系统基线**：OpenWrt 25.12.5、Linux 6.12.94、musl 和 nftables/fw4。
- **可用的 eMMC 系统**：HS400 Enhanced Strobe、ADMA、SquashFS + ext4 overlay，约 28.4 GiB 空间可持久保存软件和配置。
- **稳定千兆网络**：RTL8211E 在双向 30 分钟压力测试中均达到 941 Mbit/s；GMAC IRQ 自动放置到 Cortex-A72，软件 flow offload 默认启用。
- **完整 USB 3.0 主机能力**：蓝色 Type-A 与 Type-C 均通过 UAS/`5000M` 高速存储测试；Type-C 支持正反插、热拔插和完整 runtime-PM 生命周期。
- **双控制台与恢复路径**：UART2 1500000 baud、HDMI Linux console、USB 键盘登录，以及 TF/initramfs 恢复启动。
- **内置 Web 管理**：LuCI、简体中文界面、uhttpd、Firewall 和 APK 软件包管理随镜像提供，默认使用 HTTPS。
- **完整的日常命令体验**：保留 BusyBox 作为启动与救援底座，同时内置 GNU `tar`、`gzip`、`grep`、`sed`、`gawk`、`diff`、`patch`、`dd`、`stat`、`find`、`xargs`、`procps-ng`、tmux、完整 Vim 和 rsync；SFTP 服务端与 LuCI 简体中文界面随镜像提供。
- **可验证的按需驱动**：可以从固定源码按包名构建 `kmod-*` APK；只有与当前固件内核依赖完全一致的模块才会交付，不覆盖 ABI，也不强制安装。
- **面向升级维护**：DTS、Linux 补丁和 rootfs 文件各自只有一个权威来源；全部上游精确锁定到 commit，并由自动检查保护关键不变量。

## 硬件支持矩阵

| 子系统 | 硬件与关键参数 | 驱动与工程实现 | 状态 |
|---|---|---|---|
| CPU / 调频 | 4× Cortex-A53（408～1416 MHz）+ 2× Cortex-A72（408～1800 MHz） | `cpufreq-dt`、OPP、`schedutil`、cpufreq cooling | 已验证六核、自动调频和温控绑定 |
| 时钟 / 温控 | RK3399 CRU、TSADC、CPU/GPU thermal zone | `clk-rk3399`、`rockchip-thermal` | 已验证 |
| PMIC / 电源 | RK809；`vdd_cpu_l`、`vdd_cpu_b`、`vdd_gpu`、`vdd_center` | `rk808`/`rk808-regulator`、`fan53555` 兼容 TCS4525/TCS4526 | 已验证关键电源轨 |
| UART2 | `ttyS2`，1500000 8N1；earlycon `0xff1a0000` | DesignWare 8250 / `8250_dw` | 已验证启动与登录 |
| TF 卡 | 4-bit；Linux 50 MHz；U-Boot 25 MHz/PIO | Linux `dw_mmc-rockchip`；U-Boot DWMMC 可靠性补丁 | 已验证 Linux 读写和 U-Boot FIT 加载 |
| eMMC | 32 GB，8-bit，HS400 Enhanced Strobe、ADMA | `sdhci-of-arasan`、Rockchip eMMC PHY；标准 quirk 禁用不稳定 CQE | 已验证启动、读写和持久化 overlay |
| 千兆以太网 | RK3399 GMAC + RTL8211E，RGMII，TX/RX delay `0x28/0x20` | `dwmac-rk` / stmmac + Realtek PHY；IRQ 绑定 CPU4 | 已验证 1000/full 和双向线速 |
| USB2 | 两组 EHCI/OHCI、USB2 PHY、板载 Hub | `ehci-platform`、`ohci-platform`、Rockchip USB2 PHY | 已验证枚举 |
| USB3 Type-A | DWC3_1 / xHCI / `tcphy1`，固定 host | DWC3、xHCI、`phy-rockchip-typec` | 已验证 UAS/`5000M` 高速读写 |
| USB3 Type-C | FUSB302 `0x22`，5 V/1.5 A source/host，DWC3_0 / `tcphy0` | 标准 FUSB302/TCPM + 本工程 Rockchip Type-C PHY、DWC3 生命周期补丁 | 已验证正反插、热拔插、UAS 和高速读写 |
| HDMI console | VOPB + DW-HDMI，EDID 自动选模；保留串口 | Rockchip DRM/VOP、DW-HDMI、Innosilicon HDMI PHY、fbcon | 已验证文本 console 与 USB 键盘登录 |
| Watchdog | RK3399 DesignWare WDT；30 秒超时、5 秒喂狗 | `dw_wdt` + OpenWrt `procd` | 已验证停止喂狗后硬件复位及系统自动恢复 |
| 板载 LED | 蓝 GPIO2_A5、红 GPIO2_A4、绿 GPIO2_A3，高电平有效 | 标准 `gpio-leds`；OpenWrt 启动/failsafe/运行/升级状态别名 | 三路亮灭和运行状态已验证 |
| PCIe x4 插座 | Gen1、x4 host，可经转接连接 x1 端点 | Rockchip PCIe host/PHY | 控制器已启用；尚无端点，第二网卡待验收 |
| Mini-PCIe 插座 | 只有 USB2 走线，面向 LTE 模块 | 复用 USB2 host 驱动；不存在 PCIe lane | USB2-only，不能使用 RTL8822CE 等 PCIe 网卡 |
| Wi-Fi / 蓝牙 | 不属于目标范围 | 不打包无线驱动和固件 | 有意禁用 |
| GPU / NPU | 电源与 thermal 描述保留 | 不集成图形桌面、GPU 计算或 RKNN/NPU 软件栈 | 不属于目标范围 |

更完整的固定连线、电源、地址、时序和升级不变量见 [硬件参考](docs/HARDWARE-REFERENCE.md)，当前验收边界见 [硬件状态](docs/HARDWARE-STATUS.md)。

## 实测性能

以下数据来自当前 OpenWrt 25.12.5 / Linux 6.12.94 固件和同一块 TB-RK3399ProD 实机；它们用于给出可复现的工程基线，不代表所有外设、线材或网络环境的保证值。

| 项目 | 测试条件 | 实测结果 |
|---|---|---:|
| 千兆网发送 | `iperf3 -P 4 -t 1800` | 941 Mbit/s，197 GiB，180 次 TCP 重传；GMAC/PHY 错误为 0 |
| 千兆网接收 | `iperf3 -P 4 -t 1800 -R` | 941 Mbit/s，197 GiB，GMAC/PHY 错误为 0 |
| IRQ 调优复测 | 4 流、30 秒；GMAC IRQ 位于 CPU4/A72 | 发送/接收 942/941 Mbit/s，0 重传 |
| USB3 Type-A | Lexar E300 2 TB M.2、UAS、`5000M` | 约 340～360 MB/s |
| USB3 Type-C 写入 | 同一 M.2、exFAT、8 GiB `O_DIRECT` + `fsync` | 约 300～320 MiB/s |
| USB3 Type-C 读取 | 同一 M.2、exFAT、8 GiB `O_DIRECT` | 约 340 MiB/s，完整数据比较通过 |
| TF 卡 | 4 GB 卡，Linux 50 MHz/4-bit/IDMAC | 约 5.9 MiB/s 写、18.8 MiB/s 读 |
| CPU 温控 | 六核满载 90 秒 | 最高约 55.6 °C，无错误或非预期降频 |

ARMv8 Crypto Extensions 已由 OpenSSL 3.5.7、16 KiB 数据块、固定单个 Cortex-A72 实测：

| 算法 | ARMv8 AES-CE | 纯软件 | 加速倍数 |
|---|---:|---:|---:|
| AES-128-CBC | 1.347 GB/s | 112 MB/s | 12.0× |
| AES-256-CBC | 1.017 GB/s | 83 MB/s | 12.2× |
| AES-128-GCM | 1.395 GB/s | 61.9 MB/s | 22.5× |
| AES-256-GCM | 1.195 GB/s | 51.8 MB/s | 23.1× |

两个 Cortex-A72 并行时，AES-128-GCM/AES-256-GCM 合计约为 2.794/2.408 GB/s。该结果证明 AES-CE 路径生效，不等同于包含协议、VPN、NAT、防火墙和网络 I/O 开销的端到端吞吐。原始判读和加速策略见 [网络性能与加速策略](docs/NETWORK-PERFORMANCE.md)。

## 当前交付范围

当前版本已经达到本板 OpenWrt 基础硬件使能的工程交付条件，包括启动、电源、CPU/调频/温控、eMMC overlay、TF、千兆网、USB2/USB3、Type-C 热插拔、HDMI console、板载状态灯和 watchdog 故障复位链。

仍需明确区分以下边界：

- 独立 x4 插座尚未安装 PCIe 端点，因此尚未宣称第二网卡、双口 NAT 或 PCIe 长期稳定性已经通过。
- Type-C 已通过功能与高速 I/O 验收；量产前仍建议增加 20～50 次方向交替/快速重插，以及 1～4 小时或 100 GiB 连续 I/O。
- Wi-Fi、蓝牙、HDMI 音频、图形桌面、GPU 计算和 NPU 是明确的非目标。

## 适配分层与改造点

板级行为以 Toybrick 官方 `rockchip-toybrick/kernel` stable Linux 4.4 为基线；OpenWrt 的 Linux 6.12 用于承载当前子系统 API，其他 Rockchip 6.x 分支只作移植参考，不视为 TB-RK3399ProD 的官方支持版本。

| 层次 | 本工程承担的改造 | 权威来源 |
|---|---|---|
| U-Boot | 保留 Toybrick/Rockchip 2017.09 启动链；修复现代 Linux x86_64 主机构建兼容性，并将 TF 路径限制为 25 MHz、PIO、单次最多 1 MiB，以可靠加载恢复 FIT | `patches/u-boot/` |
| Linux 驱动 | 为 RK3399 Type-C PHY 接入标准 orientation switch；为 DWC3 实现真实 `NONE ↔ HOST`、xHCI 创建/销毁、父子 runtime PM 与 OTG reset 生命周期；用标准 SDHCI quirk 禁用本板不稳定的 eMMC CQE | `patches/kernel/` 与 OpenWrt 板级补丁中的 CQE backport |
| 板级描述与配置 | 固化 RK809/电源、CPU/温控、存储、GMAC、USB、HDMI、PCIe 等连线和参数；选择 Linux Kconfig、OpenWrt profile、软件包和镜像规则 | `dts/`、`patches/openwrt/`、`configs/` |
| 运行策略 | 启用 ext4 overlay、把 GMAC IRQ 幂等绑定到 CPU4/A72、启用软件 flow offload，并提供一次性 Type-C 诊断工具 | `rootfs/` |
| 构建与发布 | 固定全部上游 commit，下载到 `.work/`，同步唯一来源，执行检查并生成 `uboot.img`、`openwrt.img` 和发布包 | `scripts/`、`Makefile` |

Type-C 不是把 Linux 4.4 代码逐行复制到 6.12：板级时序和生命周期以 Toybrick stable 4.4 为行为规范，再用 Linux 6.12 的 TCPM、role-switch、generic PHY、runtime PM 和 reset API 表达。FUSB302/TCPM 使用未修改的 Linux 6.12 标准驱动；实质驱动改造集中在 Rockchip Type-C PHY 与 DWC3 两个补丁。其余大多数硬件沿用上游驱动，通过 DTS、Kconfig 和 profile 完成板级集成。

## 工程结构

```text
boot/             boot_linux 容器使用的 U-Boot 启动脚本
configs/          OpenWrt 最小配置和精确锁定的 feed
docs/             架构、构建、硬件、部署和维护文档
dts/              TB-RK3399ProD 唯一权威 DTS/DTSI
patches/openwrt/  OpenWrt profile、内核配置和镜像规则
patches/kernel/   直接作用于固定 Linux 6.12 的关键驱动补丁
patches/u-boot/   Toybrick U-Boot 板级补丁
rootfs/           注入固件的板级服务和首次启动默认值
scripts/          检查、初始化、构建和打包脚本
```

`.work/`、`out/` 和 `dist/` 均可重新生成，不纳入版本控制。完整文档入口见 [文档索引](docs/README.md)。

## 构建

在原生 Linux x86_64 主机执行：

```sh
make check
make -j4 init
make -j4 all
make package
```

| 目标 | 职责 |
|---|---|
| `make check` | 离线检查工程结构、脚本、补丁、配置和关键不变量 |
| `make init` | 获取固定上游和 `packages`/`luci` feed，应用补丁、同步 DTS/内核补丁/rootfs、生成配置并下载全部源包 |
| `make all` | 验证初始化状态，编译 U-Boot/OpenWrt 并生成部署镜像 |
| `make kmod KMODS="kmod-..."` | 使用同一工作树构建模块及其 kmod 依赖，ABI 完全匹配才输出 APK |
| `make package` | 校验 `out/` 并生成 `dist/` 发布包 |
| `make clean` | 只删除 `out/` 和 `dist/` |
| `make reset` | 校验 origin/固定 commit 后复位 `.work` 中的上游 Git 工作树 |
| `make -j2 reinit` | 依次执行 `reset` 和 `init` |

主机依赖、版本固定、并行参数、目录变量和完整初始化动作见 [构建说明](docs/BUILD.md)。

## 构建产物与部署

| 文件 | 用途 |
|---|---|
| `out/uboot/uboot.img` | 当前厂商 miniloader 启动链使用的 U-Boot |
| `out/openwrt/openwrt.img` | 从 LBA `0x6000` 连续写入的完整 OpenWrt 镜像，包含启动容器和 SquashFS rootfs |
| `out/openwrt/boot_linux.img`、`rootfs.img` | 组合镜像的分区级组件；前者也可用于保留 rootfs/overlay 的 boot-only 更新 |
| `out/openwrt/*initramfs-kernel.bin` | TF/串口恢复启动镜像 |
| `out/openwrt/` 其他文件 | OpenWrt 校验、版本、manifest 和构建信息 |
| `out/kmods/<kernel>/<request>/` | 与指定固件内核严格匹配的按需 kmod APK、依赖清单和校验文件 |
| `dist/*.tar.gz` | 只包含两个部署镜像、版本信息和 SHA256 的发布包 |

正常部署只写入 `uboot.img` 和 `openwrt.img`；原厂 `trust@0x4000` 保留不动。只更新内核/DTB 时可以单独写入 `boot_linux.img`，但必须保证它与原 rootfs 的内核模块 ABI 一致。刷写映射、SD/U-Boot 更新、恢复启动和上板验收见 [eMMC 部署与验收](docs/EMMC-INSTALL.md)，启动固件和分区设计依据见 [启动链设计](docs/BOOT-CHAIN.md)。

本工程不提供自动刷写或整盘 `dd` 脚本。不要把 OpenWrt 镜像写入 `trust` 分区。

## 维护与升级

`make clean` 只删除发布产物。若 `.work` 因中断的补丁或人工修改而污染，使用显式的 `make reset`；它会丢弃上游工作树内的 Git 修改，但保留 ignored 下载和编译缓存。修改 DTS、Linux 补丁或 `rootfs/` 后重新运行 `make init`，再构建并按 [硬件状态](docs/HARDWARE-STATUS.md) 和各专项文档完成回归。

Type-C 的一次性诊断使用固件内置 `tb-typec-diag`；设计、日志判读和升级测试见 [USB Type-C SuperSpeed 主机](docs/USB-TYPE-C.md)。
OpenWrt 官方预编译 `.ko` 与本项目内核配置不兼容，不能靠修改包管理哈希安全加载。普通扩展驱动使用 [按需 kmod 构建器](docs/KMOD-BUILDER.md)；启动和挂载 overlay 之前必需的驱动仍应内置固件。
