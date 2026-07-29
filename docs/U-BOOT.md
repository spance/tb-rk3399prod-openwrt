# U-Boot 适配说明

## 选择

正式基线使用 Rockchip 官方 `rockchip-linux/u-boot` 的 `next-dev` commit `aeec6f2bfd5ce0cfcdfe0ffc7f84d9d143683856`。它仍是 Rockchip vendor U-Boot 2017.09，并非主线 U-Boot v2026.07；因此继续匹配现有 miniloader/trust 分区模型，同时取得较新的 RK3399Pro、DWMMC 和 OP-TEE 客户端实现。主线 v2026.07 仍不采用，因为切换到 SPL/TPL 和主线板级模型需要重新验证 LPDDR3、RK809、可信固件、启动介质及完整 DTS，风险与当前收益不匹配。

旧 Toybrick commit `22af63bad708ff41513375a8ecf7fe8d2d521c84` 已退出正式基线。实机将 BL31 v1.35/BL32 v2.12 `trust.img` 与该旧 U-Boot 混用时，BL32 明确报出 `optee api revision mismatch with u-boot/kernel` 并停止启动；这不是 OpenWrt 或 DTS 故障。新基线包含 OP-TEE API revision 2.0 客户端，构建脚本还会从 `u-boot.bin` 检查对应接口字符串，缺失时拒绝发布。

配套版本：

- Rockchip rkbin：`ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4`。
- 固定 linux-x86 AArch64 交叉工具链：`32505a8032d04e9320dbdb817b08bf67bdfb5a0c`。
- 配置：`rk3399pro_defconfig`。
- 设备树：厂商 `rk3399-evb`。

## 可信固件

当前 miniloader 从独立 `trust` 分区加载 BL31 和 BL32，再进入独立 `uboot.img`。Rockchip `./make.sh rk3399pro` 原生生成 U-Boot、loader 和 trust，本工程显式传入固定交叉编译器，并让脚本直接使用相邻固定 rkbin 的 merger。最终产物为 `uboot.img`、DDR v1.30/miniloader v1.26 loader、BL31 v1.35/BL32 v2.12 `trust.img`；trust 使用固定整文件哈希，loader 因含打包时间而由官方解包器逐项校验有效载荷。BL32 对 OpenWrt 应用不是功能依赖，但它会在进入 BL33 时校验 U-Boot 消息接口；因此 `uboot.img` 和 `trust.img` 必须来自本工程同一次固定基线，不能任意混配。组成、独立复现方法和升级边界见 [启动链设计](BOOT-CHAIN.md) 与 [eMMC 部署与验收](EMMC-INSTALL.md)。

## 补丁

唯一补丁 `patches/u-boot/0001-tb-rk3399prod-board-support.patch` 只维护板级增量：

- 显式选择 `RK3399PROMINIALL.ini` 和 `RK3399PROTRUST.ini`。上游芯片名解析会把 RK3399Pro 化简成 RK3399，不显式固定会静默封装普通 RK3399 固件。
- 只对 U-Boot 的可拔 TF 控制器使用 25 MHz + PIO，并把单次 MMC 请求限制为 2048 blocks/1 MiB。
- 保留设备树明确请求的 FIFO 模式，并在 DWMMC 错误、超时和模式选择处输出足够的诊断信息。
- 同时接受标准 `mkimage` 的零终止 legacy script 长度表和 Rockchip 私有的 `0xffffffff` 终止形式，并对表扫描和脚本长度做边界检查。OpenWrt 继续生成标准 `boot.scr`，不迁就厂商私有格式。
- 只有在构建配置实际启用 `CONFIG_ROCKCHIP_FIT_IMAGE` 时，才把 FIT 交给 Rockchip 私有 `boot_fit` 路径；普通 `CONFIG_FIT` 镜像继续使用标准 `bootm`。这两种选项在厂商代码中含义不同，不能仅凭镜像格式无条件切换。
- 保持标准 FIT 的 FDT `load` 属性可选；错误路径不会再向调用者返回未初始化的地址，也不会返回已释放的临时配置名。`bootm-no-reloc` 只有显式设为 `yes` 时才生效，变量不存在不再被误判为启用。
- RK3399Pro 默认命令直接执行 `distro_bootcmd`，不再先尝试本板不存在的 Android `boot`、Rockchip 私有 FIT 和 RK image。distro 顺序仍是可拔 TF 优先、eMMC 回退，后续 USB/网络恢复目标也保留。

旧基线需要的 host 构建和大块 IDMAC 修补不再携带：新 Rockchip 基线已经包含后续 host/DWMMC 修复，继续叠加旧实现会扩大补丁面并增加冲突风险。项目也不修改 `make.sh` 或复制 merger。

