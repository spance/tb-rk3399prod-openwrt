# TB-RK3399ProD 硬件基线与升级参考

本文记录当前 OpenWrt 适配所依据的板级硬件、DTS 固定参数和实机已确认结果。以后升级 OpenWrt、Linux 或重做补丁时，应以本文和 `dts/` 为回归基线；设备编号（如 `mmcblk0`/`mmcblk1`）可能随内核变化，不能作为硬件身份依据。

`dts/rk3399pro-toybrick-prod.dts` 和 `.dtsi` 是实际构建使用的唯一板级设备树来源。`make init` 会读取 OpenWrt Rockchip target 的内核补丁版本，并通过 `scripts/sync-openwrt-dts.sh` 覆写到对应源码树；`patches/openwrt/0001-tb-rk3399prod-board-support.patch` 只保存 profile、DTB 构建入口和必要的内核 binding 修改，不再包含完整 DTS。以后修改硬件描述只改 `dts/`，然后重新执行 `make init` 再构建。当前实机通过情况和未完成项目另见 `HARDWARE-STATUS.md`。

## 1. 软件基线

| 组件 | 当前基线 |
|---|---|
| 开发板 | Toybrick TB-RK3399ProD |
| DT compatible | `rockchip,rk3399pro-toybrick-prod`、`rockchip,rk3399pro` |
| 官方板级行为基线 | `rockchip-toybrick/kernel` 的 `stable` 分支，Linux 4.4，固定提交 `a80be5749ac552821967eff313df53f9e0cd1e01` |
| OpenWrt | `v25.12.5`，commit `f0a60eee2fe051741c643ea6118718aae1ef17fb` |
| OpenWrt 目标 Linux | `6.12.94` |
| Rockchip vendor U-Boot | `next-dev` commit `aeec6f2bfd5ce0cfcdfe0ffc7f84d9d143683856`，带本工程板级补丁和 OP-TEE API 2.0 客户端 |
| Rockchip rkbin | commit `ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4`；BL31 v1.35、BL32 v2.12、DDR v1.30、miniloader v1.26 与官方 merger 的固定构建输入 |
| Toybrick linux-x86 工具链 | commit `32505a8032d04e9320dbdb817b08bf67bdfb5a0c` |
| OpenWrt target | `rockchip/armv8`，profile `toybrick_tb-rk3399prod` |

以后升级时，板级连线、供电、复位、时钟、引脚和外设事件顺序优先参考上述 Toybrick stable 4.4；目标 6.x 内核用于选择当前子系统 API 和已合入的通用修复；Rockchip 其他 6.x 分支及邮件列表补丁只能作为移植线索。任何无法静态证明等价的差异都必须保留为待验收项，并以本板实机测试闭环。

当前正式 profile 默认启用独立 PCIe 插槽的 Gen2 host、RTL8125BG 主线驱动/固件和 HDMI Linux 文本 console。板载 Mini-PCIe 只接 USB2；无线、蓝牙、摄像、音频、图形桌面、GPU 功能和 NPU 不属于本阶段的完成条件，相关无线驱动和固件也不纳入镜像。

## 2. SoC、内存与控制台

| 项目 | 关键参数 | 当前状态 |
|---|---|---|
| SoC | Rockchip RK3399Pro，AArch64 | 已确认启动 |
| CPU | 4× Cortex-A53 + 2× Cortex-A72，两个 cpufreq domain；`CONFIG_CPU_FREQ_THERMAL=y` | 6 核、负载调频和 cpufreq cooling device 已确认；未故意加热到降频点 |
| 内存 | 4 GiB LPDDR3，双通道；每通道 2 GiB、32-bit、双 CS；当前实机为 DDR bin v1.27、BL31 v1.30、800 MHz；构建目标为 DDR v1.30、BL31 v1.35 | 原厂基线已确认；新版 loader/trust 和无损 ROUND 探测待实机验收 |
| UART | UART2，`ttyS2`，1500000 baud，8N1 | 已确认 |
| earlycon | `uart8250,mmio32,0xff1a0000` | 已确认 |
| HDMI console | RK3399 VOPB + DW-HDMI，`tty0`/`tty1` | 显示输出和文本 console 已确认 |
| TSADC | `hw-tshut-mode=1`，`hw-tshut-polarity=1`；CPU cpufreq cooling | CPU/GPU thermal zone 与两个 CPU cooling device 的 trip 绑定已确认 |
| Watchdog | RK3399 DesignWare WDT；TOP 计数为 2^16～2^31；`procd` 30 秒超时、每 5 秒喂狗 | 已确认驱动、设备节点、喂狗及停止喂狗后的硬件复位 |
| LEDs | 蓝 GPIO2_A5、红 GPIO2_A4、绿 GPIO2_A3，均高电平有效 | `leds-gpio` 已绑定，三路亮灭与 OpenWrt 状态切换已确认 |

