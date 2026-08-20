# PCIe RTL8125BG 2.5GbE

## 设计结论

RTL8125BG 安装在板载标准 PCIe 插槽，通过 RK3399Pro 的 PCIe 2.1 Root Complex 工作。网卡本身是 x1 端点，目标链路为 `5.0 GT/s, Width x1`；插槽和主控虽按 x4 描述，协商后只使用端点具备的一条 lane。

本工程使用 Linux 6.12 主线 `r8169`，不引入 Realtek 外置 `r8125`：

- 主线驱动已经匹配 PCI ID `10ec:8125`，并有明确的 RTL8125B 初始化路径。
- RTL8125B 所需的 `rtl_nic/rtl8125b-2.fw` 已由驱动声明。
- OpenWrt `kmod-r8169` 强依赖 `r8169-firmware`，因此驱动和固件会作为同一设备 profile 的依赖闭环进入只读固件。
- 这样继续服从 OpenWrt 内核 ABI、模块打包和安全更新机制，不承担厂商模块与 Linux 6.12 API 漂移的额外维护成本。

设备树显式设置 `max-link-speed = <2>`。Toybrick stable 4.4 的 RK3399Pro DTS 没有 Gen1 限制；Linux 6.12 Rockchip host 在未限速时也默认选择 Gen2。主线实现先建立 Gen1，再发起 Gen2 retrain；若信号质量不足，驱动会保留 Gen1 链路，最终速率可从 sysfs/`lspci` 明确观察。Gen1 x1 的有效单向载荷带宽约 2 Gbit/s，不能作为 2.5GbE 达标状态。

## PI7C9X2G304SV 交换扩展板

扩展板使用 PI7C9X2G304SV `12d8:b304` 把一条上行链路分成两个下行端口。
x86 Linux 已确认其合法稀疏拓扑：上游端口位于 Device 0，下一层总线的
Device 0 不存在，两个下游桥分别位于 Device 1 和 Device 2；安装 RTL8125
后可继续枚举到下行 Device 0 的 `10ec:8125`。因此这组结果已经验证交换芯片、
板级上行链路、内部端口配置和至少一个下行端口，但不能替代 RK3399 实机验收。

RK3399 AXI PCIe 控制器对无目标配置读取不能可靠返回全 1，而可能向 ARM64
报告同步外部总线异常。Linux 6.12 原有 `rockchip_pcie_valid_device()` 只过滤
Root Port 及其直属总线；继续扫描交换芯片内部总线时会先访问不存在的 Device 0，
在看到 Device 1/2 之前崩溃。规范补丁
`patches/kernel/147-pcie-rockchip-pi7c9x2g304-safe-scan.patch` 只匹配实际的
`12d8:b304`：

- 上游交换端口的子总线只允许 Device 1、2，其他 Device 直接报告不存在；
- 下游端口的子总线只允许点到点的 Device 0；
- Device 0 仅在下游 Link Status 的 Data Link Layer Link Active 置位时访问；
  首次扫描最多等待约 180 ms，兼顾端点复位后的链路收敛；
- 直连 RTL8125 和其他非 PI7C9X2G304SV 桥保持原有扫描逻辑。

这是控制器访问安全修复，不是用软件掩盖链路错误。扩展板在 RK3399 上仍按以下
顺序验收，任何阶段出现 external abort、AER、completion timeout 或异常复位都
不得进入下一阶段：

1. 空扩展板冷启动，确认 `12d8:b304` 的上游端口和 Device 1/2 两个下游桥均
   被枚举，两个空端口只记录 link inactive，系统继续启动。
2. 断电后只安装 RTL8125，确认完整拓扑、`r8169`、Gen2 x1 和 2500/full。
3. 分别只安装第二端点以及同时安装两个端点，确认两条下行链路互不影响。
4. 至少执行 10 次冷启动、10 次软重启，再分别进行单端点和双端点压力测试。

扩展板插槽同样不支持带电插拔。当前状态是“x86 硬件拓扑已确认、RK3399驱动
修复待上板”，在上述闭环完成前不宣称扩展板已经交付。

## 运行策略

板级服务使用 PCI vendor/device ID 查找网卡，不假设它一定叫 `eth1`。`r8169` 在 Linux 6.12 中申请一个 IRQ 并使用一个 NAPI，因此该 IRQ 统一放在 CPU5/Cortex-A72；板载 GMAC 继续使用 CPU4。S99 启动服务和任意 netifd `ifup` 事件都会运行同一段幂等逻辑。

固件不会自动把新网卡分配给 WAN 或 LAN。安装后先确认 MAC、物理口和当前接口名，再通过 LuCI 或 UCI 明确配置，避免枚举顺序变化导致管理口或防火墙 zone 被意外替换。

PCIe 插槽不按热插拔设计。安装、拆卸或重新插紧网卡前必须正常关机并断电；不要带电插拔。

## 已完成的实机验收

当前 RTL8125BG 实卡的 PCI ID 为 `10ec:8125` rev 05，已完成以下闭环：

- endpoint 与 RK3399 root port 都协商为 `5.0 GT/s, Width x1`，网口为 `2500Mb/s, Full`。
- Linux 6.12.94 主线 `r8169` 正常绑定，加载 `rtl8125b-2_0.0.2` 固件，使用单个 MSI IRQ 和单个 RX queue。
- checksum、scatter-gather、TSO、GSO 和 GRO 保持启用；测试期间没有 PCIe AER、驱动 timeout、异常复位或链路抖动。
- 满载时 CPU/GPU 温度保持在约 46 °C 以下。

