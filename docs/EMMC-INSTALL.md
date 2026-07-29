# eMMC 部署与验收

本文只描述构建完成后的写入边界、恢复方法和上板验收。构建主机和产物生成流程见 [构建说明](BUILD.md)；`trust.img`、BL31/BL32 和分区设计依据见 [启动链设计](BOOT-CHAIN.md)。

## 部署前提

本板沿用原厂 GPT 和 512-byte sector：

| 分区 | 起始 LBA | sector 数 | 容量 |
|---|---:|---:|---:|
| `uboot` | `0x2000` | `0x2000` | 4 MiB |
| `trust` | `0x4000` | `0x2000` | 4 MiB |
| `boot_linux` | `0x6000` | `0x30000` | 96 MiB |
| `rootfs` | `0x36000` | grow | eMMC 剩余空间，约 29 GiB |

当前厂商 miniloader 启动链要求保留 `uboot@0x2000` 和 `trust@0x4000`。`trust.img` 同时包含 BL31 和 BL32，并非可以因 OpenWrt 不使用 OP-TEE 应用就删除的普通系统分区。项目沿用厂商 U-Boot 完整打包流程，从固定 Rockchip 官方 rkbin 同时生成 loader、`trust.img` 和 `uboot.img`。

`boot_linux` 和 `rootfs` 并非 RK3399 在所有启动方案下的硬编码布局，但当前镜像、启动脚本和验收基线均按上表生成，因此本版本也不允许单独移动。若重新设计 GPT，必须同步修改启动脚本、镜像尺寸、根分区标签和部署规则，并作为新的完整方案重新验收。

> `0x10000000` 是 FIT 的 DRAM 加载地址，不是 eMMC LBA；不得把它用于刷写工具的扇区地址。

## 部署产物

```text
out/uboot/uboot.img
out/uboot/rk3399pro_loader_v1.30.126.bin
out/uboot/trust.img
out/openwrt/openwrt.img
```

`openwrt.img` 固定为 224 MiB，是从 `boot_linux@0x6000` 开始连续写入的原始部署镜像。内部布局：

| `openwrt.img` 内偏移 | 内容 | 写入后的目标 |
|---:|---|---|
| `0` | 64 MiB ext2 启动容器 | `boot_linux@0x6000` |
| `64 MiB` | 32 MiB 清零间隙 | `boot_linux` 分区尾部 |
| `96 MiB` | 128 MiB SquashFS rootfs 载体 | `rootfs@0x36000` 的开头 |

64 MiB ext2 启动容器的内容为：

```text
/boot.cmd       可审阅的启动命令
/boot.scr       mkimage 封装、由 distro_bootcmd 执行
/openwrt.itb    正常 OpenWrt kernel + DTB FIT，不含 initramfs
/SHA256SUMS     镜像内文件校验值
```

组合镜像中的 rootfs 载体固定为 128 MiB，开头是只读 SquashFS，后面补零。SquashFS 内容上限为 120 MiB，额外 8 MiB 清零余量用于确保重装后不会误识别旧 overlay 超级块。128 MiB 是安全的覆盖范围，不是最终 `/overlay` 容量；写入 grow `rootfs` 分区后，内核看到的是整个约 29 GiB 分区。

普通 FIT、独立 `boot_linux.img`、`rootfs.img`、manifest 和 `initramfs-kernel.bin` 会保留在 `out/openwrt/`，便于检查、恢复和调试，但不进入 `dist` 发布包。

## 启动链构建与独立复现

正常工程构建无需手工执行 merger：`make uboot` 或 `make all` 会调用厂商 `./make.sh rk3399pro`，生成 U-Boot、loader 和 trust，并把通过固定大小/SHA256 校验的文件复制到 `out/uboot/`。下面的命令用于脱离 U-Boot 工作树独立复现和审计官方 loader/trust，不是第二套项目构建入口。

固定的官方 rkbin commit 不包含合并后的 RK3399Pro `trust.img`/loader 成品，但提供全部标准输入和 merger。两个 merger 都是 Rockchip 提供的 Linux x86_64 可执行文件，不需要 ARM 交叉编译器。独立复现时，请在 Linux x86_64 编译机上的临时目录取得同一固定 commit：

