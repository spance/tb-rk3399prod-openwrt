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
out/openwrt/openwrt-rockchip-armv8-toybrick_tb-rk3399prod-kernel.bin
out/openwrt/openwrt-rockchip-armv8-toybrick_tb-rk3399prod-initramfs-kernel.bin
out/openwrt/boot_linux.img
out/openwrt/rootfs.img
```

`boot_linux.img` 固定为 64 MiB ext2，能够完整写入 96 MiB 的原厂分区。镜像内容：

```text
/boot.cmd       可审阅的启动命令
/boot.scr       mkimage 封装、由 distro_bootcmd 执行
/openwrt.itb    正常 OpenWrt kernel + DTB FIT，不含 initramfs
/SHA256SUMS     镜像内文件校验值
```

`rootfs.img` 固定为 128 MiB，开头是只读 SquashFS，后面补零。SquashFS 内容上限为 120 MiB，额外 8 MiB 清零余量用于确保重装后不会误识别旧 overlay 超级块。128 MiB 是安全的刷写载体，不是最终 `/overlay` 容量；写入 grow `rootfs` 分区后，内核看到的是整个约 29 GiB 分区。

`initramfs-kernel.bin` 仅用于 TF/串口恢复，不进入正式 `boot_linux.img`。

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

重新写入 `rootfs.img` 会把 overlay 的起始元数据清零；下一次启动将重新格式化 overlay，效果等同恢复出厂。当前工程没有实现保留配置的 `sysupgrade` 流程，升级前应在系统外保存所需配置，并始终写入同一次构建产生的 `boot_linux.img` 和 `rootfs.img`。

## 写入映射

| 文件 | 唯一目标 |
|---|---:|
| `uboot.img` | `uboot`，LBA `0x2000` |
| 原厂 `trust.img` | `trust`，LBA `0x4000`；保留且不由本工程更新 |
| `boot_linux.img` | `boot_linux`，LBA `0x6000` |
| `rootfs.img` | `rootfs`，LBA `0x36000` |

正常系统必须成对写入 `boot_linux.img@0x6000` 和 `rootfs.img@0x36000`。写入 `rootfs.img` 会覆盖原厂 rootfs 和已有 OpenWrt overlay；用户已保留原厂完整系统镜像。刷写仍使用 Rockchip 官方 RKDevTool/rkdeveloptool 和本板官方 loader、parameter/GPT，本工程不提供自动刷机命令。

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

构建机可在刷写前检查两个容器：

```sh
e2fsck -fn out/openwrt/boot_linux.img
debugfs -R 'ls -l /' out/openwrt/boot_linux.img
od -An -tx1 -N4 out/openwrt/rootfs.img
stat -c '%s' out/openwrt/rootfs.img
```

`rootfs.img` 的前四字节应为 `68 73 71 73`，大小应为 `134217728`。
