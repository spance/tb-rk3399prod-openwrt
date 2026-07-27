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

## 对原厂驱动的重新审计

当前实现不是原厂 Linux 4.4 驱动的逐行等价迁移。原厂方案由三个相互配合的部分组成：

1. 私有 FUSB302 状态机先写入方向和 SuperSpeed extcon 属性，再同步 `EXTCON_USB_HOST` 状态；
2. Rockchip 专用 `dwc3-rockchip.c` 在拔出时先移除 shared/primary HCD，再关闭 USB2/USB3 PHY 并挂起 DWC3；
3. 再次插入时先复位 OTG 控制器，Type-C PHY 在 `power_on()` 中读取已经确定的方向，只初始化当前方向的一对 USB3 lanes；PIPE ready 后才重新添加 HCD。PHY 上电失败最多重试 5 次。

因此，原厂可靠热插拔的关键不是“PHY 在线换向”，而是由 DWC3 消费者统一管理 xHCI、控制器和 PHY 的完整生命周期。此前只把 orientation-switch 接入 PHY、再尝试在常驻 xHCI 下在线重启 PHY，缺少原厂 DWC3 生命周期，不能视为等价迁移；实机出现 `-110` 和 `connect-debounce failed` 与这一差异一致。

## Linux 6.12 实现

工程现在以 Rockchip `develop-6.6` 的固定提交 `1ba51b059f25533c5529b7f68186190b47d6a7b3` 为主要依据，分别回移两部分：

- `144-phy-rockchip-typec-orientation-switch.patch`：接入 TCPM orientation switch。回调只记录 `flip` 和 `new_mode`，不写在线寄存器、不复位 PHY；实际 lane 配置仍只在 PHY `power_on()` 中完成，并恢复 Rockchip 的 5 次上电重试。
- `145-usb-dwc3-rk3399-typec-runtime-pm.patch`：让未连接的 RK3399 OTG DWC3 进入 runtime suspend，执行 `dwc3_core_exit()` 并关闭 generic PHY；连接后由 `dwc3_core_init_for_resume()` 在已知方向下重新上电，再创建 host/xHCI。autosuspend 延时为 100 ms。

DTS 中连接器仍固定声明 `data-role = "host"`、`power-role = "source"`；DWC3_0 使用 `dr_mode = "otg"` 和 `usb-role-switch`，内核启用 `CONFIG_USB_DWC3_DUAL_ROLE`。dual-role 只是复用内核的控制器生命周期状态机，并不表示产品对外提供 gadget：TCPM 在本连接器上只会请求 `HOST` 或 `NONE`。

事件顺序如下：

1. 拔出：TCPM 先发送 orientation `NONE`，再发送 USB role `NONE`；DWC3 退出 host、删除 xHCI，空闲后关闭 core 和 PHY。
2. 插入：TCPM 先发送 normal/reverse orientation，再请求 `HOST`；DWC3 runtime resume，PHY 按该方向初始化，随后创建 xHCI 并枚举设备。

这条路径不同时配置两组 USB3 lanes，不在活动 xHCI 下方重启 PHY，也不依赖用户态热插拔脚本或驱动重绑。

## 已有证据和当前状态

已经确认：

- FUSB302 在 normal/reverse 两个方向均能正确报告 CC、方向、`source`/`host` 和 5 V VBUS；
- 保持 Lexar E300 2 TB M.2 已连接再启动，可稳定以 UAS/`5000M` 枚举；
- Type-C 直读 4 GiB 约 367 MB/s（350 MiB/s），无新增 USB、UAS、SCSI 或 I/O 错误；
- 同一设备在 Type-A USB3 的对照约 319 MiB/s，证明 Type-C SuperSpeed 物理通道完整可用。

旧实验在运行中的 xHCI 下重启 PHY 时出现 `failed to reinitialize USB3 PHY for host mode: -110`，并停在 `RxDetect`；设备随冷启动则立即进入 UAS。这证明故障在软件生命周期，不是 FUSB302、VBUS、线材或 SuperSpeed 物理通道本身。

当前状态是“物理高速与冷启动 UAS 已确认；按 Rockchip DWC3/PHY 生命周期重构后的热插拔待新镜像验收”。

## 构建后静态检查

```sh
grep -E 'CONFIG_(TYPEC|TYPEC_TCPM|TYPEC_FUSB302|PHY_ROCKCHIP_TYPEC|USB_DWC3_DUAL_ROLE|USB_GADGET)=y' \
  .work/openwrt/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/linux-6.12.94/.config

.work/openwrt/staging_dir/host/bin/dtc -I dtb -O dts -o - \
  .work/openwrt/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/image-rk3399pro-toybrick-prod.dtb | \
  grep -E 'fcs,fusb302|orientation-switch|usb-role-switch|dr_mode|fe800000'
```

最终 DTB 应包含 FUSB302、orientation switch、`usb-role-switch` 和 `dr_mode = "otg"`，不应包含实验属性 `rockchip,usb3-host-only`。

## 上板验收

空载启动后检查 Type-C、角色开关和运行时电源状态：

```sh
dmesg | grep -Ei 'fusb|type-c|typec|tcpm|fe800000|dwc3|xhci'
ls -l /sys/class/typec /sys/class/usb_role
find /sys/devices/platform -path '*fe800000.usb/power/runtime_status' -exec sh -c 'printf "%s: " "$1"; cat "$1"' sh {} \;
lsusb -t
```

空载约 100 ms 后，Type-C DWC3 应为 suspended，且它的 xHCI 可以消失；插入后应恢复 active 并重新出现。独立 Type-A 的 xHCI 必须始终存在。

使用已在 Type-A 确认可达 SuperSpeed 的同一块 M.2、线材和转接器：

1. normal 方向插入，确认 UAS/`5000M`，完成至少 4 GiB direct read/write。
2. 卸载并拔出，等待 1 秒；同方向重复插入至少 5 次。
3. 翻转插头后重复，确认仍为 UAS/`5000M`。
4. 两个方向交替至少 10 次，再连续读写至少 30 分钟。
5. 基础测试通过后缩短拔插间隔，验证快速重连边界。
6. 日志不得新增 `connect-debounce failed`、PMA/PIPE timeout、xHCI、UAS、SCSI 或文件系统错误。
7. 断电进入 Loader/Maskrom，确认 Rockchip 官方工具仍能发现设备。

推荐记录：

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
- 若新内核已具备 RK3399 未连接 runtime suspend/恢复逻辑，删除 145 回移；
- 若只合入其中一部分，另一部分仍需基于当时最新的 Rockchip 代码重新移植；
- 每次升级都重新完成正反插、同方向重插、快速重插、长时 UAS 读写和 Loader 回归。

产品对外仍是 host-only；内核内部使用 dual-role 状态机是为获得正确的 detach/attach 生命周期，不能再简化为常驻 host，除非有新的硬件文档和完整实机证据证明可以安全在线换向。