三个 LED 沿用 Toybrick stable 4.4 DTS 的 GPIO 和极性，但使用标准 LED common binding 命名。DTS aliases 将蓝灯用于 `led-boot`，红灯用于 `led-failsafe`/`led-upgrade`，绿灯用于 `led-running`；OpenWrt `/etc/diag.sh` 和 `/lib/functions/leds.sh` 会直接消费这些别名，因此无需再增加板级常驻脚本。正常运行状态为蓝灭、红灭、绿亮。

临时人工控制可直接写 `/sys/class/leds/blue:status/brightness`、`red:fault/brightness` 或 `green:status/brightness`，取值为 `0`/`1`。这只适合调试；正式启动状态应继续由 OpenWrt 标准状态机管理，避免自定义脚本与 failsafe 或升级指示竞争。

启动参数至少应保留：

```text
console=tty0 console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xff1a0000
```

### 启动内存约束

```text
可用 DRAM bank 0:  0x00200000 - 0x08400000
TEE/BL32 保留区:   0x08400000 - 0x0a200000
可用 DRAM bank 1:  0x0a200000 - 0xf8000000
FIT 加载地址:       0x10000000
Linux load/entry:  0x03200000
```

不得再把约 30 MiB 的 FIT 加载到 `0x08000000`：它会跨入 TEE/BL32 保留区，并可能令 U-Boot 在解析 FIT 时触发 `Synchronous Abort`。

## 3. PMIC 与主要电源轨

I2C0 工作在 400 kHz。主 PMIC 是 RK809，地址 `0x20`，中断为 GPIO1_C2、低电平有效，并作为系统电源控制器。CPU/GPU 的三个关键电源域为 `vdd_cpu_l`、`vdd_cpu_b` 和 `vdd_gpu`。

Linux 6.12 基线中，TCS4525/TCS4526 由兼容的 `fan53555` regulator 驱动处理；升级内核时需要重新检查 `tcs,tcs4526` binding 和 OF match 是否仍存在。

| 电源轨 | 器件/通道 | 电压范围或固定值 | 用途与关键参数 |
|---|---|---|---|
| `vdd_cpu_l` | RK809 DCDC2 | 0.75–1.35 V | 4 个 A53；ramp 6001 |
| `vdd_cpu_b` | TCS4525，I2C `0x1c` | 0.7125–1.3875 V | 2 个 A72；ramp 2300；VSEL GPIO1_C1 |
| `vdd_gpu` | TCS4526，I2C `0x10` | 0.7375–1.3875 V | GPU 电源；ramp 2300；VSEL GPIO1_B6；GPU 功能当前禁用 |
| `vdd_center` | RK809 DCDC1 | 0.75–1.35 V | 核心电源 |
| `vcc_ddr` | RK809 DCDC3 | 由 PMIC 配置 | DDR 电源 |
| `vcc3v3_sys` | RK809 DCDC4 | 3.3 V | 系统 3.3 V |
| `vcc_buck5` | RK809 DCDC5 | 2.2 V | PMIC LDO 输入 |
| `vdd_log` | 固定稳压器 | 0.9 V | always-on |
| `vcc5v0_sys` | 固定稳压器 | 5 V | 板级主 5 V |
| `vcc_phy` | 固定稳压器 | 3.3 V | RTL8211E PHY |
| `vcc_pcie` | 固定稳压器 | 3.3 V | GPIO2_A6 使能；正式配置 always-on/boot-on |
| `vcca_0v9` / `vcca_1v8` | RK809 LDO1/LDO4 | 0.9 V / 1.8 V | PCIe 模拟电源 |
| `vcc_sd` / `vccio_sd` | RK809 LDO9/LDO8 | 3.3 V / 1.8–3.3 V | TF 卡供电与 I/O 电压 |

