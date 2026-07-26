# 文档索引

## 构建与维护

- [构建说明](BUILD.md)：Linux x86_64 项目检查、初始化、构建和打包。
- [硬件参考](HARDWARE-REFERENCE.md)：板级硬件、关键电气/总线参数和升级回归基线。
- [硬件状态](HARDWARE-STATUS.md)：已确认和待验收硬件状态。

## 系统架构

- [启动链设计](BOOT-CHAIN.md)：厂商 miniloader、`trust.img`、BL31/BL32 及分区可变边界。
- [启动内存布局](BOOT-MEMORY-MAP.md)：TEE、FIT 和 Linux 的 DRAM 地址约束。
- [HDMI Linux console](HDMI-CONSOLE.md)：Rockchip DRM、fbcon、双 console、键盘登录和验收。
- [U-Boot 适配](U-BOOT.md)：厂商 U-Boot 基线、补丁和启动地址。
- [OpenWrt 适配](OPENWRT.md)：OpenWrt profile、硬件范围、持久化 overlay 和恢复启动。
- [网络性能与加速策略](NETWORK-PERFORMANCE.md)：千兆压测、IRQ 绑核、软件 flow offload、AES 和 PCIe RSS。

## 部署与验收

- [eMMC 部署与验收](EMMC-INSTALL.md)：eMMC 写入映射、恢复方法和上板验收步骤。

## 外部资料

- [外部资料](REFERENCES.md)：Toybrick、Rockchip、OpenWrt 和启动固件的固定来源链接。
