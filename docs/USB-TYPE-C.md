# USB Type-C SuperSpeed 主机设计与验收

## 产品边界

TB-RK3399ProD 的 Type-C 插座在 BootROM/U-Boot 阶段继续作为 Rockchip Loader/Maskrom 刷机接口；进入 Linux 后，只作为 5 V 电源源端和 USB 主机使用。OpenWrt 不提供 Type-C 充电输入、USB gadget 或 DisplayPort Alt Mode，也不改变 BootROM、miniloader 和 U-Boot 的恢复能力。

Linux 侧的验收目标是：

- FUSB302/TCPM 在正反插时均报告 `source`/`host` 和正确方向；
- USB2、USB3 均可热插拔，SuperSpeed 存储显示 UAS/`5000M`；
- 两个方向都能完成重复枚举和长时间读写；
- Type-A USB3 与 Loader/Maskrom 功能不回归。

## 硬件链路

| 部件 | 固定参数 |
|---|---|
| Type-C 控制器 | FUSB302，I2C8 地址 `0x22` |
| FUSB302 中断 | GPIO1_A2，低电平触发、上拉 |
| Type-C VBUS | GPIO0_A1，低电平使能的 5 V 固定稳压器 |
| 对外角色 | `source` / `host`，5 V / 1.5 A |
| USB2 数据 | `u2phy0_otg` → DWC3_0 |
| USB3 数据 | `tcphy0_usb3` → DWC3_0/xHCI，5 Gbit/s |
| DWC3 地址 | `fe800000.usb` |
| 独立 Type-A USB3 | DWC3_1 `fe900000.usb` / `tcphy1`，不受本方案影响 |

原厂 BSP 使用私有 `fairchild,fusb302`、GPIO 与 extcon 接口。Linux 6.12 使用主线 `fcs,fusb302`、TCPM、regulator、Type-C connector 和 `usb-role-switch`，设备树不能逐字照搬。

## 依据优先级

本板的官方支持基线是 Toybrick `stable` 分支 Linux 4.4，固定参考提交为 `a80be5749ac552821967eff313df53f9e0cd1e01`。板级连线、FUSB302 事件顺序、DWC3/xHCI/PHY 生命周期及复位先后关系均以该实现为行为规范。

Linux 6.12 是 OpenWrt 25.12.5 的目标内核，用来选择当前的 TCPM、role-switch、runtime PM、generic PHY 和 reset API；Rockchip `develop-6.6` 及后续补丁只用于核对如何用较新 API 表达相同行为，不能作为 TB-RK3399ProD 已获 6.x 官方支持的依据。若三者有差异，优先保持 4.4 的板级时序，再以 6.12 API 实现，最后由实机回归确认。

## 对原厂驱动的重新审计

当前实现不是原厂 Linux 4.4 驱动的逐行等价迁移。原厂方案由三个相互配合的部分组成：

1. 私有 FUSB302 状态机先写入方向和 SuperSpeed extcon 属性，再同步 `EXTCON_USB_HOST` 状态；
2. Rockchip 专用 `dwc3-rockchip.c` 在整段线缆连接期间持续持有父 glue 与子 DWC3 的 runtime-PM 引用；拔出时先移除 shared/primary HCD，再关闭 USB2/USB3 PHY，最后同步挂起子控制器和父 glue；
3. 再次插入时先复位 OTG 控制器，Type-C PHY 在 `power_on()` 中读取已经确定的方向，只初始化当前方向的一对 USB3 lanes；PIPE ready 后才重新添加 HCD。PHY 上电失败最多重试 5 次。

因此，原厂可靠热插拔的关键不是“PHY 在线换向”，而是由 DWC3 消费者统一管理 xHCI、控制器和 PHY 的完整生命周期。此前只把 orientation-switch 接入 PHY、再尝试在常驻 xHCI 下在线重启 PHY，缺少原厂 DWC3 生命周期，不能视为等价迁移；实机出现 `-110` 和 `connect-debounce failed` 与这一差异一致。

## Linux 6.12 实现

工程以 Toybrick stable 4.4 的板级行为为目标，用 Linux 6.12 的现有框架实现；Rockchip `develop-6.6` 的固定提交 `1ba51b059f25533c5529b7f68186190b47d6a7b3` 仅作为新 API 写法的交叉参考。适配由两部分组成：

