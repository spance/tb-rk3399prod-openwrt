# DDR 固件与动态调频验证

## 当前阶段

TB-RK3399ProD 使用双通道 LPDDR3，当前稳定启动频率为 800 MHz。DDR 相关能力分属三层，不能把它们当成同一个固件更新：

| 层次 | 当前/本轮版本 | 职责 | 本轮动作 |
|---|---|---|---|
| loader 内 DDR bin | 实机为 v1.27；构建目标为 DDR v1.30 + miniloader v1.26 | 上电和复位后的 DDR 探测、训练与初始化 | 随 U-Boot 构建生成，最后独立部署验收 |
| 官方 `trust.img` 内 BL31 | v1.30 → RK3399Pro v1.35；BL32 同步到官方 v2.12 | EL3/PSCI，以及 Linux 时钟驱动使用的 DDR GET/ROUND/SET SMC | 使用官方完整组合并验证 GET/ROUND |
| Linux 6.12 DMC/devfreq | 原先禁用 | 读取负载、选择 OPP、协调时钟与电压 | 仅启用无损 ROUND 探测，不允许 SET |

Rockchip 的 RK3399Pro 发布说明把 DDR bin v1.29 的 LPDDR3 位宽识别修复和 v1.30 的 LPDDR3 reboot 卡死修复标为重要。v1.30 有明确升级价值，但 DDR bin 不在 `trust.img` 中；它要和 miniloader v1.26 通过官方 `boot_merger` 组成 loader 镜像，并写入比 GPT 分区更早的启动区域。工程现在随 U-Boot 构建生成并校验 v1.30.126 loader，但构建集成不改变部署原则：先把匹配的新 U-Boot/trust 作为一组完成启动验收，再更新 OpenWrt 完成 BL31/ROUND 验收，最后把 loader 作为独立启动变量进行冷启动和软复位回归。

官方仓库没有给出 miniloader v1.26 的逐项变更说明，当前实机使用的 miniloader 版本也尚未从日志中可靠确认。因此不能仅凭 DDR v1.30 的修复说明把整套 loader 判定为低风险更新；部署前必须核对 [启动链构建与独立复现](EMMC-INSTALL.md#启动链构建与独立复现) 中的固定哈希，并确认 Loader/Maskrom 恢复链可用。

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

## 进入真实动态调频前的门槛

ROUND 通过只证明 BL31 能接受频率查询，不能证明 SET、NOC timing、ODT、调压顺序和所有 LPDDR3 颗粒都稳定。下一阶段至少需要：

1. 先单独部署 DDR v1.30/miniloader v1.26，完成冷启动、reboot 和固定 800 MHz 压力回归，不与首次 SET 测试合并；
2. 根据 ROUND 返回值建立正式 OPP 表，并逐项确认 BSP timing 支持；
3. 明确本板 DMC 的真实供电轨。Toybrick 4.4 使用固定 900 mV `vdd_log`，不能在没有原理图和测量依据时改成可调 `vdd_center`；
4. 先用固定 governor 单步切换相邻频点，验证内存压力、DMA、PCIe、GMAC、USB3 和温控；
5. 完成低频↔800 MHz 循环、冷启动和 reboot 循环，再启用 `simple_ondemand`。

在这些门槛完成前，本工程不宣称 DDR 动态调频可交付，也不会因 probe-only 模式而产生运行期节电收益。
