# 启动链与 `trust.img`

## 当前启动链

本工程继续使用 Toybrick/Rockchip 厂商 miniloader 启动模型：

```text
RK3399 BootROM
  -> Rockchip miniloader（DDR 和启动介质初始化）
  -> trust.img：BL31，随后可进入 BL32
  -> uboot.img：BL33 / U-Boot
  -> boot_linux：OpenWrt FIT（Linux + DTB）
  -> rootfs：SquashFS + ext4 overlay
```

Rockchip 官方说明明确区分两种方式：miniloader 从独立 `trust.img` 加载可信固件；SPL 模型则可把可信固件放入 `u-boot.itb`。本工程采用前者，没有构建 SPL 或 `u-boot.itb`。

## 当前 `trust.img` 的实际内容

固定 rkbin commit `78c1c4939634a76f6f4531c912c1a52a83f0451b` 的 `RKTRUST/RK3399TRUST.ini` 定义为：

| 阶段 | 文件 | 加载地址 | 当前作用 |
|---|---|---:|---|
| BL31 | `rk3399_bl31_v1.30.elf` | `0x00040000` | ARM Trusted Firmware 的 EL3/安全监控阶段；当前 miniloader 启动链需要 |
| BL32 | `rk3399_bl32_v1.21.bin` | `0x08400000` | Rockchip OP-TEE 安全世界固件；占用 TEE 保留内存 |
| BL33 | 不在 `trust.img` 中 | — | 由独立 `uboot.img` 提供 U-Boot |

所以 `trust.img` 不是“给 OP-TEE 做普通设备初始化”的镜像。DDR 和启动介质的早期初始化主要由 miniloader 完成，普通外设由 U-Boot 或 Linux/DTS 初始化；`trust.img` 同时承载当前启动链所需的 BL31 和可选安全世界 BL32。

当前 OpenWrt 目标没有配置 OP-TEE 用户空间、TA 或板级 OP-TEE 接口，BL32 不提供本项目要求的路由功能。但不能因此删除整个 `trust.img`：这样会连同 BL31 一起移除，厂商 miniloader 将无法按当前方式进入 U-Boot。BL32 同时解释了实机 DRAM 映射中 `0x08400000-0x0a200000` 的安全内存空洞。

## 当前工程决策

- 保留原厂 `trust.img` 和 `trust@0x4000`，本工程不生成、不更新它。
- OpenWrt 升级只更新本工程构建的 `uboot.img` 和从 LBA `0x6000` 连续写入的 `openwrt.img`；不得用任何本工程镜像覆盖 `trust`。
- 若未来需要回收 BL32 保留内存，可以研究“保留 BL31、取消 BL32”的新 `trust.img`，但必须重新验证冷启动、软复位、PSCI/SMP、CPU 调频、休眠/唤醒和内存布局。它是独立启动固件项目，不属于普通 OpenWrt 升级。
- 只有迁移到 SPL + `u-boot.itb`，把 BL31（以及可选 BL32）合并进 U-Boot FIT 后，独立 `trust` 分区才可以取消；这等同于更换整个启动链。

## 分区表是否必须完全照搬原厂

不是 SoC 在任何启动方案下都强制使用这张 GPT，但当前已验证交付物与它构成一套不可拆分的部署约定：

| 区域 | 当前约束 | 是否可独立调整 |
|---|---|---|
| 官方 loader/miniloader | 当前启动链入口 | 否 |
| `uboot@0x2000` | miniloader 使用的独立 U-Boot 镜像位置 | 当前方案下否 |
| `trust@0x4000` | miniloader 使用的独立 BL31/BL32 镜像位置 | 当前方案下否 |
| `boot_linux@0x6000` | 本工程 64 MiB ext2 启动容器；脚本默认第 3 分区 | 技术上可改，但必须同时修改 GPT、启动脚本、镜像尺寸和部署规则 |
| `rootfs@0x36000` | `PARTLABEL=rootfs`，占用剩余空间 | 技术上可改，但必须保留标签并同步 GPT、镜像和部署规则 |

因此，当前版本继续使用原厂 GPT 最稳妥，也没有明显容量收益值得承担启动链回归风险。未来若要做 A/B 系统、独立数据分区或 SPL/mainline U-Boot，应把它作为新的完整分区方案设计和验收，不能只删除 `trust` 分区。
