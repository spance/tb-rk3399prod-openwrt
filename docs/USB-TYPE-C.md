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

工程中的 `144-phy-rockchip-typec-orientation-switch.patch` 以 Rockchip 上游 v15 orientation-switch 方案为依据，只保留本板 USB 主机所需的部分。RK3399 DWC3 在切换角色时会保持 generic PHY 上电，因此回调不能只比较新旧方向：拔出时把缓存的 orientation 标记为无效；每次重新连接时，即使插头方向与上次相同，也会记录当前方向、标记一次待处理的 PHY 重初始化，并停止仍按旧方向运行的 PHY。

重置活动 PHY 时必须保持 USB3 host 路由开启。驱动的标准 `rockchip_usb3_phy_power_off()` 路径会先调用 `tcphy_cfg_usb3_to_usb2_only(tcphy, false)`，orientation 回调遵循同一约束。更重要的是，该回调不能初始化 PHY，也不能轮询 `pipe_status`：TCPM 在 orientation 回调成功返回之后才设置 USB host role，此前 DWC3 仍处于 peripheral/idle，PHY 和 PIPE 都不具备完整建链条件。实际初始化被延后到 Rockchip USB3 PHY 的标准 `.set_mode(PHY_MODE_USB_HOST)` 回调；DWC3 先创建 host core，再调用 generic PHY `set_mode`，此时驱动才按缓存方向执行 `tcphy_phy_init()`，并在 PMA ready 后验证 PIPE ready。

DTS 将连接器的方向端点连接到 `tcphy0_usb3`，将角色端点连接到 DWC3_0，并为 DWC3_0 设置 `dr_mode = "otg"` 与 `usb-role-switch`。TCPM 的事件顺序是：先设置 orientation，再设置 USB role。拔出时 orientation 回调使缓存和待处理标记失效，随后 DWC3 退出 host 并删除该控制器的 xHCI；再次插入时 orientation 回调记录方向并停止旧 PHY，然后立即返回，TCPM 切换到 host，DWC3 创建 host core 并通过 generic PHY `set_mode` 完成按方向初始化和 PIPE 验证。该生命周期完全由内核标准状态机执行，不依赖 OpenWrt 热插拔脚本或轮询服务。

`CONFIG_USB_DWC3_DUAL_ROLE` 依赖 `CONFIG_USB_GADGET`，所以后者也会编入内核；它只是 DWC3 标准角色切换实现的构建依赖。本板连接器的 `data-role = "host"`、`power-role = "source"` 未改变，不把 gadget/受电端作为受支持功能，也不添加任何 gadget function 或用户空间配置。Linux 把 DWC3 的 host-only、gadget-only 和 dual-role 定义为一个 Kconfig choice，因此目标配置还必须显式记录前两项为 `not set`；只加入 dual-role 正选项会使 `syncconfig` 将其余选项标成 `NEW` 并进入交互，破坏无人值守构建。

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

role-switch 镜像进一步实测确认状态机已接通：拔出时 Type-C xHCI 自动删除，插入时自动重建，CC 正确报告 orientation、`source`/`host`、1.5 A，VBUS regulator 保持 5 V。测试先后暴露了两个独立的软件问题：旧回调在同方向重插时会因 `flip` 未变化而跳过活动 PHY 重初始化；补上 detach 缓存失效后，回调又在 DWC3 尚未切入 host 时等待 PIPE ready，形成不可满足的时序条件。

现场对 FUSB302、DWC3 和 `tcphy0` 执行完整的驱动解绑/重绑后，同一块 Lexar E300 立即以 UAS/`5000M` 枚举；只重绑 xHCI 或 DWC3 均不能恢复。随后从 `/dev/sda` 完成 4 GiB direct read，耗时约 11.71 秒，即约 367 MB/s（350 MiB/s），全程没有新增 USB、UAS、SCSI 或 I/O 错误。这证明 CC、供电、PHY 和 SuperSpeed 物理链路均正常。

第二次修复镜像的 TCPM trace 给出了关键时序证据：`Requesting mux state` 后约 5.6 ms 即撤销 VBUS 并退回 `SRC_UNATTACHED`，表明 orientation 回调在 PIPE 轮询中失败；下一轮 attach 虽然创建 Bus 7/8，但错误路径已经物理关闭 PHY，而 DWC3 仍持有其逻辑 power reference，因此不会再次调用标准 `power_on()`，最终表现为“有 xHCI root hub、没有 USB 设备”。

第三次镜像移除了过早的 PIPE 轮询：TCPM 不再回退，单次 attach 正确进入 `host`/`source`，DWC3 也创建了 Bus 7/8；但约 3.49 秒后仍出现 `usb usb8-port1: connect-debounce failed`，设备没有以 UAS 枚举。这进一步把问题收敛为：不仅 PIPE 轮询，连 PHY 重初始化本身也不能发生在 host role 之前。单独重绑 DWC3 或先后重绑 DWC3/FUSB302 仍会复现同一过早初始化路径，不能作为正式修复。

当前工程把方向记录与物理初始化彻底分离：orientation 回调只记录、停 PHY 和返回；DWC3 创建 host core 后调用 `.set_mode(PHY_MODE_USB_HOST)`，Rockchip PHY 才重新初始化并检查 PIPE。标准 `power_on()` 若已先完成一次真正的电源循环，也会清除待处理标记，避免重复初始化。该版本仍需重新构建和刷机；完成两个方向交替热插拔、长时读写和 Loader 回归前，状态保持为“SuperSpeed 硬件已确认，自动热插拔修复待验收”。