- `patches/kernel/144-phy-rockchip-typec-orientation-switch.patch`：接入 TCPM orientation switch。带 orientation switch 的 PHY 初始状态明确为 `DISCONNECT`；回调只记录 `flip` 和 `new_mode`，不写在线寄存器、不复位 PHY。实际 lane 配置仍只在 PHY `power_on()` 中完成，恢复 Rockchip 的 5 次上电重试，并记录复位、PMA ready、PIPE ready、方向、尝试次数和原始状态值。PHY 关闭时的 GRF 恢复错误会完整记录，但不向 generic PHY 返回失败，避免其 `power_count` 和 runtime-PM 引用无法归零。
- `patches/kernel/145-usb-dwc3-rk3399-typec-runtime-pm.patch`：只对同时具有 RK3399 DWC3、OTG 模式和标准 `usb-role-switch` 属性的控制器启用本生命周期。在本控制器上把 `USB_ROLE_NONE` 表示成真正的内部 idle，而不是 Linux 6.12 原有的默认 device；连接成功后持续持有 runtime-PM 引用，拔出时先删除 xHCI，再释放连接期引用并同步挂起。这样父 glue 的 `usb3-otg` 复位脉冲只发生于真正的 `NONE → HOST`，不会发生在 `HOST → NONE` 或普通总线唤醒途中。attach 时父 glue 执行 `assert → 1 µs → deassert`，子 DWC3 再恢复 core/PHY，等待 10–11 ms 后创建 xHCI。若一次恢复最终失败，父子回调已经回滚到 suspended 硬件状态后会重置 runtime-PM 错误状态，使下一次 TCPM 事件仍能重试，而不是永久返回 `-EINVAL` 直到重启。100 ms autosuspend 仅作为空闲路径的安全边界；活动连接不依赖该定时器。

这两份关键驱动补丁是工程中的直接权威文件。`make init` 根据 OpenWrt 的 `KERNEL_PATCHVER` 把它们同步到 `target/linux/rockchip/patches-<版本>/`；OpenWrt 板级补丁不再嵌套保存第二份副本。

DTS 中连接器仍固定声明 `data-role = "host"`、`power-role = "source"`；DWC3_0 使用 `dr_mode = "otg"` 和 `usb-role-switch`，内核启用 `CONFIG_USB_DWC3_DUAL_ROLE`。dual-role 只是复用内核的控制器生命周期状态机，并不表示产品对外提供 gadget：TCPM 在本连接器上只会请求 `HOST` 或 `NONE`。

事件顺序如下：

1. 拔出：TCPM 先发送 orientation `NONE`，再发送 USB role `NONE`；DWC3 在仍处于供电状态时退出 host、删除 xHCI，然后释放连接期 PM 引用并同步关闭 core、PHY 和父 glue。该方向不触发 OTG 复位。
2. 插入：TCPM 先发送 normal/reverse orientation，再请求 `HOST`；从真实 idle 恢复父 DWC3 glue 时先脉冲 `usb3-otg` 复位，子 DWC3 随后 runtime resume，PHY 按已经记录的方向初始化；等待 10–11 ms 后创建 xHCI，并在整段连接期间保持 PM active。

这条路径不同时配置两组 USB3 lanes，不在活动 xHCI 下方重启 PHY，也不依赖用户态热插拔脚本或驱动重绑。

## 验收证据与结论

当前实现已经确认：

- FUSB302 在 normal/reverse 两个方向均正确报告 CC、方向、`source`/`host` 和 5 V VBUS；
- 空载时 Type-C DWC3/xHCI 关闭，连接后恢复；detach 按 xHCI → child core/PHY → parent glue 的顺序关闭，PM usage 最终回到 0；
- 首次插入、同方向拔插和翻转后重插均在一次 PHY 尝试内恢复，Lexar E300 2 TB M.2 以 UAS/`5000M` 枚举；
- exFAT 分区完成 8 GiB `O_DIRECT` 写入并 `fsync`，约 300～320 MiB/s；8 GiB `O_DIRECT` 读取约 340 MiB/s；完整 8 GiB 数据比较通过；
- 测试窗口没有出现 `connect-debounce failed`、PMA/PIPE timeout、PHY `-110`、xHCI reset、UAS、SCSI、I/O 或 exFAT 错误；既有 SCSI `ioerr_cnt` 在追加读取前后保持不变；
- 同一设备在蓝色 Type-A USB3 约为 340～360 MB/s，两个接口均落在这套 RK3399 USB 3.0、硬盘盒和存储组合的正常高速区间；
- 本版镜像通过 Type-C Loader 路径完成刷写，说明 Linux 侧修改没有破坏 Rockchip 刷机入口。

