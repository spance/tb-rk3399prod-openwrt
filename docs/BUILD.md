# 初始化、构建与打包

## 支持环境

构建主机固定为原生 Linux x86_64。推荐 Debian/Ubuntu，并安装：

```sh
sudo apt-get update
sudo apt-get install -y bc bison build-essential bzip2 ca-certificates \
  device-tree-compiler e2fsprogs file flex gawk gettext git \
  libncurses-dev perl python3 python3-setuptools rsync unzip wget \
  xz-utils zlib1g-dev
```

`make init` 会在下载前检查 Linux x86_64、必要命令，并实际编译/链接小型探针，确认 native libc、C++、ncurses、zlib、Python setuptools 和 OpenWrt 要求的 Perl 核心模块可用；同时执行 `dtc` 版本探测。检查失败时会列出缺项和 Debian/Ubuntu 安装命令，不会等到长时间构建后才报错。

该清单只针对当前固定的 TB-RK3399ProD 构建路径，不是通用 OpenWrt 开发机的全量套件集。复核后的依据如下：

- 工程直接使用 `e2fsprogs` 生成并校验 `boot_linux.img`。
- 固定的厂商 U-Boot 路径使用 `bc`，需要 flex/bison 构建 Kconfig/DTC，且其 `CONFIG_MKIMAGE_DTC_PATH="dtc"` 要求 host `dtc`。
- OpenWrt 25.12.5 的 host 前置检查要求 GNU 工具、Git、Perl、Python、rsync、ncurses、zlib 及归档/下载工具；HTTPS 获取依赖 `ca-certificates`。
- OpenWrt 会自行构建 bc、bison、cpio、elfutils、flex、LibreSSL、pkgconf、xz 和 zlib 等 staged host tools，但其中少数工具在完成自举之前仍需要系统命令或开发库，因此保留上述最小集。

已删除当前路径不使用的 `gcc-multilib`、`libc6-dev-i386`、`libssl-dev`、`libelf-dev`、`pkg-config`、`swig` 和系统 `cpio`；`libc6-dev` 由 `build-essential` 依赖引入，不再重复列出。若以后启用 U-Boot `PYLIBFDT`、FIT 签名或其他 OpenWrt profile，再按新的实际构建图增加 `swig`、OpenSSL 开发库等依赖。

默认目录：

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

OpenWrt 只使用一个工作树和一个正式配置，独立 x4 插座的 PCIe host、常用维护工具和 HDMI Linux console 默认启用；板载 Mini-PCIe 插座仅接 USB2，无线驱动不纳入镜像。

初始化是幂等的。网络 fetch 会自动重试三次；中断后再次执行可以继续未完成的初始 checkout。补丁状态只由 Git 判断，不写额外状态文件；每个补丁必须是“可应用”或“已完整应用”，其他状态立即失败。所有上游仓库固定到精确 commit；`configs/feeds.conf` 只保留当前固件需要的 `packages` 和 `luci` feed，并固定到 OpenWrt 25.12.5 官方源码使用的 commit，不会因远端分支变化而漂移。routing、telephony 和 video feed 不下载。

工作树只接受当前基线的精确状态。调整任一上游基线、补丁模型或目录模型后，应使用一个空的 `TB_WORK_DIR` 重新初始化；这使代码路径保持单一，也避免把无法证明正确的状态带入固件。

`dts/rk3399pro-toybrick-prod.dts` 和 `.dtsi` 是板级设备树的唯一权威文件。每次初始化都会读取 OpenWrt Rockchip target 的 `KERNEL_PATCHVER`，将这两个文件覆写到对应的 `target/linux/rockchip/files-<版本>/arch/arm64/boot/dts/rockchip/`，然后逐字节校验。OpenWrt 补丁不再保存 DTS 副本；更新设备树后必须先重新运行 `make init`，再执行构建。

`patches/kernel/` 是 Type-C PHY/DWC3 关键 Linux 改动的唯一权威来源。初始化会把其中的直接内核补丁逐字节同步到 `target/linux/rockchip/patches-<版本>/`。这避免在 OpenWrt 外层补丁中嵌套维护驱动补丁，也允许保留一棵固定 Linux 源码树直接执行 apply/reverse 检查和继续迭代。

驱动开发时建议在工程目录之外保留两棵独立、固定 commit 的参考树：OpenWrt 当前 Linux 6.12 用于生成和反向校验补丁，Toybrick stable Linux 4.4 用于核对本板的权威时序。它们不是构建输入，也不提交到本仓库；`make clean`/`make reset` 不应操作这些参考树。每次修改直接内核补丁后，至少应在干净 6.12 树验证可正向应用、在已修改树验证可反向应用，再由 `make init` 同步到 OpenWrt。

`rootfs/` 同样是板级固件文件的唯一权威来源。`scripts/sync-openwrt-rootfs.sh` 将其中的 init 服务和 UCI 首次启动脚本复制到 Rockchip target base-files，并逐文件校验；可执行模式由同步脚本显式设置，不依赖 Windows Git 的 mode bit。当前包含 GMAC IRQ 绑核和软件 flow offload 默认值。

