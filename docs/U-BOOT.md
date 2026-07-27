# U-Boot 适配说明

## 选择

正式基线继续使用 Toybrick/Rockchip U-Boot 2017.09，commit `22af63bad708ff41513375a8ecf7fe8d2d521c84`。主线 U-Boot v2026.07 暂不采用，因为迁移还需要重新验证 LPDDR3、TPL/SPL、RK809、BL31/BL32/Trust、启动介质和完整板级 DTS，当前风险与收益不匹配。

配套版本：

- rkbin：`78c1c4939634a76f6f4531c912c1a52a83f0451b`。
- Toybrick linux-x86 工具链：`32505a8032d04e9320dbdb817b08bf67bdfb5a0c`。
- 配置：`rk3399pro_defconfig`。
- 设备树：厂商 `rk3399-evb`。

## 可信固件

当前厂商 miniloader 从独立 `trust` 分区加载 BL31 和 BL32，再进入独立 `uboot.img`。本工程只构建 U-Boot，不重新生成 `trust.img`。其中 BL32/OP-TEE 对当前 OpenWrt 应用不是必需功能，但 BL31 仍是现有启动链的一部分，因此不能删除整个 `trust` 分区。组成、内存占用和替代启动方案见 [启动链设计](BOOT-CHAIN.md)。

## 补丁

1. `patches/u-boot/0001-modern-linux-host-build-compat.patch`
   - 兼容现代 Linux x86_64、GCC/flex 和旧版 DTC。
   - 修正工具链目录与 DTS include 处理。
2. `patches/u-boot/0002-tb-rk3399prod-dwmmc-tf-reliability.patch`
   - 修正 DWMMC IDMAC 完成等待和状态清理。
   - 把单次 MMC 请求限制为 2048 blocks/1 MiB。
   - 只对 U-Boot 的可拔 TF 控制器使用 25 MHz + PIO。

该策略已稳定读取约 30 MiB FIT；Linux 启动后 TF 仍使用 50 MHz + IDMAC，不影响内核运行阶段性能。eMMC SDHCI 高速路径未被修改。

## 启动地址

OpenWrt FIT 统一加载到 `0x10000000`。不要使用 `0x08000000`，否则约 30 MiB FIT 会覆盖 `0x08400000-0x0a200000` 的 BL32/TEE 保留区并导致 `bootm` 异常。

## 从 TF 卡更新 boot_linux

当前 U-Boot 已启用 MMC 命令、TF 的 Rockchip DWMMC 和 eMMC 的 Rockchip SDHCI。实机编号固定为 `mmc 1` = TF、`mmc 0` = eMMC，因此可以把 `boot_linux.img` 放在 TF 卡第一个 FAT 分区，再从 U-Boot 手动写入 eMMC。

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
