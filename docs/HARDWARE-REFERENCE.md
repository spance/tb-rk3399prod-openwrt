# TB-RK3399ProD 硬件基线与升级参考

本文记录当前 OpenWrt 适配所依据的板级硬件、DTS 固定参数和实机已确认结果。以后升级 OpenWrt、Linux 或重做补丁时，应以本文和 `dts/` 为回归基线；设备编号（如 `mmcblk0`/`mmcblk1`）可能随内核变化，不能作为硬件身份依据。

`dts/rk3399pro-toybrick-prod.dts` 和 `.dtsi` 是实际构建使用的唯一板级设备树来源。`make init` 会读取 OpenWrt Rockchip target 的内核补丁版本，并通过 `scripts/sync-openwrt-dts.sh` 覆写到对应源码树；`patches/openwrt/0001-tb-rk3399prod-board-support.patch` 只保存 profile、DTB 构建入口和必要的内核 binding 修改，不再包含完整 DTS。以后修改硬件描述只改 `dts/`，然后重新执行 `make init` 再构建。当前实机通过情况和未完成项目另见 `HARDWARE-STATUS.md`。

## 1. 软件基线

| 组件 | 当前基线 |
|---|---|
| 开发板 | Toybrick TB-RK3399ProD |
| DT compatible | `rockchip,rk3399pro-toybrick-prod`、`rockchip,rk3399pro` |
| OpenWrt | `v25.12.5`，commit `f0a60eee2fe051741c643ea6118718aae1ef17fb` |
| Linux | `6.12.94` |
| Toybrick U-Boot | commit `22af63bad708ff41513375a8ecf7fe8d2d521c84`，带本工程补丁 |
| Toybrick rkbin | commit `78c1c4939634a76f6f4531c912c1a52a83f0451b` |
| Toybrick linux-x86 工具链 | commit `32505a8032d04e9320dbdb817b08bf67bdfb5a0c` |
| OpenWrt target | `rockchip/armv8`，profile `toybrick_tb-rk3399prod` |

当前正式 profile 默认启用独立 x4 插座的 PCIe host 和 HDMI Linux 文本 console。板载 Mini-PCIe 只接 USB2；无线、蓝牙、摄像、音频、图形桌面、GPU 功能和 NPU 不属于本阶段的完成条件，相关无线驱动和固件也不纳入镜像。

## 2. SoC、内存与控制台

| 项目 | 关键参数 | 当前状态 |
|---|---|---|
| SoC | Rockchip RK3399Pro，AArch64 | 已确认启动 |
| CPU | 4× Cortex-A53 + 2× Cortex-A72，两个 cpufreq domain；`CONFIG_CPU_FREQ_THERMAL=y` | 6 核、负载调频和 cpufreq cooling device 已确认；未故意加热到降频点 |
| 内存 | 4 GiB LPDDR3，双通道；每通道 2 GiB、32-bit、双 CS，DDR 初始化日志为 800 MHz | 原厂 DDR 日志已确认 |
| UART | UART2，`ttyS2`，1500000 baud，8N1 | 已确认 |
| earlycon | `uart8250,mmio32,0xff1a0000` | 已确认 |
| HDMI console | RK3399 VOPB + DW-HDMI，`tty0`/`tty1` | 显示输出和文本 console 已确认 |
| TSADC | `hw-tshut-mode=1`，`hw-tshut-polarity=1`；CPU cpufreq cooling | CPU/GPU thermal zone 与两个 CPU cooling device 的 trip 绑定已确认 |
| Watchdog | RK3399 DesignWare WDT；TOP 计数为 2^16～2^31；`procd` 30 秒超时、每 5 秒喂狗 | 驱动、设备节点和运行状态已确认；故障复位未做破坏性测试 |
| LEDs | 蓝 GPIO2_A5、红 GPIO2_A4、绿 GPIO2_A3，均高电平有效 | DTS 固定值 |

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
- 厂商 U-Boot 的 TF 路径使用本工程可靠性补丁：25 MHz、PIO，单次请求最多 2048 blocks（1 MiB）。这个限制只用于 U-Boot 读卡，不应误套到 Linux eMMC。

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
- 蓝色 Type-A 口已由多种设备确认工作在 `5000M`；Lexar E300 2 TB M.2 移动硬盘使用 UAS，4 GiB direct read 约 319 MiB/s，测试后无新增 USB/UAS/SCSI 错误，已经证明该物理口的 SuperSpeed 路径可达到正常高速区间。
- Type-C USB3：DWC3_0 `fe800000.usb`、`tcphy0`，连接器固定为 source/host；FUSB302 位于 I2C8 `0x22`，中断 GPIO1_A2 低有效，VBUS 由 GPIO0_A1 低电平使能，对外声明 5 V/1.5 A。DWC3 内部使用 `dr_mode = "otg"` 和 `usb-role-switch`，仅用于在插拔/换向时退出并重建 host/xHCI。
- Linux 6.12 的 RK3399 Type-C PHY 缺少 TCPM orientation-switch 支持；工程回移 Rockchip 2026 年 v15 方案的 USB 部分，并在方向改变时重新初始化 SuperSpeed lanes。实机手工重绑 DWC3 后，C 口已用同一块 Lexar E300 确认 UAS/`5000M` 和约 349 MiB/s 的 4 GiB direct read，且无新增 USB/UAS/SCSI 错误；自动 role-switch 版本仍需刷机完成两个方向和热插拔回归。设计和测试方法见 [USB Type-C SuperSpeed 主机](USB-TYPE-C.md)。
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
| 最大链路速率 | Gen1，`max-link-speed = 1` |
| Root Complex lanes | x4，`num-lanes = 4` |
| 物理出口 | 独立 PCIe x4 板对板插座；允许通过合适转接板连接 x1 端点 |
| ASPM | 禁用 L0s（`aspm-no-l0s`） |
| EP GPIO | GPIO0_B4，高有效 |
| CLKREQ# pinctrl | `pcie_clkreqn_cpm` |
| 电源 | 0.9 V、1.8 V、3.3 V；3.3 V 由 GPIO2_A6 使能 |

本板有两个容易混淆的插座：上述 SoC PCIe host 只连接到独立 x4 板对板插座；板载 Mini-PCIe 插座只接 USB2，面向 LTE 模块，没有 PCIe lane。标准 PCIe 端点插入 Mini-PCIe 后不会出现在 `lspci`，DTS 或驱动无法弥补缺失的电气连线；`pcie@f8000000` 的 Gen1 training timeout 表示独立 x4 插座没有建立端点链路，与 Mini-PCIe 中是否插卡无关。

独立 x4 插座仍保持启用，供未来通过匹配其板对板定义的转接板安装 PCIe 网卡或其他端点。具体设备驱动应在确定型号后按需加入，不预装当前没有硬件用途的无线驱动。安装端点后必须验证 `lspci -nnk`、实际链路宽度/速率、AER 错误、吞吐与重启稳定性。

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
dmesg | grep -Ei 'pcie|aer|usb|typec|tcpm|fusb|xhci|ehci|ohci|stmmac|gmac|drm|vop|hdmi|fbcon'
```

还应从构建后的 FIT 提取 DTB，确认 `model`、`compatible`、串口、HDMI/VOPB、RGMII delay、eMMC HS400、PCIe `status/max-link-speed/num-lanes` 和关键 regulator 没有在补丁刷新时丢失。升级验收顺序建议为：串口和电源 → CPU/温控 → TF/eMMC → 千兆网 → USB → HDMI → 插有实物端点的 PCIe。
