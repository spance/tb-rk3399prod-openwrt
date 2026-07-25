# 初始化、构建与打包

## 支持环境

构建主机固定为原生 Linux x86_64。推荐 Debian/Ubuntu，并安装：

```sh
sudo apt-get update
sudo apt-get install -y build-essential flex bison gawk gcc-multilib \
  libc6-dev libc6-dev-i386 gettext git libncurses-dev libssl-dev libelf-dev \
  pkg-config python3 python3-setuptools rsync swig unzip zlib1g-dev file \
  wget xz-utils bc device-tree-compiler bzip2 cpio
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

OpenWrt 只使用一个工作树和一个正式配置，PCIe host 默认启用。此前用于开发调试的无 PCIe base profile 已移除。

初始化是幂等的。网络 fetch 会自动重试三次；中断后再次执行可以继续未完成的初始 checkout。脚本会核对 commit 和补丁状态，不会静默切换到新版上游。

## 2. 构建

构建全部目标：

```sh
make all
```

也可以单独执行：

```sh
make uboot
make openwrt
```

直接调用脚本时可指定并行数：

```sh
bash scripts/build.sh all 16
```

U-Boot 使用厂商命令 `./make.sh rk3399pro`。OpenWrt 会更新/安装 feeds、执行 `make defconfig`、下载源码并构建；并行构建失败时自动以 `-j1 V=s` 重试，保留完整错误位置。

## 3. 打包

```sh
make package
```

打包要求 U-Boot 和 OpenWrt 两个目标均已完成。输出：

```text
dist/tb-rk3399prod-openwrt-25.12.5.tar.gz
dist/tb-rk3399prod-openwrt-25.12.5.tar.gz.sha256
```

包内包含固件、逐文件 `SHA256SUMS` 和固定上游版本信息。OpenWrt 输出目录另外保留官方 `sha256sums`，工程生成的目录级清单使用 `TB-SHA256SUMS`，避免在 NTFS 上发生大小写文件名碰撞。当前 OpenWrt profile 生成的是已验证启动路径使用的 initramfs FIT；正式 eMMC 分区安装和回滚仍需单独实机验收，不能把该归档误当作 Rockchip `update.img`。

## 刷写边界

使用 Rockchip 官方 RKDevTool/rkdeveloptool 和本板官方 loader、parameter/分区表。U-Boot 产物只写 U-Boot 分区，不连带改写 loader/trust；本工程不提供自动刷机命令。
