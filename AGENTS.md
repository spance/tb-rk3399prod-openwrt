# AGENTS.md

本文件适用于整个仓库。它是后续维护者和自动化代理的工作入口，不替代
`README.md` 或 `docs/` 中的设计文档。开始修改前只读取与任务有关的文档，
但必须遵守下面的工程不变量。

## 项目边界

本项目为 TB-RK3399ProD 提供可重现的 OpenWrt 板级适配、厂商 U-Boot 启动链
构建和部署镜像。目标是稳定支持已经列入文档的板载硬件，并保持补丁规模、
运行时策略和发布物可审计。

- Wi-Fi、蓝牙和 NPU 不属于当前交付目标。
- mini PCIe 插槽不是 PCIe 数据链路，不能据此启用 PCIe 无线网卡。
- 独立 PCIe x1 插槽及 RTL8125BG 支持按现有专项文档维护。
- 不为未经实机验证的能力宣称“已支持”或“已交付”。
- 如果需求与硬件连线、启动链或 Linux 接口约束冲突，应明确指出，不能用
  隐藏风险的兼容代码迁就。

## 权威来源

- `scripts/lib.sh`：上游地址、固定 commit、版本、镜像尺寸、哈希和 eMMC LBA
  的唯一权威来源。不要在本文件复制这些易漂移的数据。
- `dts/`：板级 DTS/DTSI 的唯一权威副本。
- `patches/kernel/`：直接作用于固定 Linux 内核的规范补丁。
- `patches/openwrt/`：OpenWrt target、profile、内核配置和镜像规则。
- `patches/u-boot/`：固定 Rockchip vendor U-Boot 的板级补丁。
- `rootfs/`：注入固件的板级运行策略、服务和诊断程序。
- `configs/`：最小 OpenWrt 配置和 feed 固定信息。
- `boot/`：`boot_linux` 容器使用的 U-Boot 启动脚本。

`.work/` 是可保留的本地上游源码和构建树，便于编译及调试，但不是规范源；
不得只在其中修复问题。`out/`、`dist/` 和 `.work/` 都是生成目录，不纳入版本
控制。需要的修改必须回写到上述权威文件，并通过初始化脚本重新同步。

不得提交完整 OpenWrt、U-Boot、rkbin、prebuilt/工具链源码，也不得提交设备
调试日志、机器信息、用户名、绝对路径、临时数据或凭据。

## 阅读路由

- 项目能力和目录概览：`README.md`、`docs/README.md`
- 主机构建、初始化、缓存和产物：`docs/BUILD.md`
- OpenWrt profile、rootfs、overlay 和软件包：`docs/OPENWRT.md`
- eMMC 布局、刷写边界、恢复和验收：`docs/EMMC-INSTALL.md`
- BootROM、loader、BL31/BL32/BL33：`docs/BOOT-CHAIN.md`
- U-Boot、启动地址和 TF 维护启动：`docs/U-BOOT.md`
- 板级电气连接与固定参数：`docs/HARDWARE-REFERENCE.md`
- 已验证能力与尚未验证事项：`docs/HARDWARE-STATUS.md`
- Type-C 驱动设计和日志：`docs/USB-TYPE-C.md`
- PCIe RTL8125BG：`docs/PCIE-RTL8125.md`
- DDR 固件与动态调频门槛：`docs/DDR-DVFS.md`
- 按需内核模块：`docs/KMOD-BUILDER.md`
- 网络调优和性能证据：`docs/NETWORK-PERFORMANCE.md`

## 修改规则

1. 不在 OpenWrt 工作树维护第二份 DTS、rootfs 文件或内核补丁。修改规范副本，
   再运行 `make init` 同步。
2. `configs/openwrt.config` 保持最小化；板级默认软件包、Kconfig 和镜像规则由
   同一个 OpenWrt 板级补丁原子维护，避免保存展开后的重复配置。
3. Linux 补丁必须能依次应用到固定内核，并保持编号和依赖顺序。修改补丁后
   必须让同步脚本使旧内核构建状态失效。