测试时把第二网口放入独立 network namespace，使用静态地址且不加入 `br-lan`，避免两个物理口位于同一广播域时影响现有 DHCP、路由或形成回环。namespace 中的接口不会出现在默认环境的 `ip address` 输出；测试结束后接口被移回默认 namespace，并保持未配置和 `DOWN`。

固件内置的一次性诊断入口为：

```sh
tb-rtl8125-diag > /tmp/rtl8125-diag.txt 2>&1
```

升级内核、DTS、U-Boot 或 PCIe 参数后仍必须满足：

1. `lspci -nnk` 能看到 `10ec:8125`，`Kernel driver in use` 为 `r8169`。
2. `/lib/firmware/rtl_nic/rtl8125b-2.fw` 存在，日志没有 firmware load failure。
3. endpoint 和 root port 的 `LnkSta` 均为 `Speed 5GT/s, Width x1`，sysfs 显示 `5.0 GT/s`、宽度 `1`。
4. `ethtool` 在连接 2.5GbE 对端和合格线材时显示 `Speed: 2500Mb/s`、`Duplex: Full`。
5. 正式运行策略把 RTL8125 的 MSI IRQ affinity 设为 CPU5；板载 GMAC 仍为 CPU4。
6. 日志没有 link training failure、AER、PCIe completion timeout、r8169 Tx timeout 或 firmware error。

若只得到 Gen1，不应把它当作驱动成功后的正常降速。先检查卡是否完全插入、金手指与插槽、电源、线缆固定和冷启动复现，再保留完整 `tb-rtl8125-diag` 输出分析。不要通过替换 `r8125` 驱动掩盖 PCIe 物理层问题。

主线 `r8169` 已满足本项目交付要求。OpenWrt 的 `kmod-r8125-rss` 可以通过本项目 kmod 构建器作为独立实验包生成，但不安装、不提交也不纳入发布物；当前没有证据证明切换外置驱动能改善本板的实际结果，因此不增加第二套生产驱动路径。

## 网络与压力测试

当前短时性能验收使用 4 条 TCP 流，单向各 30～60 秒，双向并发 60 秒：

| 场景 | 结果 | 判读 |
|---|---:|---|
| TB-RK3399ProD → 对端 | 2.35 Gbit/s | 0 TCP 重传 |
| 对端 → TB-RK3399ProD | 2.35 Gbit/s | 0 TCP 重传 |
| 4+4 流双向并发 | 约 2.35/2.33 Gbit/s，合计约 4.68 Gbit/s | 极限接收路径有少量 RX missed/TCP 重传，未出现链路或 PCIe 错误 |
| UDP 单向 | 约 2.31 Gbit/s | 接收损失约 0.01% |
| UDP 反向 | 约 2.30 Gbit/s | 调整 socket buffer 后接收损失约 0.036% |

TCP 测试端一侧使用 iperf3 3.20，Linux x86_64 对端使用 iperf3 3.12。两者完成了控制协商和全部数据测试；对端 3.12 仍是单线程实现，因此后续正式基准建议统一版本。完整测试结束后出现的 `Size of data read does not correspond to offered length` 属于后续客户端连接被主动终止时控制 socket 未收全参数，不属于已经完成测试的数据错误。

亲和性 A/B 表明，让 IRQ、RPS 和应用负载扩散到六个核心并没有提高吞吐，反而增加 RX missed 和重传。当前结论不是“核心越多越好”，而是把主要网络路径留在两颗 Cortex-A72；正式双口策略仍是 GMAC/RTL8125 分别使用 CPU4/CPU5。测试中的临时 namespace、IP、RPS 和 affinity 修改在结束后均已撤销。

升级后复测时，先为测试接口配置不会与现网冲突的地址，然后记录测试前状态：

```sh
DEV="$(for p in /sys/class/net/*; do [ "$(cat "$p/device/vendor" 2>/dev/null)" = 0x10ec ] && [ "$(cat "$p/device/device" 2>/dev/null)" = 0x8125 ] && basename "$p"; done)"
ethtool "$DEV"
ethtool -S "$DEV" > /tmp/rtl8125-before.txt
ip -s link show dev "$DEV"
```

发布前的短测已经完成；需要量产级或具体部署场景验收时，收发各跑 30 分钟：

```sh
iperf3 -c <server-ip> -P 4 -t 1800
iperf3 -c <server-ip> -P 4 -t 1800 -R
```

随后再次保存 `ethtool -S`、`ip -s link`、`dmesg` 和 `tb-rtl8125-diag`。验收不仅看吞吐，还要求 CRC、missed、FIFO、timeout、PCIe/AER 与 carrier change 没有非预期增长。再执行至少 10 次冷启动和 10 次软重启，确认每次都稳定获得 Gen2 x1、2500/full 和相同驱动。

如果用于路由，再分别测试软件 flow offload 开/关、双向并发和实际防火墙规则。板载 GMAC 只有 1GbE，因此 RTL8125 与板载口之间的普通双口路由上限仍由 1GbE 端决定；2.5GbE 本机访问或 RTL8125 上的多 VLAN 单臂路由才具备超过 1GbE 的链路条件。

默认保留主线驱动的 checksum、scatter-gather、TSO/GSO 和 EEE 策略，不预先关闭 offload 或 EEE。只有出现可复现的协商、掉线或错误计数问题，才用 `ethtool -K` / `--set-eee` 做单变量 A/B，并把结论沉淀为板级策略。
