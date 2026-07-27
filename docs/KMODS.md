# 内核模块策略

## 当前结论

本项目只支持由本项目固定源码、最终 Kconfig 和工具链构建的内核模块，不把 OpenWrt 官方 `rockchip/armv8` 预编译 `.ko` 声明为兼容模块。

当前内核包 ABI 固定在 `configs/kernel-abi.conf`：

| 项目 | 固定值 |
|---|---|
| OpenWrt | 25.12.5，commit `f0a60eee2fe051741c643ea6118718aae1ef17fb` |
| target | `rockchip/armv8` |
| Linux | `6.12.94`，kernel package release `r1` |
| 本项目 Kconfig ABI | `cfceb14a62d77a03b5b109290342abb5` |

构建会把真实生成的 `.vermagic` 与该值比较，manifest 也必须包含同一项 `kernel (= 6.12.94~cfceb14a62d77a03b5b109290342abb5-r1)`。它用于发现意外配置漂移，不用于伪装成另一个内核。

## 为什么不能只覆盖官方哈希

OpenWrt 软件包中的 `kernel (= <version>~<hash>-r<release>)` 是包管理依赖。Linux 加载 `.ko` 时还会检查模块自身格式，并按照当前内核编译出的数据结构解释模块内容。两层检查不是一回事。

实机曾将包管理哈希强制改为官方 `5fab3a97d147fbf8146094eeebd78fd9`。官方 `kmod-dummy` 因而能够安装，但 `insmod dummy.ko` 仍然失败：

```text
.gnu.linkonce.this_module section size must match the kernel's built struct module size at run time
```

ELF 静态检查显示，官方 `dummy.ko` 的 `.gnu.linkonce.this_module` 是 640 字节，本项目内建 `exfat.ko` 是 704 字节。两者内部 vermagic 虽然同为 `6.12.94 SMP mod_unload aarch64`，`struct module` 布局仍不一致。Linux 6.12 的 `struct module` 含有多组受 Kconfig 控制的字段，因此这种差异不能通过改包名、改哈希、`insmod -f` 或修改加载器安全消除。

已证伪的双 ABI 补丁和官方 kmod 仓库已从工程删除，避免让 APK 的安装成功掩盖内核 ABI 风险。

## `ALL_KMODS` 的真实作用

OpenWrt 将 `CONFIG_ALL_KMODS` 定义为“默认选择全部内核模块包”。包元数据生成器会把每个 `kmod-*` 默认选为 `m`：它们会参与构建并输出软件包，但不会因此全部进入设备 SquashFS。只有 profile 的 `DEVICE_PACKAGES` 和依赖仍会进入固件。

OpenWrt 25.12.5 官方 `rockchip/armv8` buildbot 配置启用了 `CONFIG_ALL_KMODS=y`，本项目正式配置没有启用它。因此：

- 从本项目删除 `ALL_KMODS` 不会解决问题，因为它原本就未启用；
- 无法从已经发布的官方 `.ko` 中“删除 `ALL_KMODS`”；
- 为本项目增加 `ALL_KMODS` 会改变最终内核 Kconfig 和 ABI，需要完整重编、更新 ABI 基线并重新刷写内核与 rootfs；
- 增加它有机会使配置更接近官方 buildbot，但不等于证明官方模块兼容，因为板级 DRM、Type-C、debugfs 和其他选择仍可能改变结构布局或依赖符号。

## 增加模块的安全方式

少量确定需求优先加入板级 `DEVICE_PACKAGES`，随后重新构建并刷写完整 `openwrt.img`。驱动、内核和 rootfs 中的模块来自同一构建，交付边界最清楚。

若以后需要大量按需安装的模块，应把 `CONFIG_ALL_KMODS=y` 作为新的永久构建基线，并发布本项目构建产生的 target kmod APK 仓库。该路线不会让所有模块进入固件，但会显著增加下载量、构建时间和输出空间。上线前需要：

1. 更新 `configs/kernel-abi.conf` 中经审计的新 ABI；
2. 确保固件和 kmod 仓库来自相同 OpenWrt commit、Linux 版本、Kconfig 与工具链；
3. 为仓库生成并保留 APK 索引和签名，设备只配置该项目仓库；
4. 用存储、网络、netfilter 等代表模块完成加载、卸载、重启和压力测试。

若必须直接加载 OpenWrt 官方预编译模块，则需复现官方 buildbot 的完整配置，而不是只添加或删除一个选项。至少要比较最终 `.config.set`、模块内部 vermagic、`.gnu.linkonce.this_module` 大小、导出符号/CRC，并在板上装卸代表模块。所有门槛通过前，不应覆盖 `.vermagic` 或把官方 kmod 仓库写入正式镜像。

## 升级约束

升级 OpenWrt、Linux、Kconfig、工具链或内核补丁后，内核和所有外部 kmod 必须作为一个 ABI 单元重新构建。不能用 boot-only 更新把新内核与 overlay 中的旧模块混用；升级前应卸载或清理后装 kmod，完整刷写后再从匹配仓库安装。

构建产物 `out/openwrt/kernel-abi.buildinfo` 记录版本和本项目 ABI，`out/openwrt/kernel.config` 保存最终内核配置，便于后续升级比较。

## 上游依据

- [OpenWrt 25.12.5 build options：`ALL_KMODS`](https://github.com/openwrt/openwrt/blob/f0a60eee2fe051741c643ea6118718aae1ef17fb/config/Config-build.in)
- [OpenWrt kmod 默认选择逻辑](https://github.com/openwrt/openwrt/blob/f0a60eee2fe051741c643ea6118718aae1ef17fb/scripts/package-metadata.pl)
- [OpenWrt 25.12.5 `rockchip/armv8` 官方构建配置](https://downloads.openwrt.org/releases/25.12.5/targets/rockchip/armv8/config.buildinfo)
- [Linux 6.12 `struct module`](https://github.com/torvalds/linux/blob/v6.12/include/linux/module.h#L378)