```sh
mkdir rk3399pro-rkbin && cd rk3399pro-rkbin
git init
git remote add origin https://github.com/rockchip-linux/rkbin.git
git sparse-checkout init --no-cone
git sparse-checkout set --no-cone \
  RKTRUST/RK3399PROTRUST.ini RKBOOT/RK3399PROMINIALL.ini \
  bin/rk33/rk3399pro_bl31_v1.35.elf \
  bin/rk33/rk3399pro_bl32_v2.12.bin \
  bin/rk33/rk3399pro_ddr_800MHz_v1.30.bin \
  bin/rk33/rk3399pro_miniloader_v1.26.bin \
  bin/rk33/rk3399pro_usbplug_v1.26.bin \
  tools/trust_merger tools/boot_merger
git fetch --depth=1 --filter=blob:none origin \
  ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4
git checkout --detach FETCH_HEAD
chmod +x tools/trust_merger tools/boot_merger
```

固定输入的 SHA256：

| 文件 | SHA256 |
|---|---|
| `tools/trust_merger` | `059b622fc7597da572d8fcf726da3897e498985b3e922015f1413fb45f89963a` |
| `rk3399pro_bl31_v1.35.elf` | `68ad1a1db071c1b63a4bdf8a5b5210ef1f880dd55c73f07fc3cb29082825dae9` |
| `rk3399pro_bl32_v2.12.bin` | `522f1c69fba21577b2bd5f297b1915b3406937fb9fe0169845b7da42c4ba745a` |
| `tools/boot_merger` | `30c5ae87038b77117fa27fb4c39d697e835492386f96f9553f57f343cee9f4dc` |
| `rk3399pro_ddr_800MHz_v1.30.bin` | `2c74f7c0a2f7b1a49225fd0dca2fd88f574177e2b87dd4c526d569a94a9bcd92` |
| `rk3399pro_miniloader_v1.26.bin` | `e0c4d582d48e7d5d654845a1d30cb639658faa2d1c93642327c89c5c895535a1` |
| `rk3399pro_usbplug_v1.26.bin` | `7c95c84a0815b288aa500c9a38334eb91ac95a8dc8d11468c9be1ae1d9752513` |

校验输入后直接运行官方工具：

```sh
./tools/trust_merger RKTRUST/RK3399PROTRUST.ini
./tools/boot_merger RKBOOT/RK3399PROMINIALL.ini
sha256sum trust.img rk3399pro_loader_v1.30.126.bin
```

得到的 `trust.img` 是官方 BL31 v1.35 + BL32 v2.12 组合；loader 是官方 DDR v1.30 + miniloader v1.26 组合。工程默认构建使用同一 INI、输入和 merger，不修改其二进制内容。

在上述固定 commit、标准 INI 和 Linux x86_64 merger 下，`trust.img` 是可重现的；loader 头部包含打包时间，尾部 CRC 随之变化，因此不能把某一次 loader 整文件 SHA256 错当成跨构建常量：

| 产物 | 字节数 | 校验方式 |
|---|---:|---|
| `trust.img` | `4194304` | 整文件 SHA256：`63ce40c87dc3cb0c0d8e84b46acb95fa5ab39601c77bfbedf3e112fb4c30d774` |
| `rk3399pro_loader_v1.30.126.bin` | `452942` | 使用同一官方 `boot_merger unpack`，校验下表四个有效载荷；发布包记录本次整文件 SHA256 |

工程的 `scripts/verify-rkbin-images.sh` 自动执行解包校验：

| 解包文件 | 字节数 | SHA256 |
|---|---:|---|
| `rk3399pro_ddr_800MH.bin` | `147456` | `e35891be5ac1cd75230544530a5d7923e0cd59d31dd9f0138696f0e5de987ad3` |
| `FlashData.bin` | `147456` | 与上项相同，并要求两文件逐字节一致 |
| `FlashBoot.bin` | `86016` | `6f5e885f968225711f99ef4bd70f26551c11393bc90a6c853f032be67e42d93c` |
| `rk3399pro_usbplug_v.bin` | `71680` | `099876f8d98e22dce58894d40176f5d49c6460edd3c417ed42f9cc952fd28979` |

任一文件名、大小、trust 哈希或 loader 有效载荷哈希不一致时先停止部署，检查 rkbin commit、INI、输入文件和宿主架构，不要继续刷写。

## overlay 工作方式

正常启动参数包含：

