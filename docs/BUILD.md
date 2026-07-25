# 初始化、构建与打包

## 支持环境

构建主机固定为原生 Linux x86_64。推荐 Debian/Ubuntu，并安装：

```sh
sudo apt-get update
sudo apt-get install -y build-essential flex bison gawk gcc-multilib \
  libc6-dev libc6-dev-i386 gettext git libncurses-dev libssl-dev libelf-dev \
  pkg-config python3 python3-setuptools rsync swig unzip zlib1g-dev file \
  wget xz-utils bc device-tree-compiler bzip2 cpio e2fsprogs
```

`make init` 会在下载前检查 Linux x86_64、必要命令，并实际编译/链接小型探针，确认 native libc、C++、32-bit libc、ncurses、OpenSSL、zlib、libelf、Python setuptools 和 Perl 模块可用；`swig` 与 `dtc` 也会执行版本探测。检查失败时会列出缺项和 Debian/Ubuntu 安装命令，不会等到长时间构建后才报错。默认目录：

```text
.work/  上游源码、feeds、工具链和编译树
out/    未归档的构建产物
dist/   最终 tar.gz 发布包及 SHA256
```

可在命令前用 `TB_WORK_DIR`、`TB_OUT_DIR`、`TB_DIST_DIR` 将这三个目录放到其他磁盘。

OpenWrt 强制要求大小写敏感文件系统。在 WSL 中不要把 `TB_WORK_DIR` 放在普通的 `/mnt/c` 或 `/mnt/d` NTFS 挂载上，应放到 WSL ext4，例如：

```sh
TB_WORK_DIR=$HOME/tb-rk3399prod-work make init
TB_WORK_DIR=$HOME/tb-rk3399prod-work make all
```

初始化脚本会在下载大型仓库前检查此条件。

构建脚本会隔离 WSL 自动注入的 Windows PATH，只使用标准 Linux host 路径，避免带空格或相对片段的 Windows 路径破坏 OpenWrt 的 `find -execdir` 安全检查。确需额外 host 工具目录时可显式设置 `TB_HOST_PATH`。

## 1. 初始化

```sh
make init
```

初始化过程会下载并固定到：

| 组件 | 版本 |
|---|---|
| Toybrick U-Boot | `22af63bad708ff41513375a8ecf7fe8d2d521c84` |
| Toybrick rkbin | `78c1c4939634a76f6f4531c912c1a52a83f0451b` |
| Toybrick linux-x86 工具链 | `32505a8032d04e9320dbdb817b08bf67bdfb5a0c` |
| OpenWrt | `v25.12.5` / `f0a60eee2fe051741c643ea6118718aae1ef17fb` |
| Linux | OpenWrt 官方 `6.12.94` |

OpenWrt 只使用一个工作树和一个正式配置，PCIe host 默认启用。

初始化是幂等的。网络 fetch 会自动重试三次；中断后再次执行可以继续未完成的初始 checkout。补丁状态只由 Git 判断，不写额外状态文件；每个补丁必须是“可应用”或“已完整应用”，其他状态立即失败。所有上游仓库固定到精确 commit；`configs/feeds.conf` 只保留当前固件所需的 `packages` feed，并固定到 OpenWrt 25.12.5 官方发布使用的 commit，不会因远端分支变化而漂移。当前配置未启用 LuCI，因此不会下载 `luci`、`routing`、`telephony` 或 `video` feed。

工作树只接受当前基线的精确状态。调整任一上游基线、补丁模型或目录模型后，应使用一个空的 `TB_WORK_DIR` 重新初始化；这使代码路径保持单一，也避免把无法证明正确的状态带入固件。

`dts/rk3399pro-toybrick-prod.dts` 和 `.dtsi` 是板级设备树的唯一权威文件。每次初始化都会读取 OpenWrt Rockchip target 的 `KERNEL_PATCHVER`，将这两个文件覆写到对应的 `target/linux/rockchip/files-<版本>/arch/arm64/boot/dts/rockchip/`，然后逐字节校验。OpenWrt 补丁不再保存 DTS 副本；更新设备树后必须先重新运行 `make init`，再执行构建。

