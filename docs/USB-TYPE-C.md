# USB Type-C SuperSpeed 主机设计与验收

## 目标与边界

TB-RK3399ProD 的 Type-C 插座在 BootROM/U-Boot 阶段继续承担 Rockchip Loader/Maskrom 刷机设备接口；进入 Linux 后，同一插座由 OpenWrt 初始化为固定的 USB 主机和 5 V 电源源端。两个阶段使用各自的设备树和驱动，OpenWrt 的修改不改变 BootROM、miniloader 或 U-Boot 的恢复能力。

Linux 阶段只把 USB2/USB3 主机作为产品功能，不提供充电输入或 DisplayPort Alt Mode。DWC3 内核配置使用 dual-role，是为了接入标准 `usb-role-switch` 状态机；连接器仍固定为 `source`/`host`，不会对外提供 USB gadget。验收标准是：

- C-C 或合规的 Type-C 转接连接能够枚举存储设备；
- 插头正反两个方向都能达到 `5000M`；
- 启动后热插拔和交替方向重插均能恢复；
- UAS 大文件读写期间没有 xHCI、DWC3、SCSI、UAS 或文件系统错误；
- Type-A USB3、Rockchip Loader 刷机和其他既有硬件不回归。

## 硬件链路

| 部件 | 固定参数 |
|---|---|
| Type-C 控制器 | FUSB302，I2C8 地址 `0x22` |
| FUSB302 中断 | GPIO1_A2，低电平触发，管脚上拉 |
| Type-C VBUS | GPIO0_A1，低电平使能的 5 V 固定稳压器 |
| 供电/数据角色 | Linux 固定 `source` / `host` |
| 对外声明 | 5 V、1.5 A，支持 USB 通信 |
| USB2 数据 | `u2phy0_otg` → DWC3_0 |
| USB3 数据 | `tcphy0_usb3` → DWC3_0/xHCI，5 Gbit/s |
| 控制器地址 | DWC3_0 `fe800000.usb` |
| 独立 Type-A USB3 | DWC3_1 `fe900000.usb` / `tcphy1`，不受本修改影响 |

原厂 BSP 使用私有的 `fairchild,fusb302`、GPIO 和 extcon 接口。Linux 6.12 使用主线 `fcs,fusb302`、TCPM、regulator 和 Type-C connector 描述；不能把原厂节点逐字复制到新内核。

改造前镜像的现场基线只有 `fe900000.usb` 对应的 Type-A xHCI，`/sys/class/typec` 为空，I2C8、`fe800000.usb` 和 `tcphy0` 的设备树节点均未启用。因此此前 Type-C 转接器无枚举属于软件链路未启用，不能据此判定 Type-C 物理 SuperSpeed 链路不可用。

## PHY 换向与 DWC3 生命周期

OpenWrt 25.12.5 的 Rockchip armv8 内核已经内建 `TYPEC`、`TYPEC_TCPM`、`TYPEC_FUSB302`、`USB_ROLE_SWITCH` 和 `PHY_ROCKCHIP_TYPEC`。Linux 6.12 的 RK3399 Type-C PHY 驱动却只从旧式 extcon 读取插头方向，无法接收主线 TCPM 的 orientation-switch 事件。仅打开 DTS 节点会形成“默认方向可能工作、反插或重插不可靠”的半成品。

工程中的 `144-phy-rockchip-typec-orientation-switch.patch` 以 Rockchip 上游 v15 orientation-switch 方案为依据，只保留本板 USB 主机所需的部分。RK3399 DWC3 在切换角色时会保持 generic PHY 上电，因此回调不仅保存方向，还会在方向改变时同步重置并按新方向初始化空闲的 SuperSpeed lanes。

DTS 将连接器的方向端点连接到 `tcphy0_usb3`，将角色端点连接到 DWC3_0，并为 DWC3_0 设置 `dr_mode = "otg"` 与 `usb-role-switch`。TCPM 的事件顺序是：先设置 orientation，再设置 USB role。拔出时 DWC3 退出 host 并删除该控制器的 xHCI；再次插入时先完成 PHY 换向，再切换到 host 并创建新的 xHCI。这个生命周期与实机上有效的 DWC3 手工解绑/重绑一致，但由内核状态机自动执行，不依赖 OpenWrt 热插拔脚本。

