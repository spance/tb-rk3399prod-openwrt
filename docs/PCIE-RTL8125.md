# PCIe RTL8125BG 2.5GbE

## 设计结论

RTL8125BG 安装在板载标准 PCIe 插槽，通过 RK3399Pro 的 PCIe 2.1 Root Complex 工作。网卡本身是 x1 端点，目标链路为 `5.0 GT/s, Width x1`；插槽和主控虽按 x4 描述，协商后只使用端点具备的一条 lane。

本工程使用 Linux 6.12 主线 `r8169`，不引入 Realtek 外置 `r8125`：

- 主线驱动已经匹配 PCI ID `10ec:8125`，并有明确的 RTL8125B 初始化路径。
- RTL8125B 所需的 `rtl_nic/rtl8125b-2.fw` 已由驱动声明。
- OpenWrt `kmod-r8169` 强依赖 `r8169-firmware`，因此驱动和固件会作为同一设备 profile 的依赖闭环进入只读固件。
- 这样继续服从 OpenWrt 内核 ABI、模块打包和安全更新机制，不承担厂商模块与 Linux 6.12 API 漂移的额外维护成本。

设备树显式设置 `max-link-speed = <2>`。Toybrick stable 4.4 的 RK3399Pro DTS 没有 Gen1 限制；Linux 6.12 Rockchip host 在未限速时也默认选择 Gen2。主线实现先建立 Gen1，再发起 Gen2 retrain；若信号质量不足，驱动会保留 Gen1 链路，最终速率可从 sysfs/`lspci` 明确观察。Gen1 x1 的有效单向载荷带宽约 2 Gbit/s，不能作为 2.5GbE 达标状态。

## 运行策略

板级服务使用 PCI vendor/device ID 查找网卡，不假设它一定叫 `eth1`。`r8169` 在 Linux 6.12 中申请一个 IRQ 并使用一个 NAPI，因此该 IRQ 统一放在 CPU5/Cortex-A72；板载 GMAC 继续使用 CPU4。S99 启动服务和任意 netifd `ifup` 事件都会运行同一段幂等逻辑。

固件不会自动把新网卡分配给 WAN 或 LAN。安装后先确认 MAC、物理口和当前接口名，再通过 LuCI 或 UCI 明确配置，避免枚举顺序变化导致管理口或防火墙 zone 被意外替换。

PCIe 插槽不按热插拔设计。安装、拆卸或重新插紧网卡前必须正常关机并断电；不要带电插拔。

## 首次上板验收

刷入包含本次适配的镜像并冷启动后，先运行：

```sh
tb-rtl8125-diag > /tmp/rtl8125-diag.txt 2>&1
```

必须同时满足：

1. `lspci -nnk` 能看到 `10ec:8125`，`Kernel driver in use` 为 `r8169`。
2. `/lib/firmware/rtl_nic/rtl8125b-2.fw` 存在，日志没有 firmware load failure。
3. endpoint 和 root port 的 `LnkSta` 均为 `Speed 5GT/s, Width x1`，sysfs 显示 `5.0 GT/s`、宽度 `1`。
4. `ethtool` 在连接 2.5GbE 对端和合格线材时显示 `Speed: 2500Mb/s`、`Duplex: Full`。
5. RTL8125 的 MSI IRQ affinity 为 CPU5；板载 GMAC 仍为 CPU4。
6. 日志没有 link training failure、AER、PCIe completion timeout、r8169 Tx timeout 或 firmware error。

若只得到 Gen1，不应把它当作驱动成功后的正常降速。先检查卡是否完全插入、金手指与插槽、电源、线缆固定和冷启动复现，再保留完整 `tb-rtl8125-diag` 输出分析。不要通过替换 `r8125` 驱动掩盖 PCIe 物理层问题。

## 网络与压力测试

先为测试接口配置不会与现网冲突的地址，然后记录测试前状态：

```sh
DEV="$(for p in /sys/class/net/*; do [ "$(cat "$p/device/vendor" 2>/dev/null)" = 0x10ec ] && [ "$(cat "$p/device/device" 2>/dev/null)" = 0x8125 ] && basename "$p"; done)"
ethtool "$DEV"
ethtool -S "$DEV" > /tmp/rtl8125-before.txt
ip -s link show dev "$DEV"
```

本机收发先各跑 30 分钟：

```sh
iperf3 -c <server-ip> -P 4 -t 1800
iperf3 -c <server-ip> -P 4 -t 1800 -R
```

随后再次保存 `ethtool -S`、`ip -s link`、`dmesg` 和 `tb-rtl8125-diag`。验收不仅看吞吐，还要求 CRC、missed、FIFO、timeout、PCIe/AER 与 carrier change 没有非预期增长。再执行至少 10 次冷启动和 10 次软重启，确认每次都稳定获得 Gen2 x1、2500/full 和相同驱动。

如果用于路由，再分别测试软件 flow offload 开/关、双向并发和实际防火墙规则。板载 GMAC 只有 1GbE，因此 RTL8125 与板载口之间的普通双口路由上限仍由 1GbE 端决定；2.5GbE 本机访问或 RTL8125 上的多 VLAN 单臂路由才具备超过 1GbE 的链路条件。

默认保留主线驱动的 checksum、scatter-gather、TSO/GSO 和 EEE 策略，不预先关闭 offload 或 EEE。只有出现可复现的协商、掉线或错误计数问题，才用 `ethtool -K` / `--set-eee` 做单变量 A/B，并把结论沉淀为板级策略。
