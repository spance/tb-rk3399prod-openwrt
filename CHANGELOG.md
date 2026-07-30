# Changelog

本文件记录正式发布的工程能力和升级边界。具体实现、复现步骤和实机证据以
`README.md` 及 `docs/` 中的专项文档为准。

## v1.0.0 - 2026-07-30

首个稳定版本，基于 OpenWrt 25.12.5 和 Linux 6.12.94。

### 交付内容

- 固定并可复现构建 Rockchip loader、vendor U-Boot、BL31/BL32 `trust.img`、
  OpenWrt `boot_linux.img` 和带持久化 overlay 的 `openwrt.img`。
- 完成 RK809 与核心电源、六核 CPU 调频、时钟、温控、UART2、TF、eMMC、
  千兆 GMAC、PCIe、USB2/USB3、Type-C、HDMI console、watchdog 和板载 LED
  的板级集成。
- eMMC 使用 HS400 Enhanced Strobe、ADMA 和 Linux CQE depth 16；对齐厂商
  strobe 电气配置后，读写、重启和 overlay 持久化回归通过。
- RTL8125BG 使用 PCIe Gen2 x1、Linux 主线 `r8169` 和 RTL8125B 固件；实卡
  2500/full，TCP 单向 2.35 Gbit/s，60 秒双向并发合计约 4.68 Gbit/s。
- Type-C 使用标准 TCPM/role-switch/generic PHY/runtime PM 接口实现 source/host，
  已通过正反插、热拔插、UAS、5000M 和 exFAT 高速读写。
- 提供 LuCI HTTPS、简体中文、nftables/fw4、软件 flow offload、常用 GNU/网络/
  存储维护工具，以及严格匹配当前固件内核 ABI 的按需 kmod 构建器。

### 已验证性能

- 板载千兆网双向各 1800 秒、4 流 TCP：941 Mbit/s。
- RTL8125BG 两个单向短测：2.35 Gbit/s；4+4 流双向并发约
  2.35/2.33 Gbit/s。
- USB3 Type-A M.2/UAS：约 340～360 MB/s。
- USB3 Type-C M.2/UAS/exFAT：8 GiB direct 写约 300～320 MiB/s，读约
  340 MiB/s，数据比较通过。
- eMMC 非 CQE 基线：顺序读约 291～305 MB/s，4 GiB 分段直写约
  88.6～98.5 MB/s；CQE 配置完成独立零错误回归。

### 交付边界

- RTL8125 双向极限满载存在少量 RX missed/TCP 重传，当前版本接受这一边界；
  数小时双向耐久、多次冷启动和真实双口 NAT/flow-offload A/B 不在本次首版
  实机测试范围内。
- DDR 使用官方 800 MHz 固定频点。Linux 只执行无损 GET/ROUND 探测，不执行
  SET、调压或动态 DDR devfreq。
- Wi-Fi、蓝牙、HDMI 音频、图形桌面、GPU 计算和 NPU 不属于本版本目标。
- 本项目不支持通用 OpenWrt sysupgrade；完整镜像、boot-only 更新和启动链
  刷写必须遵守 `docs/EMMC-INSTALL.md` 的分区与 ABI 边界。