4. Type-C 行为以 Toybrick vendor 4.4 的板级时序为参考，但实现必须使用当前
   固定主线内核的标准 TCPM、role-switch、generic PHY、runtime PM 和 reset
   接口；禁止机械复制旧内核实现。修改前先确认现有诊断日志是否足以定位一次
   测试结果。
5. 不覆盖内核 vermagic、ABI 哈希或包管理依赖来强行加载官方 kmod。额外模块
   必须用同一初始化状态、Kconfig、内核源码和工具链通过项目 kmod 构建器生成。
6. 改变 DTS、Kconfig、内核补丁或内置模块后，不能假定旧 `boot_linux.img`、
   rootfs 或外置 kmod 仍然 ABI 兼容；按文档选择完整重刷或 boot-only 更新。
7. 硬件状态文档必须区分静态设计、启动日志观察、短测和长期压力测试。性能
   数据应记录方向、持续时间、并发、介质、文件系统和直接 I/O 等必要条件。
8. 不把聊天过程和失败尝试写成项目历史。只沉淀仍然有效的结论、原因、风险、
   复现方式和验收结果；Git 历史承担具体变更记录。

## 构建与检查

标准 Linux x86_64 流程：

```sh
make check
make -j4 init
make -j4 all
make package
```

- `make all` 不代替 `make init`。
- `make clean` 只清理 `out/` 和 `dist/`。
- 清理 OpenWrt Rockchip 内核缓存使用 `make kernel-clean`。不要直接调用
  `make -C .work/openwrt target/linux/clean`，该路径可能触发交互式 Kconfig 或
  在配置不完整时生成错误的空 target 状态。
- 需要复位上游工作树时使用 `make reset`；这会丢弃 `.work` 中的人工修改。
- 按需模块使用 `make -j4 kmod KMODS="kmod-..."`，并遵守
  `docs/KMOD-BUILDER.md` 的模块池和 ABI 规则。
- 代码或文档修改后至少运行 `make check`。涉及实际构建、镜像或硬件的修改，
  还必须执行对应构建、镜像校验和专项上板验收，不能只凭静态检查宣布完成。

## 启动链和部署红线

- Rockchip loader 是 BootROM 使用的特殊启动组件，必须使用官方工具的
  Loader/Upgrade Loader 操作；它不是普通 GPT 分区镜像，不能按普通 LBA 0
  写入。
- `uboot.img`、`trust.img` 和 `openwrt.img` 的目标地址以 `scripts/lib.sh` 和
  `docs/EMMC-INSTALL.md` 为准，三者不可互换。
- `openwrt.img` 是按现有 GPT 布局连续覆盖 `boot_linux` 和 `rootfs` 数据区域的
  原始镜像，不是 Rockchip `update.img`，也不包含 GPT 分区表或启动链前三项。
- 完整写入 `openwrt.img` 会重建 rootfs/overlay。只写 `boot_linux.img` 虽可保留
  rootfs 和 overlay，但必须先证明内核、rootfs 内置模块和外置 kmod ABI 一致。
- `uboot.img` 的 OP-TEE 客户端必须和 `trust.img` 内 BL32 的消息接口兼容；两者
  升级时应作为一个配对，在同一刷机会话写完且中间不重启。Loader/DDR 仍作为
  风险更高的独立阶段最后升级，并始终保留 Loader/Maskrom、UART 和已知可恢复
  镜像。

## 文档维护

改变实现时同步更新唯一相关文档，不在多个文件复制大段相同说明。尤其需要
同步记录以下变化：

- 硬件支持状态或性能验收结果；
- 上游基线、镜像布局、启动地址或升级边界；
- 构建命令、依赖、生成物或清理语义；
- 驱动生命周期、诊断接口和失败恢复方法；
- 软件包集合、overlay 行为或 kmod ABI 规则。

提交前检查差异中没有生成物、主机路径或调试信息，并让提交说明描述最终技术
变化，而不是对话过程。
