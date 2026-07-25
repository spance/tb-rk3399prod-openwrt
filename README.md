# TB-RK3399ProD OpenWrt 适配工程

面向 Toybrick TB-RK3399ProD 的 OpenWrt 25.12.5 板级适配。仓库只保存可维护的 DTS、U-Boot/OpenWrt 补丁、固定配置、构建脚本和设计文档；上游源码、工具链、调试日志、设备信息与编译产物均不提交。

正式 profile 包含串口/HDMI 双 Linux console、RTL8822CE PCIe Wi-Fi、千兆以太网、USB、TF、eMMC 持久化 overlay 和 PCIe host；HDMI 音频、图形桌面、GPU、板载无线、蓝牙和 NPU 不在当前范围内。

## 构建

在原生 Linux x86_64 主机执行：

```sh
make check
make init J=4
make all J=4
make package
```

| 目标 | 职责 |
|---|---|
| `make check` | 离线检查工程结构、脚本、补丁、配置和关键不变量 |
| `make init` | 获取固定上游和唯一 `packages` feed，应用补丁、同步 DTS、生成配置并下载全部源包 |
| `make all` | 只验证既有初始化状态并编译 U-Boot/OpenWrt、生成分区镜像 |
| `make package` | 校验 `out/` 并生成 `dist/` 发布包 |
| `make clean` | 仅删除 `out/` 和 `dist/` |
| `make reset-work` | 校验 origin/固定 commit 后强制复位 `.work` 内的上游 Git 工作树 |
| `make reinit J=2` | 依次执行 `reset-work` 和 `init` |

完整的主机依赖、版本固定、目录变量和构建行为见 [构建说明](docs/BUILD.md)。8 GiB 内存主机建议先使用 `J=2`～`4`。

## 构建产物

| 文件 | 用途 |
|---|---|
| `out/uboot/uboot.img` | 当前厂商 miniloader 启动链使用的 U-Boot |
| `out/openwrt/boot_linux.img` | eMMC 正常启动容器，包含 OpenWrt FIT 和 `boot.scr` |
| `out/openwrt/rootfs.img` | SquashFS 系统和首次启动自动创建的持久化 ext4 overlay |
| `out/openwrt/*initramfs-kernel.bin` | TF/串口恢复启动 |
| `dist/*.tar.gz` | 最终发布包及 SHA256 |

## 工程结构

```text
boot/             boot_linux 容器使用的 U-Boot 启动脚本
configs/          OpenWrt 最小配置和精确锁定的必要 feed
docs/             架构、构建、硬件、部署和维护文档
dts/              TB-RK3399ProD 唯一权威 DTS/DTSI
patches/openwrt/  OpenWrt v25.12.5 板级补丁
patches/u-boot/   Toybrick U-Boot 板级补丁
scripts/          检查、初始化、构建和打包脚本
```

`.work/`、`out/` 和 `dist/` 均为可重新生成且不纳入版本控制的目录。板级参数和升级回归基线见 [硬件参考](docs/HARDWARE-REFERENCE.md)，当前验收状态见 [硬件状态](docs/HARDWARE-STATUS.md)。

`make clean` 只删除 `out/` 和 `dist/`。若上游工作树被中断的补丁或人工修改污染，使用显式的 `make reset-work`；它会丢弃 `.work` 内的 Git 修改，但保留已下载和已编译的 ignored cache。`make reinit J=2` 可以完成工作树复位并重新初始化。

## 启动与部署

`trust.img`、BL31/BL32、厂商 miniloader 和分区可变边界统一说明在 [启动链设计](docs/BOOT-CHAIN.md)。刷写映射、官方工具边界、恢复启动和上板验收独立维护在 [eMMC 部署与验收](docs/EMMC-INSTALL.md)。

本工程不提供自动刷写或整盘 `dd` 脚本。当前发行版沿用已验证的官方 loader、`uboot`/`trust` 位置和 GPT；不要把 OpenWrt 镜像写入 `trust` 分区。