升级内核后，RK809、TCS4525/TCS4526 或 regulator probe 失败属于阻断性回归；不要在电源轨未确认时进行 CPU、存储或 PCIe 压力测试。

## 4. 存储

### TF 卡

- 控制器别名 `mmc0 = &sdmmc`，硬件节点 `dwmmc@fe320000`，4-bit。
- 卡检测 GPIO0_A7，低电平有效；无写保护。
- DTS 保留 `max-frequency = 150000000`，但当前 Linux 实机确认的稳定工作值为 50 MHz、Rockchip IDMAC。
- Rockchip vendor U-Boot 的 TF 路径使用本工程可靠性参数：25 MHz、PIO，单次请求最多 2048 blocks（1 MiB），并保留错误/超时诊断。这个限制只用于 U-Boot 读卡，不应误套到 Linux eMMC。

### eMMC

- 控制器别名 `mmc1 = &sdhci`，硬件节点 `sdhci@fe330000`，8-bit、不可移除。
- HS400 1.8 V、Enhanced Strobe、eMMC PHY 均启用。
- 实机容量约 29.1 GiB；HS400 Enhanced Strobe 和 ADMA 已确认。CQE 曾正常识别为深度 16，但连续写入会反复触发无数据损坏的 recovery；正式配置通过 Linux 现有 `SDHCI_QUIRK_BROKEN_CQE` 将其关闭，以稳定性优先。该 quirk 不关闭 HS400、Enhanced Strobe 或 ADMA。
- Linux 下可作为普通块设备读写，但管理命令应按容量、CID/名称或 GPT `PARTLABEL` 识别设备，不要依赖 `mmcblkN` 编号。
- 当前部署 GPT 使用 512-byte sector：`uboot@0x2000` 为 4 MiB，`trust@0x4000` 为 4 MiB，`boot_linux@0x6000` 为 96 MiB，`rootfs@0x36000` 占用剩余空间。前两项属于厂商 miniloader 启动链约束；后两项是当前工程镜像和启动脚本共同采用的发布约定，并非 RK3399Pro 不可改变的硬件地址。边界和替代方案见 [启动链设计](BOOT-CHAIN.md)。
- 工程将内部的 64 MiB 启动容器和 128 MiB rootfs 载体组合为 224 MiB `openwrt.img`，从 LBA `0x6000` 连续写入后，rootfs 自动落在 LBA `0x36000`。启动参数使用 `root=PARTLABEL=rootfs` 和 `fstools_overlay_fstype=ext4`；SquashFS 后面的全部剩余空间由 OpenWrt `fstools` 在首次启动时格式化为 ext4 `/overlay`。该设计不调整 GPT，也不依赖 eMMC 的动态设备编号。完整映射、持久化和重装边界见 `EMMC-INSTALL.md`。

## 5. 千兆以太网

| 参数 | 固定值 |
|---|---|
| MAC 控制器 | RK3399 GMAC / stmmac |
| PHY | Realtek RTL8211E，MDIO 地址 0 |
| 接口 | RGMII |
| 外部时钟 | 125 MHz，输入模式 |
| TX delay | `0x28` |
| RX delay | `0x20` |
| PHY reset | GPIO3_C0，低有效 |
| reset 时序 | assert 10 ms，deassert 50 ms |
| PHY 供电 | `vcc_phy`，3.3 V |

