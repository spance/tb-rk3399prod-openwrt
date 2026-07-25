# U-Boot 适配说明

## 选择

正式基线继续使用 Toybrick/Rockchip U-Boot 2017.09，commit `22af63bad708ff41513375a8ecf7fe8d2d521c84`。主线 U-Boot v2026.07 暂不采用，因为迁移还需要重新验证 LPDDR3、TPL/SPL、RK809、BL31/BL32/Trust、启动介质和完整板级 DTS，当前风险与收益不匹配。

配套版本：

- rkbin：`78c1c4939634a76f6f4531c912c1a52a83f0451b`。
- Toybrick linux-x86 工具链：`32505a8032d04e9320dbdb817b08bf67bdfb5a0c`。
- 配置：`rk3399pro_defconfig`。
- 设备树：厂商 `rk3399-evb`。

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
