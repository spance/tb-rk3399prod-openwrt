# TB-RK3399ProD OpenWrt 适配工程

本工程只保存 TB-RK3399ProD 的板级 DTS、U-Boot/OpenWrt 补丁、最小配置和可复现构建脚本。上游源码、工具链、调试日志和已编译固件均不纳入工程。

## 快速开始

在原生 Linux x86_64 主机执行：

```sh
make init
make all
make package
```

- `make init`：下载固定版本的 Toybrick U-Boot、rkbin、官方交叉工具链和 OpenWrt，并应用本板补丁。
- `make all`：构建 U-Boot、正常/恢复 FIT、`boot_linux.img`，以及带自动持久化 overlay 的 `rootfs.img`。
- `make package`：校验并打包 `out/` 中的固件到 `dist/`。

下载、编译和发布目录分别是 `.work/`、`out/`、`dist/`，均由工程生成并被版本控制忽略。详细依赖、版本和操作说明见 `docs/BUILD.md`；以后升级 OpenWrt/Linux 时的硬件回归基线见 `docs/HARDWARE-REFERENCE.md`。

## 目录

```text
configs/          唯一的 OpenWrt 最小配置
boot/             eMMC boot_linux 分区使用的 U-Boot 启动脚本
docs/             构建、硬件状态、启动内存和 eMMC 安装说明
dts/              TB-RK3399ProD 最终 DTS/DTSI
patches/u-boot/   官方 Toybrick U-Boot 补丁
patches/openwrt/  OpenWrt v25.12.5 板级补丁
scripts/          初始化、构建和打包脚本
```

刷写使用 Rockchip 官方 RKDevTool/rkdeveloptool，并沿用开发板官方 loader、parameter/分区表。本工程不提供自动刷写或整盘 `dd` 脚本。正常安装必须成对写入 `boot_linux.img@0x6000` 和 `rootfs.img@0x36000`；首次启动会自动把 eMMC `rootfs` 分区的剩余空间初始化为 ext4 `/overlay`。