实机已确认协商为 1000 Mb/s、全双工并启用 RX/TX flow control。两个方向各 1800 秒、4 流 TCP 测试均达到 941 Mbit/s 和 197 GiB，测试后的 CRC、carrier、DMA/stmmac 等硬件错误计数为 0。板级启动服务动态解析 GMAC IRQ 并绑定 CPU4/A72；软件 flow offload 默认开启、硬件 flow offload 关闭。详细数据、适用边界和升级后的 A/B 方法见 [网络性能与加速策略](NETWORK-PERFORMANCE.md)。

## 6. USB

- USB2：两组 EHCI/OHCI 以及对应 USB2 PHY 已启用。
- 蓝色 Type-A USB3：DWC3_1/xHCI `fe900000.usb`、`tcphy1`，固定 host 模式。
- Type-A USB3 host 电源使能：GPIO2_A2，输出高。
- 板载 USB Hub 复位：GPIO4_C5，输出高。
- 正式 profile 内置 USB Mass Storage、UAS、FAT32 和 exFAT 驱动；常见 U 盘、SSD 与移动硬盘无需联网安装文件系统模块。
- 蓝色 Type-A 口已由多种设备确认工作在 `5000M`；Lexar E300 2 TB M.2 移动硬盘使用 UAS，实测约 340～360 MB/s，测试后无新增 USB/UAS/SCSI 错误，已经证明该物理口的 SuperSpeed 路径可达到正常高速区间。
- Type-C USB3：DWC3_0 `fe800000.usb`、`tcphy0`，连接器固定为 source/host；FUSB302 位于 I2C8 `0x22`，中断 GPIO1_A2 低有效，VBUS 由 GPIO0_A1 低电平使能，对外声明 5 V/1.5 A。DWC3 使用 `dr_mode = "otg"` 和 `usb-role-switch` 取得正确的断开/重连生命周期，但连接器不会请求 gadget 角色。
- 本板 Type-C 的行为基线是 Toybrick stable Linux 4.4；Linux 6.12 只提供当前 API，Rockchip 6.6 只作现代实现参考。工程按 4.4 时序实现 PHY 方向记录/5 次上电重试，以及 detach 时删除 xHCI 并关闭 core/PHY；attach 时先脉冲父节点 `SRST_A_USB3_OTG0`，再由 DWC3 子核心恢复并给 PHY 上电，等待 10–11 ms 后才创建 xHCI。方向回调不在线重置 PHY，只由后续 `power_on()` 配置当前方向的一对 lanes。Lexar E300 已在首次插入、同向重插和翻转重插中确认 UAS/`5000M`；exFAT 上 8 GiB direct 写约 300～320 MiB/s、direct 读约 340 MiB/s，并通过完整数据比较，测试窗口没有新增 USB/UAS/SCSI/I/O/文件系统错误。设计与完整证据见 [USB Type-C SuperSpeed 主机](USB-TYPE-C.md)。
- Type-C 的 Linux 配置不修改 BootROM/U-Boot；Loader/Maskrom 刷机接口继续保留。

## 7. HDMI console

| 项目 | 固定值 |
|---|---|
| HDMI TX / PHY | `hdmi@ff940000`，Synopsys DW-HDMI + Rockchip INNO HDMI PHY |
| 显示控制器 | VOPB `vop@ff900000` 及 `iommu@ff903f00` |
| DDC | I2C3，SCL rise/fall `450/15 ns` |
| 模拟电源 | `vcca_0v9` / `vcca_1v8` |
| 内核终端 | `console=tty0`；`tty1::askfirst` |
| 恢复终端 | UART2 1500000，始终保留并列在 bootargs 最后 |

HDMI 只承担 Linux 文本 console；U-Boot 显示、HDMI 音频、桌面和 GPU 不在范围内。模式由 EDID 自动选择，不固定分辨率。详细验收见 [HDMI Linux console](HDMI-CONSOLE.md)。

## 8. PCIe