早期实验曾在运行中的常驻 xHCI 下直接重启 PHY，出现 `failed to reinitialize USB3 PHY for host mode: -110` 并停在 `RxDetect`；设备随冷启动则立即进入 UAS。这一对照把故障定位到软件生命周期，而不是 FUSB302、VBUS、线材或 SuperSpeed 物理通道，也构成当前设计不允许在线重启 PHY 的原因。

因此当前 Type-C 功能已经达到板级工程交付条件。量产前的剩余工作是耐久性扩展，而不是功能阻断：建议执行 20～50 次方向交替/快速重插，以及至少 1～4 小时或 100 GiB 连续 I/O。

## 构建后静态检查

```sh
grep -E 'CONFIG_(DEBUG_FS|TYPEC|TYPEC_TCPM|TYPEC_FUSB302|PHY_ROCKCHIP_TYPEC|USB_DWC3_DUAL_ROLE|USB_GADGET)=y' \
  .work/openwrt/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/linux-6.12.94/.config

.work/openwrt/staging_dir/host/bin/dtc -I dtb -O dts -o - \
  .work/openwrt/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/image-rk3399pro-toybrick-prod.dtb | \
  grep -E 'fcs,fusb302|orientation-switch|usb-role-switch|dr_mode|fe800000'
```

最终 DTB 应包含 FUSB302、orientation switch、`usb-role-switch` 和 `dr_mode = "otg"`，不应包含实验属性 `rockchip,usb3-host-only`。

## 一次性诊断采集

固件内置 `/usr/sbin/tb-typec-diag`。它在一个时间窗内只记录发生变化的 Type-C role、orientation、DWC3 runtime-PM 和 USB 设备状态，结束时收集完整 `dmesg`、`logread`、USB/块设备拓扑、IRQ、相关 clock/power-domain/regulator/GPIO、驱动绑定和 deferred probe，以及 Linux 已有的 FUSB302 与 TCPM 1024 项事件环。脚本会把开始/结束标记写入内核日志，使测试窗口在完整 `dmesg` 中有明确边界。

读取 FUSB302/TCPM debugfs 事件环会推进其 tail。脚本在测试开始时先把开机阶段的现存事件保存到输出文件并释放环容量，结束时再读取测试期间的新事件；两段内容都保存在同一文件中，不会因为下一阶段采集而丢失，同时降低 1024 项环在多次插拔中溢出的概率。若 debugfs、事件环或关键驱动绑定不存在，脚本会明确记录“未找到”，而不是静默跳过。

默认一次 120 秒即可覆盖两个方向：

```sh
tb-typec-diag
# 正向插入并等待枚举；卸载、拔出、翻转，再次插入并等待枚举
# 完成后把脚本打印的 /tmp/tb-typec-diag-*.log 取回分析
```

也可指定时间和输出文件：

```sh
tb-typec-diag 180 /tmp/typec-run.log
```

若未来内核升级后出现“带盘冷启动成功、运行中重插失败”，最有效的一次采集方式是：先保持已知可用的 M.2 连接并启动，进入系统后执行 `tb-typec-diag 240`，确认冷启动枚举仍在，然后卸载并拔出，依次完成同向重插、翻转重插。这样一份文件同时包含成功链和回归链，可直接做边界对比，不需要针对每个猜测重新刷机。

驱动的事件日志覆盖以下关键边界：

- TCPM/FUSB302：CC、attach/detach、请求的 USB role 和 orientation；
- DWC3 父 glue：OTG reset 的 assert/deassert 失败、复位脉冲完成、clock resume/suspend；
- Type-C PHY：方向、reset、PMA ready、PIPE ready、GRF 写入错误、PIPE regmap 读取错误、5 次重试及原始状态值；
- DWC3 子控制器：当前/目标 role、xHCI 创建或移除、同步 suspend 结果；
- runtime PM：关键转换同时记录 usage count、连接期 hold 状态和最终 suspended 状态，可直接发现引用泄漏；
- 用户态快照：Type-C/USB role、父子 runtime status、USB speed/UAS、块设备、clock、power domain、regulator、GPIO 和驱动绑定。

同一份日志可以按下面的连续边界定位故障：

