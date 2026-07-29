# 启动链与 `trust.img`

## 当前启动模型

本工程继续使用 Toybrick/Rockchip 厂商 miniloader 启动链：

```text
RK3399 BootROM
  -> Rockchip miniloader + DDR bin
  -> trust.img：BL31，随后进入 BL32
  -> uboot.img：BL33 / U-Boot
  -> boot_linux：OpenWrt FIT（Linux + DTB）
  -> rootfs：SquashFS + ext4 overlay
```

DDR bin 负责最早期 DRAM 探测、训练和初始化；BL31 提供 EL3、PSCI 和 DDR 调频 SMC；BL32 是 Rockchip OP-TEE 安全世界；BL33 由独立 `uboot.img` 提供。普通 Linux 外设仍由 U-Boot、Linux 驱动和 DTS 初始化，因此 `trust.img` 不是“普通设备初始化包”，也不包含 DDR bin 或 U-Boot。

Rockchip 同时支持 SPL + `u-boot.itb` 模型，但本工程没有切换启动链。只要继续使用 miniloader，就必须保留独立 `trust` 和 `uboot` 区域。

## 直接使用 Rockchip 官方固件

Rockchip `rkbin` 的当前固定基线 `ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4` 没有提交合并后的 RK3399Pro `trust.img` 或 loader，GitHub 当前也没有 Release/Tag 成品；仓库提供的是已编译固件、标准 INI 和官方 merger。该基线的标准组合是：

| 官方产物 | 标准输入 | 地址/职责 |
|---|---|---|
| `trust.img` | BL31 v1.35 + BL32/OP-TEE v2.12 | BL31 `0x00040000`，BL32 `0x08400000` |
| `rk3399pro_loader_v1.30.126.bin` | DDR 800 MHz v1.30 + miniloader v1.26 | BootROM 后的 DRAM 初始化与一级 loader |
| `uboot.img` | 不属于上述两个 merger 的输入 | 本工程继续构建带板级补丁的 BL33 |

这些输入和封装规则都没有经过本工程修改。Rockchip vendor U-Boot 固定到 `aeec6f2bfd5ce0cfcdfe0ffc7f84d9d143683856`，其 `./make.sh rk3399pro` 会依次生成 `uboot.img`、loader 和 `trust.img`。工程显式传入固定 AArch64 交叉编译器、固定相邻 rkbin，并通过板级 defconfig 指定 `RK3399PROMINIALL.ini` 与 `RK3399PROTRUST.ini`，避免脚本把 RK3399Pro 错化简为普通 RK3399。

因此 `make uboot`/`make all` 会把三项启动链产物一起写入 `out/uboot/`，并校验 trust 的文件名、大小和整文件 SHA256，以及 loader 的文件名、大小和解包载荷 SHA256。若只需脱离 U-Boot 独立复现官方封装，仍可在固定 rkbin 根目录直接执行：

```sh
./tools/trust_merger RKTRUST/RK3399PROTRUST.ini
./tools/boot_merger RKBOOT/RK3399PROMINIALL.ini
```

`trust_merger`/`boot_merger` 只负责官方二进制的格式封装，不编译 BL31、OP-TEE、DDR 初始化代码或 miniloader。Rockchip 对这一代平台主要发布二进制；只有未来确实修改可信固件源码或镜像格式时，才有理由在本工程建立相应构建链。

官方发布说明没有列出 BL31 v1.30 到 v1.35 的逐项变化，所以不能预先宣称性能或功耗提升。静态 ELF 对比显示两个版本的三个 `PT_LOAD` 物理地址均为 `0x00040000`、`0xff8c0000` 和 `0xff8c2000`，新版没有扩大现有保留区。BL32 v2.12 会检查 normal world 客户端的 OP-TEE 消息接口；实机已证明旧 Toybrick U-Boot 会因接口版本过低而 panic。因此正式构建改用含 API revision 2.0 客户端的新 Rockchip U-Boot，且部署时必须把 U-Boot 与 trust 当成配对，不能只更新其中一个。

## DDR bin 不属于 `trust.img`

当前实机 UART 已确认 `DDR Version 1.30 20230417` 和 miniloader `version: 1.26`。双通道 LPDDR3 均识别为 2 GiB、32-bit、双 CS，合计 4 GiB，保持 800 MHz。Rockchip 发布说明中 v1.29 的 LPDDR3 位宽识别修复和 v1.30 的 LPDDR3 reboot 卡死修复因此已进入正式启动链，而不再只是构建目标。

DDR bin 要和 `rk3399pro_miniloader_v1.26.bin` 通过官方 `boot_merger` 生成 loader，并写入早于 GPT 分区的启动区域；不能把 DDR bin 放进 `trust.img`，也不能把 loader 写到 `trust@0x4000`。构建时可以一次生成全部启动固件，部署时仍应分批验证：loader/DDR 更新失败会早于 U-Boot 和 Linux，恢复风险高于 trust 更新。细节见 [DDR 固件与动态调频验证](DDR-DVFS.md)。

## 部署策略

- `make uboot`/`make all` 生成 `uboot.img`、`rk3399pro_loader_v1.30.126.bin` 和 `trust.img`；`make all` 另外生成 `openwrt.img`。
- `uboot.img` 与 BL31 v1.35/BL32 v2.12 `trust.img` 是一次性配对升级。必须先具备可工作的 Loader/Maskrom 恢复路径、UART 和已知可恢复镜像，再在同一刷机会话分别写到 `uboot@0x2000` 与 `trust@0x4000`；两项完成前不得复位或上电启动。
- 日常 OpenWrt 更新只写 `boot_linux.img` 或 `openwrt.img`，不应反复重写 `trust`。
- `openwrt.img` 永远只能从 `0x6000` 写入，不能写到 `trust`；`trust.img` 也不能写到 `boot_linux`。
- 首次升级分三阶段：先同时写入匹配的 `uboot.img` 和 `trust.img` 并启动当前已验收 OpenWrt；再更新 OpenWrt 验证 BL31 GET/ROUND；最后才通过 Rockchip Upgrade Loader 操作更新 DDR v1.30/miniloader v1.26。U-Boot/trust 是一个接口兼容变量，OpenWrt 和 Loader/DDR 则继续隔离验证。

BL32 当前占用解释了实机 DRAM 映射中的 `0x08400000-0x0a200000` 安全内存空洞。若未来取消 BL32、回收内存，必须重新验证冷启动、软复位、PSCI/SMP、CPU 与 DDR 调频、休眠/唤醒和内存映射；不能只从 INI 删除一个文件就视为完成。

## 分区边界

原厂 GPT 不是 RK3399 在所有方案下的硬编码布局，但本工程当前交付物与它构成一套已知约定：

| 区域 | 当前用途 | 是否可独立调整 |
|---|---|---|
| loader 保留区 | miniloader + DDR bin | 否；需单独启动固件方案 |
| `uboot@0x2000` | 独立 BL33 / U-Boot | 当前方案下否 |
| `trust@0x4000` | 独立 BL31/BL32 | 当前方案下否 |
| `boot_linux@0x6000` | 64 MiB ext2 启动容器；GPT 第 3 分区内 | 可改，但须同步 GPT、脚本、镜像和部署规则 |
| `rootfs@0x36000` | `PARTLABEL=rootfs`，使用剩余空间 | 可改，但须同步 GPT、镜像和根挂载规则 |

迁移到 SPL + `u-boot.itb`、A/B 系统或新 GPT 都应作为完整的新启动链设计和验收，不能通过删除 `trust` 分区局部完成。
