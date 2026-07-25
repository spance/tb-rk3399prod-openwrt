# eMMC boot_linux 镜像

## 原厂分区边界

本板原厂 parameter 使用 512-byte sector：

| 分区 | 起始 LBA | sector 数 | 容量 |
|---|---:|---:|---:|
| `uboot` | `0x2000` | `0x2000` | 4 MiB |
| `trust` | `0x4000` | `0x2000` | 4 MiB |
| `boot_linux` | `0x6000` | `0x30000` | 96 MiB |
| `rootfs` | `0x36000` | grow | eMMC 剩余空间 |

`0x4000` 是 BL31/BL32 使用的 `trust`，不得写入 OpenWrt。`0x10000000` 是 FIT 的 DRAM 加载地址，也不是 eMMC LBA。

## 构建产物

```text
out/uboot/uboot.img
out/openwrt/openwrt-rockchip-armv8-toybrick_tb-rk3399prod-initramfs-kernel.bin
out/openwrt/boot_linux.img
```

`boot_linux.img` 固定为 64 MiB ext2，能够完整写入 96 MiB 的原厂分区。镜像内容：

```text
/boot.cmd       可审阅的启动命令
/boot.scr       mkimage 封装、由 distro_bootcmd 执行
/openwrt.itb    OpenWrt kernel + DTB + initramfs FIT
/SHA256SUMS     镜像内文件校验值
```

启动脚本优先使用 U-Boot 设置的 `devtype`、`devnum`、`distro_bootpart`；手动执行时回退到 eMMC `mmc 0:3`。FIT 固定加载到 `0x10000000`，避免 `0x08400000-0x0a200000` TEE 空洞，也避免与 `0x03200000` 内核目标地址重叠。

可以在构建机检查镜像：

```sh
e2fsck -fn out/openwrt/boot_linux.img
debugfs -R 'ls -l /' out/openwrt/boot_linux.img
```

## 写入映射与回滚边界

| 文件 | 唯一目标 |
|---|---:|
| `uboot.img` | `uboot`，LBA `0x2000` |
| 原厂 `trust.img` | `trust`，LBA `0x4000`；本工程不修改 |
| `boot_linux.img` | `boot_linux`，LBA `0x6000` |

写入前应使用 Rockchip 官方工具备份原厂 parameter/GPT、`uboot`、`trust` 和完整 `boot_linux`。写入后如果默认 distro boot 没有执行脚本，可先在串口手动验证：

```text
mmc dev 0
ext2load mmc 0:3 0x00500000 /boot.scr
setenv devtype mmc
setenv devnum 0
setenv distro_bootpart 3
source 0x00500000
```

也可跳过脚本直接验证 FIT：

```text
ext2load mmc 0:3 0x10000000 /openwrt.itb
bootm 0x10000000
```

当前 FIT 内含 initramfs。OpenWrt 可以访问 eMMC 块设备，但系统配置和软件安装默认不会持久写入原厂 `rootfs@0x36000`；持久化 rootfs/overlay 是下一阶段任务。