`make init` 随后验证 feed 仓库的 origin、HEAD、索引、干净状态和仓库数量；精确匹配时不访问 feed 远端，不匹配时才执行更新。OpenWrt 的 `src-git` feed 获取本身使用 `--depth 1`，不会同步完整 Git 历史。之后安装 package 索引、写入唯一的 `configs/openwrt.config`、执行 `make defconfig` 和 `make download`。因此成功返回表示 OpenWrt/U-Boot 补丁、直接内核补丁、DTS、rootfs 文件、feeds、配置和编译所需源码都已经准备完成；使用 GNU Make 标准参数 `make -j4 init` 控制源包并行下载数。

## 2. 项目检查

```sh
make check
```

该目标不下载也不编译源码。它检查 Shell 语法、Git whitespace、目录约束、OpenWrt/U-Boot/直接内核补丁可解析性、DTS/rootfs 唯一来源、Type-C 状态机与诊断日志不变量、网络调优、OpenWrt 关键配置、musl 目标、feed 的 40 位 commit 锁定以及启动地址/根分区参数。若 `.work/` 已初始化，还会验证上游 HEAD、补丁反向校验、feed 仓库、OpenWrt `.config`，以及内核补丁、DTS、rootfs 的逐字节同步结果。`make init` 完成前也会自动执行同一套检查。

## 3. 构建

构建全部目标：

```sh
make all
```

OpenWrt 并行数使用 GNU Make 标准 `-j` 参数控制，例如：

```sh
make -j4 all
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

`make all` 不调用初始化，只检查主机依赖、工作树、固定基线、补丁、feed、`.config`、DTS 和 rootfs 同步状态；任一输入未准备好便要求先执行 `make init`。U-Boot 使用厂商命令 `./make.sh rk3399pro`。OpenWrt 构建阶段不执行 `feeds update/install`、`defconfig` 或 `make download`，只执行编译；并行构建失败时自动关闭标准输入并以 `-j1 V=sc` 重试，既保留命令和完整错误上下文，也确保遗漏的 Kconfig 项直接失败而不会进入交互式配置。构建完成后，脚本生成并验证 64 MiB `boot_linux.img` 与 128 MiB SquashFS `rootfs.img`，再按原厂 GPT 的相对偏移组合为 224 MiB `openwrt.img`。

正式部署只需要两个镜像：

```text
out/uboot/uboot.img
out/openwrt/openwrt.img
```

`openwrt.img` 从 eMMC LBA `0x6000` 连续写入：开头是包含正常 FIT 与 `boot.scr` 的 ext2 启动容器，96 MiB 偏移处是 SquashFS rootfs；首次启动会使用 grow `rootfs` 分区剩余空间建立 ext4 `/overlay`。`out/openwrt/` 同时保留 FIT、initramfs、manifest、独立 `boot_linux.img` 和 `rootfs.img` 等诊断/恢复产物；它们不进入 `dist` 发布包。

## 4. 打包

```sh
make package
```

打包要求 U-Boot 和 OpenWrt 两个目标均已完成，并验证镜像尺寸、布局和文件系统签名。输出：

```text
dist/tb-rk3399prod-openwrt-25.12.5.tar.gz
dist/tb-rk3399prod-openwrt-25.12.5.tar.gz.sha256
```

包内只发布 `firmware/uboot.img`、`firmware/openwrt.img`、逐文件 `SHA256SUMS` 和固定上游版本信息。`openwrt.img` 是按当前 GPT 布局生成的原始连续写入镜像，不是 Rockchip `update.img`；打包使用 GNU tar sparse 格式，避免镜像中的清零间隙和 rootfs 补零区无谓占用归档空间。

## 5. 清理与工作树恢复

```sh
make clean
```

`make clean` 只删除可重建的 `out/` 和 `dist/`，绝不调用 Git，也不修改 `.work/`。自定义 `TB_OUT_DIR` 或 `TB_DIST_DIR` 时，仅允许删除已由本工程构建脚本写入隐藏标记的目录，并显式拒绝根目录、工程根目录、home 和 `TB_WORK_DIR`。

如果 `.work/` 因中断的补丁、手工调试或更新后的旧补丁状态而无法再次初始化，执行：

```sh
make reset
make -j2 init
```

`reset` 是显式的破坏性操作：它先校验每个上游仓库位于 `TB_WORK_DIR` 之下、origin 与工程固定 URL 完全一致、固定 commit 已在本地存在，然后才对 U-Boot、rkbin、工具链、OpenWrt 和 feeds 执行 `git reset --hard` 与 `git clean -fd`。因此 `.work` 内未提交的源码和未跟踪文件会丢失。它不使用 `git clean -fdx`，所以 OpenWrt 下载包、构建缓存等 ignored 数据会保留，随后 `make init` 重新应用补丁、DTS、feed 和正式配置。

便捷写法：

```sh
make -j2 reinit
```

该目标严格等价于先 `reset` 再 `init`，不会删除 `out/` 或 `dist/`。

## 后续：部署

构建和部署是两个独立阶段。产物写入映射、`trust.img` 保留要求、恢复启动与上板验收只在 [eMMC 部署与验收](EMMC-INSTALL.md) 中维护；启动固件和分区设计依据见 [启动链设计](BOOT-CHAIN.md)。
