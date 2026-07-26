# USB Type-C SuperSpeed 主机设计与验收

## 产品边界

TB-RK3399ProD 的 Type-C 插座在 BootROM/U-Boot 阶段继续作为 Rockchip Loader/Maskrom 刷机接口；进入 Linux 后，同一插座只作为 USB 主机和 5 V 电源源端使用。OpenWrt 不提供 Type-C 充电输入、USB gadget 或 DisplayPort Alt Mode，也不改变 BootROM、miniloader 和 U-Boot 的刷机能力。

Linux 侧目标如下：

- FUSB302/TCPM 正确识别正反插，角色固定为 `source`/`host`；
- USB2 和 USB3 均可热插拔，SuperSpeed 设备显示 `5000M`；
- UAS 存储可在两个方向枚举并完成长时间读写；
- Type-A USB3、Loader 刷机和其他板载硬件不回归。

## 硬件链路

| 部件 | 固定参数 |
|---|---|
| Type-C 控制器 | FUSB302，I2C8 地址 `0x22` |
| FUSB302 中断 | GPIO1_A2，低电平触发、上拉 |
| Type-C VBUS | GPIO0_A1，低电平使能的 5 V 固定稳压器 |
| Linux 角色 | `source` / `host`，对外声明 5 V、1.5 A |
| USB2 数据 | `u2phy0_otg` → DWC3_0 |
| USB3 数据 | `tcphy0_usb3` → DWC3_0/xHCI，5 Gbit/s |
| DWC3 地址 | `fe800000.usb` |
| 独立 Type-A USB3 | DWC3_1 `fe900000.usb` / `tcphy1`，不受本设计影响 |

原厂 BSP 使用私有 `fairchild,fusb302`、GPIO 和 extcon 接口。Linux 6.12 使用主线 `fcs,fusb302`、TCPM、regulator 与 Type-C connector 绑定，不能逐字移植旧节点。

## 最终软件架构

连接器在产品定义中始终是主机，因此 DWC3_0 使用 `dr_mode = "host"`，内核使用 `CONFIG_USB_DWC3_HOST=y`。FUSB302 仍负责 CC、方向检测和 VBUS，但 DTS 不再建立 DWC3 `usb-role-switch` 端点。这样空载、拔出和重新插入期间 xHCI 始终存在，行为与固定 Type-A 主机端口一致。

这一选择解决了一个不必要的状态机错配：旧实现虽然把连接器声明为 `data-role = "host"`，却把 DWC3 配置成 dual-role；`USB_ROLE_NONE` 又默认映射为 peripheral。每次拔出都会删除 xHCI，每次插入都会在 M.2 桥刚上电时重新创建 xHCI。实机已证明这条动态 device→host 路径会留下 USB 核心与 xHCI 端口状态不一致，而不是产品真正需要的功能。

Linux 6.12 的 RK3399 Type-C PHY 尚不能直接消费主线 TCPM orientation-switch 事件。`144-phy-rockchip-typec-orientation-switch.patch` 以 Rockchip 上游 v15 方案为基础，增加方向开关，并按固定主机语义处理 PHY：

- 初次启动时，方向事件先被记录；DWC3 选择 host mode 后，若方向与当前 PHY 映射不同，则在 xHCI 注册前重建 PHY；
- 拔出时只使 attachment 缓存失效，不销毁 xHCI，也不重置仍可复用的 PHY；
- 同方向重新插入保持现有 PHY/xHCI，避免无意义的控制器生命周期切换；
- 插头方向真正改变时，仅重建方向相关的 Type-C PHY lane mapping，并检查 PIPE ready；
- `usb3_powered` 与 `host_ready` 防止在 generic PHY 未上电或 DWC3 尚未进入 host 时执行热重配。

静态 host 初始化在 Linux 6.12 中本来就是 `phy_set_mode(PHY_MODE_USB_HOST)` 后再 `dwc3_host_init()`，因此不再需要修改 DWC3 动态角色路径，旧的 `145-usb-dwc3-set-host-phy-mode-before-xhci.patch` 已删除。整个方案不依赖用户态热插拔脚本、驱动重绑或固定延时。

## 实机证据与故障收敛

已经确认的硬件能力：