新 U-Boot 与 BL32 v2.12 已在实机确认 API revision 2.0 协商成功。标准 script 兼容补丁也已确认能够自动执行 855-byte `boot.scr`，并从 eMMC 以约 223 MiB/s 读入约 18.7 MiB OpenWrt FIT。厂商 `board_do_bootm()` 原本在仅启用通用 `CONFIG_FIT`、没有启用 `CONFIG_ROCKCHIP_FIT_IMAGE` 和 `boot_fit` 命令时，仍无条件拦截所有 FIT，并试图读取 Rockchip 私有 `/images/resource` 节点。OpenWrt FIT 使用标准 `config-1`、`kernel-1` 和 `fdt-1`，因此该私有提取返回错误。当前补丁按 Kconfig 边界限制私有分支，让标准 FIT 回到标准 `bootm`；实机已经完成 FIT 双哈希校验、FDT 重定位并进入 Linux。

实机已经确认标准 `bootm` 能选择并校验 `config-1`、`kernel-1` 和 `fdt-1`。调试期间还定位到厂商通用 FIT 代码的第二个缺陷：合法的 `fdt-1` 没有可选 `load` 属性时，加载函数错误地失败；上层又忽略失败并使用未初始化的 `load`，最终把随机高地址当作 DTB 地址并触发 EL2 SError。当前补丁恢复可选属性语义，并在所有失败出口保留调用者输出不变；这属于引导器修复，不通过给 OpenWrt FIT 强加固定地址来掩盖。

完整冷启动日志已经确认 DDR v1.30/miniloader v1.26、BL32 v2.12、U-Boot 固定 commit、标准 FIT 双哈希和安全内存映射。默认命令进一步收敛为直接 distro boot，以消除此前先尝试 Android、私有 `boot_fit` 和 `bootrkp` 产生的非致命错误。资源 DTB、U-Boot 以太网和 loader-logo 的早期提示发生在 autoboot 之前或标准 `bootm` 的显示 fixup 中；Linux 使用 FIT 自带 DTB，GMAC 和 DRM 均已正常，当前不为隐藏这些提示而关闭 U-Boot 显示或扩大核心补丁面。

该策略已稳定读取约 30 MiB FIT；Linux 启动后 TF 仍使用 50 MHz + IDMAC，不影响内核运行阶段性能。eMMC SDHCI 高速路径未被修改。

## 启动地址

OpenWrt FIT 统一加载到 `0x10000000`。不要使用 `0x08000000`，否则约 30 MiB FIT 会覆盖 `0x08400000-0x0a200000` 的 BL32/TEE 保留区并导致 `bootm` 异常。

## 从 TF 卡更新 boot_linux

当前配置已启用 MMC 命令、TF 的 Rockchip DWMMC 和 eMMC 的 Rockchip SDHCI。旧基线实机编号为 `mmc 1` = TF、`mmc 0` = eMMC；升级后的第一次维护操作必须先用 `mmc list`、`mmc info` 和分区内容重新确认编号，不允许只凭旧编号写盘。确认后可以把 `boot_linux.img` 放在 TF 卡第一个 FAT 分区，再从 U-Boot 手动写入 eMMC。

64 MiB 镜像可以放在安全的 `0x10000000`；写入前必须确认 `filesize` 为十六进制 `4000000`：

```text
setenv imgaddr 0x10000000
setenv verifyaddr 0x18000000

mmc dev 1
fatinfo mmc 1:1
fatload mmc 1:1 ${imgaddr} boot_linux.img
printenv filesize
```

确认大小后写入并回读比较：

```text
mmc dev 0
mmc write ${imgaddr} 0x6000 0x20000
mmc read ${verifyaddr} 0x6000 0x20000
cmp.b ${imgaddr} ${verifyaddr} 0x4000000
reset
```

这里不需要也不应执行 `mmc erase`。写入结束于 LBA `0x25fff`，不会到达 `rootfs@0x36000`。当前 TF 可靠性补丁已实测稳定加载约 30 MiB FIT；完整 64 MiB 更新路径第一次使用时仍必须保留回读比较，作为正式验收。

也可以把上述命令封装为 U-Boot `update.scr`，从 TF 手动执行：

```text
fatload mmc 1:1 0x20000000 update.scr
source 0x20000000
```

当前发行版没有“插卡即自动刷写”的逻辑。现有 eMMC `boot.scr` 只负责加载 OpenWrt FIT，不检查 TF 更新文件。以后若加入自动更新，至少应校验固定文件名、64 MiB 长度和 SHA256/CRC，写入后回读，记录已安装镜像避免重复刷写，并在没有更新或校验失败时回到原来的 `distro_bootcmd`。在这些保护完成前，不应把检测到 SD 文件直接写 eMMC。

只更新启动容器会保留 rootfs/overlay，也会保留其中的旧内核模块；内核与 kmod ABI 的限制见 [eMMC 部署与验收](EMMC-INSTALL.md)。
