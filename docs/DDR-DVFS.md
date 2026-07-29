# DDR 固件与动态调频验证

## 当前阶段

TB-RK3399ProD 使用双通道 LPDDR3，当前稳定启动频率为 800 MHz。DDR 相关能力分属三层，不能把它们当成同一个固件更新：

| 层次 | 当前/本轮版本 | 职责 | 本轮动作 |
|---|---|---|---|
| loader 内 DDR bin | DDR v1.30 + miniloader v1.26 | 上电和复位后的 DDR 探测、训练与初始化 | 已独立部署并完成冷启动、内存和软复位验收 |
| 官方 `trust.img` 内 BL31 | RK3399Pro v1.35；BL32 v2.12 | EL3/PSCI，以及 Linux 时钟驱动使用的 DDR GET/ROUND/SET SMC | 官方完整组合已部署，GET/ROUND 已验证 |
| Linux 6.12 DMC/devfreq | 原先禁用 | 读取负载、选择 OPP、协调时钟与电压 | 仅启用无损 ROUND 探测，不允许 SET |

Rockchip 的 RK3399Pro 发布说明把 DDR bin v1.29 的 LPDDR3 位宽识别修复和 v1.30 的 LPDDR3 reboot 卡死修复标为重要。v1.30 有明确升级价值，但 DDR bin 不在 `trust.img` 中；它和 miniloader v1.26 通过官方 `boot_merger` 组成 loader 镜像，并写入比 GPT 分区更早的启动区域。本次部署严格隔离了三个变量：先配对升级 U-Boot/trust，再更新 OpenWrt 验证 BL31 ROUND，最后单独升级 loader 并做冷启动和软复位回归。

官方仓库没有给出 miniloader v1.26 的逐项变更说明，因此仍不能仅凭文件名把整套 loader 判定为低风险更新。本次实机 UART 已明确显示 `DDR Version 1.30 20230417` 和 `Boot1 ... version: 1.26`；启动链身份、内存拓扑和运行结果均已闭环。未来重新部署仍必须核对 [启动链构建与独立复现](EMMC-INSTALL.md#启动链构建与独立复现) 中的固定哈希，并保留 Loader/Maskrom 恢复链。

## 为什么 ROUND 探测是无损的

Linux 6.12 的 Rockchip DDR clock 实现把三个操作分别映射到 BL31 SMC：

- `clk_get_rate()` → `ROCKCHIP_SIP_CONFIG_DRAM_GET_RATE`
- `clk_round_rate()` → `ROCKCHIP_SIP_CONFIG_DRAM_ROUND_RATE`
- `clk_set_rate()` → `ROCKCHIP_SIP_CONFIG_DRAM_SET_RATE`

本工程的 `146-devfreq-rk3399-round-rate-probe-only.patch` 增加编译期开关 `CONFIG_ARM_RK3399_DMC_DEVFREQ_ROUND_PROBE_ONLY`。开关启用时，DMC 驱动取得 `dmc_clk` 后只执行 GET 和五次 ROUND，然后立即返回；不会取得或改变 regulator，不会发送 DRAM_INIT，不会注册 devfreq governor，也不会调用 `clk_set_rate()`。DTS 还显式禁用 DFI 节点，避免仅为查询 BL31 能力而启动 DDR 负载监测硬件；suspend、resume 和 remove 路径也识别 probe-only 状态。

DTS 仍使用标准 `rockchip,rk3399-dmc` binding，不增加项目私有属性。只提供当前 800 MHz / 900 mV 的单项 OPP，用来保持设备描述完整；probe-only 路径不会消费该 OPP 或改变电压。

候选频率来自 Toybrick stable 4.4 的 RK3399Pro DMC 策略：200、400、528、600 和 800 MHz。ROUND 只询问 BL31 会把请求映射到什么频率，不会实际切换。

## 上板判读

刷入匹配的新 `uboot.img`、官方 BL31 v1.35 + BL32 v2.12 `trust.img` 和本轮 OpenWrt 后执行：

```sh
dmesg | grep -E 'DDR round-rate|rk3399-dmc'
cat /sys/kernel/debug/clk/sclk_ddrc/clk_rate
```

预期首先看到当前值 `800000000`，随后每个候选值各有一条 `request=... result=...`。结果必须满足：

- 五次 ROUND 都返回正频率，没有负错误码或 0；
- 探测前后 `sclk_ddrc` 均为 800 MHz；
- 不出现 `Cannot set frequency`、SError、同步异常、DDR/PMU 超时或内存错误；
- `/sys/class/devfreq/` 下没有由本驱动创建的 DMC governor，属于预期行为；
- 冷启动、连续软复位、六核满载、eMMC/USB/网络并发运行均保持稳定。

本轮实机结果为：五个候选频率均原值返回，探测前后 `sclk_ddrc` 都是 `800000000`，没有注册 DMC devfreq governor。UART 确认双通道各 2 GiB、32-bit、双 CS；1.5 GiB 匿名内存依次完成 `00`、`ff`、`aa`、`55` 四图样全区域写入和逐块回读，约 19.8 秒全部通过；随后三次软重启均自动进入 Linux 并重复得到五组 ROUND 结果，未出现 SError、OOM、EDAC、MMC 或文件系统错误。

## 进入真实动态调频前的门槛

ROUND 通过只证明 BL31 能接受频率查询，不能证明 SET、NOC timing、ODT、调压顺序和所有 LPDDR3 颗粒都稳定。下一阶段至少需要：

前置的 DDR v1.30/miniloader v1.26 冷启动、软重启和固定 800 MHz 压力回归已经完成。进入 SET 仍至少需要：

1. 根据 ROUND 返回值建立正式 OPP 表，并逐项确认 BSP timing 支持；
2. 明确本板 DMC 的真实供电轨。Toybrick 4.4 使用固定 900 mV `vdd_log`，不能在没有原理图和测量依据时改成可调 `vdd_center`；
3. 先用固定 governor 单步切换相邻频点，验证内存压力、DMA、PCIe、GMAC、USB3 和温控；
4. 完成低频↔800 MHz 循环、冷启动和 reboot 循环，再启用 `simple_ondemand`。

在这些门槛完成前，本工程不宣称 DDR 动态调频可交付，也不会因 probe-only 模式而产生运行期节电收益。