- FUSB302 在 normal/reverse 两个方向均正确报告 orientation、`source`/`host` 和 5 V VBUS；
- 保持 Lexar E300 2 TB M.2 已连接再启动时，可稳定以 UAS/`5000M` 枚举；
- Type-C 直读 4 GiB 约 367 MB/s（350 MiB/s），测试后无新增 USB、UAS、SCSI 或 I/O 错误；
- 同一设备在 Type-A USB3 的对照结果约 319 MiB/s，证明 Type-C SuperSpeed 物理通道完整可用。

前六轮动态 role-switch 实验依次排除了方向映射、VBUS、UAS、线材、PIPE 检查先后以及“detach 后未完整复位 PHY”等假设。最近一版在拔出后明确输出 `USB3 PHY held in reset after detach`，PHY 保持 reset 约 10 秒；重插时 PHY 在 xHCI 前恢复并输出 ready，但仍出现 `connect-debounce failed`。冷启动则在相同硬件上立即进入 UAS。

失败后的关键寄存器状态是：USB3 PORTSC 报告 `Powered Connected Enabled Link:U0 PortSpeed:4 Change:CSC`，而 USB hub 层没有子设备并显示 `not attached`。标准 port disable/enable、USB3 root-hub 重绑，以及 DWC3 glue/FUSB302 完整重探测均未可靠恢复。该证据说明 SuperSpeed PHY 已完成链路训练，问题位于动态销毁/重建 xHCI 的控制路径。最终架构因此取消这条非必要路径，让固定 host 的 xHCI 常驻。

当前代码状态是“SuperSpeed 硬件与冷启动 UAS 已确认；固定 host 热插拔方案待新镜像验收”。在完成下列回归前，不把 Type-C 自动热插拔标记为最终通过。

## 构建后静态检查

```sh
grep -E 'CONFIG_(TYPEC|TYPEC_TCPM|TYPEC_FUSB302|PHY_ROCKCHIP_TYPEC|USB_DWC3_HOST)=y' \
  .work/openwrt/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/linux-6.12.94/.config

.work/openwrt/staging_dir/host/bin/dtc -I dtb -O dts -o - \
  .work/openwrt/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/image-rk3399pro-toybrick-prod.dtb | \
  grep -E 'fcs,fusb302|orientation-switch|dr_mode|fe800000'
```

最终 DTB 应包含 FUSB302、orientation switch 和 `dr_mode = "host"`，不应包含该连接器的 `usb-role-switch`。

## 上板验收

空载启动后先确认两个 xHCI 始终存在：

```sh
dmesg | grep -Ei 'fusb|type-c|typec|tcpm|fe800000|dwc3|xhci'
ls -l /sys/class/typec
lsusb -t
```

随后使用已经在 Type-A 口确认可达 SuperSpeed 的同一块 M.2、线材和转接器：

1. normal 方向插入，确认 UAS/`5000M`，完成至少 4 GiB direct read/write。
2. 卸载并拔出；同方向重复插入至少 5 次，每次都必须重新出现块设备，Type-C xHCI 根总线编号不应改变。
3. 翻转插头后重复测试，确认日志中出现方向变化后的 PHY ready，且仍为 UAS/`5000M`。
4. 两个方向交替热插拔至少 10 次，再连续读写至少 30 分钟。
5. 检查日志中没有 `connect-debounce failed`、PMA/PIPE timeout、xHCI、UAS、SCSI 或文件系统错误。
6. 断电进入 Loader/Maskrom，确认 Rockchip 官方工具仍能发现设备。

推荐记录：

```sh
lsusb -t
cat /sys/class/typec/port0/orientation
cat /sys/class/typec/port0/data_role
cat /sys/class/typec/port0/power_role
dmesg | grep -Ei 'error|fail|timeout|uas|scsi|xhci|dwc3|fusb|tcpm'
```

## 内核升级注意事项

此补丁是 Linux 6.12 的板级回移。升级内核时先检查 `phy-rockchip-typec.c` 是否已合入 TCPM orientation-switch 支持：若已合入，应删除回移并按新绑定调整 DTS；若尚未合入，则以当时最新的 Rockchip 上游版本重新审查。无论驱动来源如何，产品边界仍是 Linux host-only，升级后必须重新完成正反插、同方向重插、长时 UAS 读写和 Loader 回归。
