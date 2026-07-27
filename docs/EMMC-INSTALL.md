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

当前厂商 miniloader 启动链要求保留 `uboot@0x2000` 和 `trust@0x4000`。`trust.img` 同时包含 BL31 和 BL32，并非可以因 OpenWrt 不使用 OP-TEE 应用就删除的普通系统分区；本工程不生成或更新它。

`boot_linux` 和 `rootfs` 并非 RK3399 在所有启动方案下的硬编码布局，但当前镜像、启动脚本和验收基线均按上表生成，因此本版本也不允许单独移动。若重新设计 GPT，必须同步修改启动脚本、镜像尺寸、根分区标签和部署规则，并作为新的完整方案重新验收。

> `0x10000000` 是 FIT 的 DRAM 加载地址，不是 eMMC LBA；不得把它用于刷写工具的扇区地址。

## 部署产物

```text
out/uboot/uboot.img
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
| `uboot.img` | `uboot`，LBA `0x2000` |
| 原厂 `trust.img` | `trust`，LBA `0x4000`；保留且不由本工程更新 |
| `openwrt.img` | 从 LBA `0x6000` 连续写入；内部 rootfs 自动落在 LBA `0x36000` |

正常部署只需写入 `uboot.img@0x2000` 和 `openwrt.img@0x6000`，保留原厂 `trust@0x4000`。写入 `openwrt.img` 会覆盖原厂 `boot_linux`、rootfs 开头和已有 OpenWrt overlay；用户已保留原厂完整系统镜像。刷写仍使用 Rockchip 官方 RKDevTool/rkdeveloptool 和本板官方 loader、parameter/GPT，本工程不提供自动化刷机程序。

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