| 参数 | 固定值 |
|---|---|
| Host 控制器 | `pcie@f8000000` |
| PHY / host | 默认 `okay` |
| 最大链路速率 | Gen2，`max-link-speed = 2`；Gen2 二次训练失败时主线驱动自动保留 Gen1 链路 |
| Root Complex lanes | x4，`num-lanes = 4` |
| 物理出口 | 板载标准 PCIe x4 机械槽，四条 lane 均有连线；可直接安装 x1 卡 |
| 当前目标端点 | Realtek RTL8125BG，PCI ID `10ec:8125`，PCIe 2.1 x1 |
| Linux 驱动 | Linux 6.12 主线 `r8169`；OpenWrt `kmod-r8169` 自动带入 `r8169-firmware` |
| RTL8125B 固件 | `/lib/firmware/rtl_nic/rtl8125b-2.fw` |
| ASPM | 禁用 L0s（`aspm-no-l0s`） |
| EP GPIO | GPIO0_B4，高有效 |
| CLKREQ# pinctrl | `pcie_clkreqn_cpm` |
| 电源 | 0.9 V、1.8 V、3.3 V；3.3 V 由 GPIO2_A6 使能 |

本板有两个容易混淆的插座：上述 SoC PCIe host 连接到标准 PCIe x4 机械槽；板载 Mini-PCIe 插座只接 USB2，面向 LTE 模块，没有 PCIe lane。标准 PCIe 端点插入 Mini-PCIe 后不会出现在 `lspci`，DTS 或驱动无法弥补缺失的电气连线；`pcie@f8000000` 的 link training timeout 表示标准 PCIe 槽没有建立端点链路，与 Mini-PCIe 中是否插卡无关。

RTL8125BG 以一条 lane 工作，正确目标是 `5.0 GT/s, Width x1`。Gen1 x1 的有效单向带宽只有约 2 Gbit/s，无法承载 2.5GbE 线速，因此本工程显式使用 Gen2；这也与 Toybrick stable 4.4 DTS 未设置 Gen1 限制、Linux 6.12 RK3399 host 默认选择 Gen2 的行为一致。主线 host 先建立 Gen1 再请求 Gen2 重训练，失败会自动回退而不是丢弃已经建立的 Gen1 链路。

生产镜像使用 Linux 主线 `r8169`，不引入 Realtek 外置 `r8125`。Linux 6.12 已包含 `10ec:8125` ID、RTL8125B 初始化路径和 `rtl8125b-2.fw` 声明；OpenWrt 的 `kmod-r8169` 对相应 firmware 包是强依赖。板级脚本按 PCI ID 识别它并把单 IRQ/NAPI 放到 CPU5，板载 GMAC 则继续位于 CPU4。固件不按可能变化的 `ethN` 名称自动分配 WAN/LAN，首次部署需在 LuCI/UCI 中明确选择。详细设计和验收见 [PCIe RTL8125BG 2.5GbE](PCIE-RTL8125.md)。

## 9. 升级回归清单

升级 OpenWrt 或 Linux 后，至少保存以下输出，与本页逐项比较：

```sh
uname -a
tr -d '\0' </proc/device-tree/model; echo
cat /proc/cmdline
cat /proc/cpuinfo
dmesg | grep -Ei 'rk8|tcs45|regulator|cpufreq|thermal|tsadc'
lsblk -o NAME,PATH,SIZE,MODEL,TRAN,FSTYPE,MOUNTPOINTS
dmesg | grep -Ei 'mmc|sdhci|dwmmc|cqe|adma'
ethtool eth0
ethtool -S eth0
ip -s link show dev eth0
lsusb -t
find /sys/class/typec -maxdepth 2 -type f -print 2>/dev/null
lspci -nnvv
tb-rtl8125-diag
dmesg | grep -Ei 'pcie|aer|usb|typec|tcpm|fusb|xhci|ehci|ohci|stmmac|gmac|drm|vop|hdmi|fbcon'
```

还应从构建后的 FIT 提取 DTB，确认 `model`、`compatible`、串口、HDMI/VOPB、RGMII delay、eMMC HS400、PCIe `status/max-link-speed/num-lanes` 和关键 regulator 没有在补丁刷新时丢失。升级验收顺序建议为：串口和电源 → CPU/温控 → TF/eMMC → 千兆网 → USB → HDMI → 插有实物端点的 PCIe。