`CONFIG_USB_DWC3_DUAL_ROLE` 依赖 `CONFIG_USB_GADGET`，所以后者也会编入内核；它只是 DWC3 标准角色切换实现的构建依赖。本板连接器的 `data-role = "host"`、`power-role = "source"` 未改变，不把 gadget/受电端作为受支持功能，也不添加任何 gadget function 或用户空间配置。

该补丁属于 Linux 6.12 的板级回移，不应在升级内核时机械沿用。升级流程必须先检查新内核的 `phy-rockchip-typec.c` 是否已经原生支持 `orientation-switch`，若已支持则删除补丁并按新绑定调整 DTS；若仍未支持，则重新审查上游最新版本并完成正反插回归。

## 构建后静态检查

```sh
grep -E 'CONFIG_(TYPEC|TYPEC_TCPM|TYPEC_FUSB302|PHY_ROCKCHIP_TYPEC|USB_ROLE_SWITCH|USB_DWC3|USB_DWC3_DUAL_ROLE|USB_GADGET)=y' \
  .work/openwrt/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/linux-6.12.94/.config

.work/openwrt/staging_dir/host/bin/dtc -I dtb -O dts -o - \
  .work/openwrt/build_dir/target-aarch64_generic_musl/linux-rockchip_armv8/image-rk3399pro-toybrick-prod.dtb | \
  grep -E 'fcs,fusb302|orientation-switch|usb-role-switch|fe800000'
```

第二条使用 OpenWrt 构建出的 host `dtc` 反编译最终 DTB，避免直接对二进制文件执行文本搜索。

## 上板验收

先在 Type-C 口不接设备的情况下启动，再执行：

```sh
dmesg | grep -Ei 'fusb|type-c|typec|tcpm|fe800000|dwc3|xhci'
ls -l /sys/class/typec
lsusb -t
```

预期能看到 FUSB302/TCPM 的 Type-C port 和 DWC3 role switch，并且没有 probe defer、I2C、regulator 或 PHY timeout。空载时 `fe800000.usb` 的 host/xHCI 可以不存在；插入 host 外设后才创建，拔出后应删除。`fe900000.usb` 的 Type-A xHCI 始终存在且不应受影响。

随后使用已经在蓝色 Type-A 口确认能跑 SuperSpeed 的同一套移动硬盘、线材和转接器作 A/B 测试：

1. 正向插入，确认 `lsusb -t` 为 `5000M`，完成至少 4 GiB 直接读写并检查 `dmesg`。
2. 卸载并拔出，翻转 Type-C 插头后重复相同测试。
3. 两个方向交替热插拔至少 10 次，每次确认设备节点能够消失并重新出现。
4. 连续读写至少 30 分钟，再检查内核日志和存储错误计数。
5. 断电进入 Loader/Maskrom，确认 Rockchip 官方工具仍能发现设备。

推荐记录：

```sh
lsusb -t
cat /sys/class/typec/port0/orientation 2>/dev/null
cat /sys/class/typec/port0/data_role 2>/dev/null
cat /sys/class/typec/port0/power_role 2>/dev/null
find /sys/class/usb_role -maxdepth 2 -type f -name role -exec sh -c 'printf "%s: " "$1"; cat "$1"' sh {} \; 2>/dev/null
dmesg | grep -Ei 'error|fail|timeout|reset|uas|scsi|xhci|dwc3|fusb|tcpm'
```

## 当前实机结论

第一版 host-only 镜像已经确认 FUSB302 在正反两个方向都能正确报告 CC、orientation、`source`/`host` 和 5 V VBUS，但运行中的 xHCI 不会在 PHY 换向后自行恢复链路。只对 Type-C DWC3_0 执行一次驱动解绑/重绑后，同一块 Lexar E300 2 TB 移动硬盘立即以 UAS/`5000M` 枚举，4 GiB direct read 约 349 MiB/s；相同设备在蓝色 Type-A 的同条件基线约 319 MiB/s，测试后没有新增 USB、UAS 或 SCSI 错误。这已经确认 C 口的 CC、VBUS、PHY 和 SuperSpeed 物理数据通道可用，也直接验证了“重建 xHCI”这一修复方向。

当前工程已改为内核原生 role-switch 生命周期，但该版本尚待重新构建和刷机。完成两个方向交替热插拔、长时读写和 Loader 回归前，状态保持为“SuperSpeed 硬件已确认，自动热插拔修复待验收”。