```text
root=PARTLABEL=rootfs rootwait rootfstype=squashfs fstools_overlay_fstype=ext4
```

GPT 分区名比 `mmcblk0p4` 一类动态编号稳定。`fstools_overlay_fstype=ext4` 用于覆盖 `fstools` 对大容量块设备默认选择 F2FS 的自动策略，确保它调用镜像中已包含的 `mkfs.ext4`。首次启动的流程为：

1. Linux 从 `PARTLABEL=rootfs` 挂载只读 SquashFS。
2. OpenWrt `fstools` 读取 SquashFS 的实际长度，并把结束位置向 64 KiB 对齐。
3. 从该位置到 `rootfs` 分区末尾建立 loop 设备，自动执行 `mkfs.ext4`。
4. ext4 挂载为 `/overlay`，其中的 `upper` 和 `work` 与 `/rom` 组成最终可写的 `/`。

因此 UCI 配置、安装的软件包以及普通 `/etc` 修改会保存在 eMMC，并在重启后继续存在。首次启动格式化会比后续启动稍慢，断电前应等待系统完全进入控制台。

重新写入 `openwrt.img` 会同时更新启动容器和 rootfs，并把 overlay 的起始元数据清零；下一次启动将重新格式化 overlay，效果等同恢复出厂。当前工程没有实现保留配置的 `sysupgrade` 流程，升级前应在系统外保存所需配置。

## 写入映射

| 文件 | 唯一目标 |
|---|---:|
| `rk3399pro_loader_v1.30.126.bin` | Rockchip 工具的 Upgrade Loader 操作；不是 GPT 分区镜像，没有普通 LBA 写入地址 |
| `uboot.img` | `uboot`，LBA `0x2000` |
| `trust.img` | `trust`，LBA `0x4000`；BL31 v1.35 + BL32 v2.12 一次性升级 |
| `openwrt.img` | 从 LBA `0x6000` 连续写入；内部 rootfs 自动落在 LBA `0x36000` |

本轮首次部署可以使用构建产物升级 `trust.img`，并在独立阶段执行 Upgrade Loader；后续 OpenWrt 更新不需要反复写 loader、U-Boot 或 trust。写入 `openwrt.img` 会覆盖 `boot_linux`、rootfs 开头和已有 OpenWrt overlay。刷写仍使用 Rockchip 官方 RKDevTool/rkdeveloptool 和本板官方 parameter/GPT，本工程不提供自动化刷机程序。

## 一次性升级官方 trust

升级 trust 之前必须同时满足：Rockchip Loader 或 Maskrom 能被主机识别；UART 可观察完整启动；已有可恢复镜像；官方输入哈希已经核对，并记录生成后 `trust.img` 的 SHA256。然后只选择 `trust.img`，目标地址严格为 `0x4000`。不得选择 loader、parameter 或整包升级，也不得把它写到 `0x6000`。

推荐分两步部署，避免把官方 trust 与新内核同时变成故障变量：先只写 `trust.img`，用当前已验收 OpenWrt 完成冷启动、六核、eMMC、网络、USB 和 reboot 冒烟；确认没有回归后，再写本轮 `openwrt.img` 启用 ROUND-only 探测。若同一次会话同时写入两者，虽然镜像布局允许，但启动失败时将难以区分可信固件和内核问题。

新 OpenWrt 启动后的第一轮验证：

1. 冷启动和 UART 中 BL31/PSCI/U-Boot/Linux 均正常；
2. 六个 CPU 在线，CPU cpufreq、温控、watchdog、eMMC、GMAC、USB 和 PCIe 没有新增错误；
3. `dmesg | grep -E 'DDR round-rate|rk3399-dmc'` 返回五组正的 ROUND 结果；
4. 探测前后 `/sys/kernel/debug/clk/sclk_ddrc/clk_rate` 都是 `800000000`；
5. 完成多次冷启动和软复位，再进入持续 I/O/网络压力测试。

若设备无法进入 U-Boot/Linux，立即通过 Loader/Maskrom 恢复原 trust，不继续更换 loader。`trust.img` 不包含 DDR bin；虽然 DDR v1.30 loader 已随构建生成，仍属于最后一个独立部署阶段，见 [DDR 固件与动态调频验证](DDR-DVFS.md)。

## 只更新 boot_linux 并保留 overlay