| 最后成功边界 | 首个缺失/错误边界 | 主要定位 |
|---|---|---|
| FUSB302 CC/TCPM attached | 无 orientation/role 事件 | FUSB302、I2C/IRQ、TCPM 或 graph 绑定 |
| `orientation=normal/reverse` | 无 `role transition ... desired=1` | USB role switch |
| role transition | 父 reset/clock resume 失败 | DWC3 glue、reset、clock 或 power domain |
| 父 resume | child core/PMA/PIPE 失败 | DWC3 core 或 Type-C PHY，并有 reset、GRF/regmap 返回码、原始状态值和 5 次重试记录 |
| PHY on | 无 `host active, xHCI created` | DWC3 host/xHCI 创建 |
| xHCI created | 无 USB/UAS 设备 | xHCI 端口、线缆、设备或 USB 枚举 |
| 拔出 role NONE | 无同步 child/parent suspend | PM 引用或退出路径泄漏 |

正常 attach 的关键日志顺序应为：父 reset pulse → 父 clocks on → PHY ready → child core resume → role transition → xHCI created；正常 detach 应为：orientation none → role NONE → xHCI removed → child core/PHY off → parent clocks off。成功 attach 后 PM usage count 应保留一个连接期引用；detach 完成后应回到 `pm_usage=0 suspended=1`。时间戳、事件环和 PM 计数足以判断顺序与引用平衡，不需要为每一个猜测重新编译固件。

## 回归与耐久验收

空载启动后检查 Type-C、角色开关和运行时电源状态：

```sh
dmesg | grep -Ei 'fusb|type-c|typec|tcpm|fe800000|dwc3|xhci'
ls -l /sys/class/typec /sys/class/usb_role
find /sys/devices/platform -path '*fe800000.usb/power/runtime_status' -exec sh -c 'printf "%s: " "$1"; cat "$1"' sh {} \;
lsusb -t
```

空载约 100 ms 后，Type-C DWC3 应为 suspended，且它的 xHCI 可以消失；插入后应恢复 active 并重新出现。独立 Type-A 的 xHCI 必须始终存在。

每次升级内核、DTS 或 Type-C 补丁后，使用已在 Type-A 确认可达 SuperSpeed 的同一块 M.2、线材和转接器。步骤 1～3 和一次 8 GiB 完整校验已在当前版本通过；步骤 4～5 是量产前建议追加的耐久边界：

1. normal 方向插入，确认 UAS/`5000M`，完成至少 4 GiB direct read/write。
2. 卸载并拔出，等待 1 秒；同方向重新插入并确认 UAS/`5000M`。
3. 再次卸载、拔出并翻转插头，确认仍为 UAS/`5000M`。
4. 量产前把两个方向交替扩展到 20～50 次，并连续读写至少 1～4 小时或 100 GiB。
5. 基础测试通过后缩短拔插间隔，验证快速重连边界。
6. 日志不得新增 `connect-debounce failed`、PMA/PIPE timeout、xHCI、UAS、SCSI 或文件系统错误。
7. 断电进入 Loader/Maskrom，确认 Rockchip 官方工具仍能发现设备。

快速人工查看仍可使用：

```sh
lsusb -t
cat /sys/class/typec/port0/orientation
cat /sys/class/typec/port0/data_role
cat /sys/class/typec/port0/power_role
dmesg | grep -Ei 'error|fail|timeout|uas|scsi|xhci|dwc3|fusb|tcpm'
```

## 内核升级注意事项

升级内核时必须同时审查 Type-C PHY 和 DWC3 两部分：

- 若新内核已合入 RK3399 TCPM orientation-switch，删除 144 回移并使用上游绑定；
- 若新内核已具备 RK3399 未连接 runtime suspend/恢复逻辑，必须同时确认：`NONE` 不回落到 gadget、xHCI 先于 suspend 删除、连接期间 PM 引用保持、父 `usb3-otg` 只在 attach 时复位且早于 PHY 上电；全部满足后才删除 145 回移；
- 若只合入其中一部分，另一部分仍以 Toybrick stable 4.4 的板级行为为目标，按新内核 API 重新实现；Rockchip 新分支只作实现参考；
- 每次升级都重新完成正反插、同方向重插、快速重插、长时 UAS 读写和 Loader 回归。

产品对外仍是 host-only；内核内部使用 dual-role 状态机是为获得正确的 detach/attach 生命周期，不能再简化为常驻 host，除非有新的硬件文档和完整实机证据证明可以安全在线换向。
