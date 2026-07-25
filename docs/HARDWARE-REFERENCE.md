# TB-RK3399ProD 硬件基线与升级参考

本文记录当前 OpenWrt 适配所依据的板级硬件、DTS 固定参数和实机已确认结果。以后升级 OpenWrt、Linux 或重做补丁时，应以本文和 `dts/` 为回归基线；设备编号（如 `mmcblk0`/`mmcblk1`）可能随内核变化，不能作为硬件身份依据。

实际构建以 `patches/openwrt/0001-tb-rk3399prod-board-support.patch` 中加入内核树的文件为准，`dts/` 是便于审阅的同步副本。刷新补丁时必须同时更新两处并检查差异；当前实机通过情况和未完成项目另见 `HARDWARE-STATUS.md`。

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

当前正式 profile 默认启用 PCIe。Wi-Fi、蓝牙、显示、摄像、音频、GPU 功能和 NPU 不属于本适配的完成条件。

## 2. SoC、内存与控制台

| 项目 | 关键参数 | 当前状态 |
|---|---|---|
| SoC | Rockchip RK3399Pro，AArch64 | 已确认启动 |
| CPU | 4× Cortex-A53 + 2× Cortex-A72，两个 cpufreq domain | 6 核和动态调频已确认 |
| 内存 | 4 GiB LPDDR3，双通道；每通道 2 GiB、32-bit、双 CS，DDR 初始化日志为 800 MHz | 原厂 DDR 日志已确认 |
| UART | UART2，`ttyS2`，1500000 baud，8N1 | 已确认 |
| earlycon | `uart8250,mmio32,0xff1a0000` | 已确认 |
| TSADC | `hw-tshut-mode=1`，`hw-tshut-polarity=1` | CPU/GPU thermal zone 已确认 |
| LEDs | 蓝 GPIO2_A5、红 GPIO2_A4、绿 GPIO2_A3，均高电平有效 | DTS 固定值 |

启动参数至少应保留：

```text
console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xff1a0000
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
- 实机容量约 29.1 GiB；HS400 Enhanced Strobe、CQE 和 ADMA 已识别。
- Linux 下预期可作为普通块设备读写，但升级前应按容量、CID/名称识别设备，不要依赖 `mmcblkN` 编号。正式改分区或安装前必须保留 loader、parameter、trust、U-Boot 和原系统分区备份。

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

实机已确认协商为 1000 Mb/s、全双工并启用 RX/TX flow control。升级时不能只以“接口能 ping”作为通过标准，还应检查 30–60 分钟双向吞吐、丢包、CRC、carrier、DMA/stmmac 错误和温度。最终长期压测结果仍应更新到 `HARDWARE-STATUS.md`。

## 6. USB

- USB2：两组 EHCI/OHCI 以及对应 USB2 PHY 已启用。
- USB3：DWC3/xHCI 以 host 模式启用，Type-C PHY1 已启用。
- USB3 host 电源使能：GPIO2_A2，输出高。
- 板载 USB Hub 复位：GPIO4_C5，输出高。
- 实机已确认 USB2/USB3 主控制器和板载 Hub 枚举；USB3 存储设备的持续吞吐仍需最终验收。

## 7. PCIe

| 参数 | 固定值 |
|---|---|
| Host 控制器 | `pcie@f8000000` |
| PHY / host | 默认 `okay` |
| 最大链路速率 | Gen1，`max-link-speed = 1` |
| Root Complex lanes | x4，`num-lanes = 4` |
| 插槽用途 | 可接 x1 PCIe 网卡 |
| ASPM | 禁用 L0s（`aspm-no-l0s`） |
| EP GPIO | GPIO0_B4，高有效 |
| CLKREQ# pinctrl | `pcie_clkreqn_cpm` |
| 电源 | 0.9 V、1.8 V、3.3 V；3.3 V 由 GPIO2_A6 使能 |

当前插槽没有端点设备。此时出现链路训练超时与厂商 BSP 行为一致，不代表供电或控制器必然故障。安装网卡后必须验证 `lspci -nnvv`、实际链路宽度/速率、AER 错误、驱动绑定、吞吐与重启稳定性；并按网卡型号启用 `igb`、`igc`、`r8169` 等对应驱动。

## 8. 升级回归清单

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
lspci -nnvv
dmesg | grep -Ei 'pcie|aer|usb|xhci|ehci|ohci|stmmac|gmac'
```

还应从构建后的 FIT 提取 DTB，确认 `model`、`compatible`、串口、RGMII delay、eMMC HS400、PCIe `status/max-link-speed/num-lanes` 和关键 regulator 没有在补丁刷新时丢失。升级验收顺序建议为：串口和电源 → CPU/温控 → TF/eMMC → 千兆网 → USB → 插有实物端点的 PCIe。