`make init` 随后验证 feed 仓库的 origin、HEAD、索引、干净状态和仓库数量；精确匹配时不访问 feed 远端，不匹配时才执行更新。OpenWrt 的 `src-git` feed 获取本身使用 `--depth 1`，不会同步完整 Git 历史。之后安装 package 索引、写入唯一的 `configs/openwrt.config`、执行 `make defconfig` 和 `make download`。因此成功返回表示编译所需源码已经准备完成；可用 `make init JOBS=4` 控制源包并行下载数。

## 2. 项目检查

```sh
make check
```

该目标不下载也不编译源码。它检查 Shell 语法、Git whitespace、目录约束、正式补丁可解析性、DTS 唯一来源、OpenWrt 关键配置、feed 的 40 位 commit 锁定以及启动地址/根分区参数。若 `.work/` 已初始化，还会验证上游 HEAD、补丁反向校验、feed 仓库、OpenWrt `.config` 和 DTS 同步结果。`make init` 完成前也会自动执行同一套检查。

## 3. 构建

构建全部目标：

```sh
make all
```

OpenWrt 并行数可通过 Make 变量设置；8 GiB 内存的主机建议从 2～4 开始：

```sh
make all JOBS=4
```

也可以单独执行：

```sh
make uboot
make openwrt
```

直接调用脚本时也可指定并行数：

```sh
bash scripts/build.sh all 16
```

`make all` 不调用初始化，只检查主机依赖、工作树、固定基线、补丁、feed、`.config` 和 DTS 状态；任一输入未准备好便要求先执行 `make init`。U-Boot 使用厂商命令 `./make.sh rk3399pro`。OpenWrt 构建阶段不执行 `feeds update/install`、`defconfig` 或 `make download`，只执行编译；并行构建失败时自动以 `-j1 V=s` 重试，保留完整错误位置。构建完成后，脚本使用 OpenWrt host `mkimage` 和 `e2fsprogs` 生成 64 MiB `boot_linux.img`，并校验、规范命名 128 MiB SquashFS `rootfs.img`。

关键 OpenWrt 输出为：

```text
out/openwrt/openwrt-...-toybrick_tb-rk3399prod-kernel.bin
out/openwrt/openwrt-...-toybrick_tb-rk3399prod-initramfs-kernel.bin
out/openwrt/boot_linux.img
out/openwrt/rootfs.img
```

第一项是 eMMC 正常启动 FIT，第二项仅用于恢复。`boot_linux.img` 包含正常 FIT 和 `boot.scr`；`rootfs.img` 写入 grow `rootfs` 分区后，首次启动会自动用其剩余空间建立 ext4 `/overlay`。

## 4. 打包

```sh
make package
```

打包要求 U-Boot 和 OpenWrt 两个目标均已完成。输出：

```text
dist/tb-rk3399prod-openwrt-25.12.5.tar.gz
dist/tb-rk3399prod-openwrt-25.12.5.tar.gz.sha256
```

包内包含固件、逐文件 `SHA256SUMS` 和固定上游版本信息。OpenWrt 输出目录另外保留官方 `sha256sums`，工程生成的目录级清单使用 `TB-SHA256SUMS`，避免在 NTFS 上发生大小写文件名碰撞。`boot_linux.img` 是原厂 `boot_linux` 分区使用的 ext2 镜像，内部包含正常 FIT 和安全加载地址为 `0x10000000` 的 `boot.scr`；`rootfs.img` 提供只读 SquashFS 和首次启动自动创建的持久化 ext4 overlay。二者都不是 Rockchip `update.img`。

## 刷写边界

使用 Rockchip 官方 RKDevTool/rkdeveloptool 和本板官方 loader、parameter/分区表。`uboot.img` 只对应 `uboot@0x2000`，`boot_linux.img` 只对应 `boot_linux@0x6000`，`rootfs.img` 只对应 `rootfs@0x36000`；不得覆盖 `trust@0x4000`。正常系统必须成对更新 `boot_linux.img` 与 `rootfs.img`。详细边界见 `EMMC-INSTALL.md`，本工程不提供自动刷机命令。