`out/openwrt/boot_linux.img` 是独立的 64 MiB 启动容器，只包含 `boot.scr`、kernel/DTB FIT 和校验文件。它从 LBA `0x6000` 写到 `0x25fff`；`rootfs` 从 `0x36000` 开始，中间还有 32 MiB 未写间隙。因此只写这个文件不会修改只读 SquashFS，也不会修改其后的 ext4 overlay。

Linux 主机进入 Rockchip Loader 后可执行：

```sh
rkdeveloptool ld
rkdeveloptool wl 0x6000 out/openwrt/boot_linux.img
rkdeveloptool rl 0x6000 0x20000 boot_linux.readback.img
cmp out/openwrt/boot_linux.img boot_linux.readback.img
rkdeveloptool rd
```

`wl`/`rl` 的地址和长度单位均为 512-byte sector；`0x20000` sectors 正好是 64 MiB。Windows RKDevTool 应在下载镜像页面只选择 `boot_linux.img` 一项，地址填写 `0x6000`；不得同时选择 `openwrt.img`、`rootfs` 或执行整包升级。

这个更新方式只适用于 boot-only 变更，例如 DTS、bootargs，或者完全相同 OpenWrt/Linux/Kconfig/补丁基线生成的内核。原 rootfs 和 overlay 中的 kmod 不会同步更新；如果内核版本、符号版本或模块 ABI 已改变，必须写完整 `openwrt.img`，否则 exFAT、UAS、TUN、nft-tproxy 等模块可能无法加载。

独立 `boot_linux.img` 当前保留在 `out/openwrt/`，不进入正式 `dist` 包；它属于明确知道内核/rootfs 兼容关系时使用的维护产物。

## 串口手动验证

如果默认 distro boot 没有执行脚本，可从 eMMC 第 3 分区手动加载：

```text
mmc dev 0
ext2load mmc 0:3 0x00500000 /boot.scr
setenv devtype mmc
setenv devnum 0
setenv distro_bootpart 3
source 0x00500000
```

也可跳过脚本直接验证正常 FIT，但必须设置完整根文件系统参数：

```text
mmc dev 0
ext2load mmc 0:3 0x10000000 /openwrt.itb
setenv bootargs console=tty0 console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xff1a0000 loglevel=8 root=PARTLABEL=rootfs rootwait rootfstype=squashfs fstools_overlay_fstype=ext4
bootm 0x10000000
```

如果正常 rootfs 启动失败，可从 TF 卡加载 `initramfs-kernel.bin`，并使用不含 `root=` 的恢复参数。恢复系统在内存中运行，不会自动使用持久化 overlay：

```text
mmc dev 1
fatload mmc 1:1 0x10000000 openwrt-rockchip-armv8-toybrick_tb-rk3399prod-initramfs-kernel.bin
setenv bootargs console=tty0 console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xff1a0000 loglevel=8
bootm 0x10000000
```

## 启动后验收

先确认根设备、文件系统和可用容量：

```sh
cat /proc/cmdline
lsblk -o NAME,PATH,SIZE,FSTYPE,PARTLABEL,MOUNTPOINTS
findmnt /
findmnt /rom
findmnt /overlay
df -hT /overlay
dmesg | grep -Ei 'rootfs|squashfs|overlay|loop|ext4|mmc'
```

预期 `/rom` 为 SquashFS、`/overlay` 为 loop 设备上的 ext4、`/` 为 overlayfs，且 `/overlay` 容量接近 eMMC `rootfs` 分区剩余空间。然后做跨重启验证：

```sh
echo "$(date -Iseconds)" >/etc/tb-overlay-test
sync
reboot
```

重启后执行：

```sh
cat /etc/tb-overlay-test
```

文件仍存在才算持久化验收通过。随后可安装一个小型软件包、再次重启并验证命令仍存在，最后检查 `dmesg` 中没有 ext4、loop、CQE、ADMA 或 eMMC I/O 错误。

构建机可在刷写前检查组合镜像：

```sh
bash scripts/verify-openwrt-image.sh out/openwrt/openwrt.img
stat -c '%s' out/openwrt/openwrt.img
```

检查脚本会验证开头的 ext2、`boot.scr`、正常 FIT、96 MiB 偏移处的 SquashFS 魔数和完整镜像长度；文件大小应为 `234881024` 字节。
