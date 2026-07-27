# 文档索引

## 维护约定

- 根目录 `README.md` 负责项目定位、硬件支持矩阵、公开性能基线、适配分层、构建入口和交付边界。
- `HARDWARE-REFERENCE.md` 维护不会随一次测试改变的连线、地址、时序、版本和升级不变量；`HARDWARE-STATUS.md` 维护当前实机证据与未验收边界。
- 子系统设计只在对应专项文档维护：Type-C、网络、HDMI、启动链各自只有一个详细说明；其他文档引用它，不复制完整实现过程。
- `BUILD.md` 只描述源码到产物，`EMMC-INSTALL.md` 只描述部署与上板验收。调整镜像布局时必须同时更新二者及脚本中的布局不变量。

## 构建与维护

- [构建说明](BUILD.md)：Linux x86_64 项目检查、初始化、构建和打包。
- [硬件参考](HARDWARE-REFERENCE.md)：板级硬件、关键电气/总线参数和升级回归基线。
- [硬件状态](HARDWARE-STATUS.md)：当前交付结论、实机证据和后续耐久/扩展验收项。

## 系统架构

- [启动链设计](BOOT-CHAIN.md)：厂商 miniloader、`trust.img`、BL31/BL32 及分区可变边界。
- [启动内存布局](BOOT-MEMORY-MAP.md)：TEE、FIT 和 Linux 的 DRAM 地址约束。
- [HDMI Linux console](HDMI-CONSOLE.md)：Rockchip DRM、fbcon、双 console、键盘登录和验收。
- [U-Boot 适配](U-BOOT.md)：厂商 U-Boot 基线、补丁、启动地址和从 TF 更新 `boot_linux`。
- [OpenWrt 适配](OPENWRT.md)：OpenWrt profile、硬件范围、持久化 overlay 和恢复启动。
- [内核模块策略](KMODS.md)：原生 ABI、官方预编译模块的实机结论、`ALL_KMODS` 边界和安全扩展路线。
- [USB Type-C SuperSpeed 主机](USB-TYPE-C.md)：4.4 行为基线、6.12 驱动设计、诊断边界和复验流程。
- [网络性能与加速策略](NETWORK-PERFORMANCE.md)：千兆压测、IRQ 绑核、软件 flow offload、AES 和 PCIe RSS。

## 部署与验收

- [eMMC 部署与验收](EMMC-INSTALL.md)：完整刷写、保留 overlay 的 boot-only 更新、恢复方法和上板验收。

## 外部资料

- [外部资料](REFERENCES.md)：Toybrick、Rockchip、OpenWrt 和启动固件的固定来源链接。
