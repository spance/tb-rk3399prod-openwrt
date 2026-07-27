# 官方 kmod 兼容层

## 目标与结论

本项目允许安装 OpenWrt 25.12.5 `rockchip/armv8` 官方仓库中、且不涉及本项目改动子系统的内核模块。它解决的是个人设备后续增加 PCIe 网卡、USB 外设、文件系统、隧道或其他通用模块时的包管理问题，不把 TB-RK3399ProD 宣称为 OpenWrt 官方 profile，也不承诺任意官方 kmod 都能安全运行。

兼容层固定为以下一组不可拆分的基线：

| 项目 | 固定值 |
|---|---|
| OpenWrt | 25.12.5，commit `f0a60eee2fe051741c643ea6118718aae1ef17fb` |
| target | `rockchip/armv8` |
| Linux | `6.12.94`，kernel release `r1` |
| 本项目原生 Kconfig ABI | `cfceb14a62d77a03b5b109290342abb5` |
| 对 APK 暴露的官方 ABI | `5fab3a97d147fbf8146094eeebd78fd9` |
| 官方仓库 | `releases/25.12.5/targets/rockchip/armv8/kmods/6.12.94-1-5fab3a97d147fbf8146094eeebd78fd9/` |

唯一配置来源是 `configs/kmod-compat.conf`。镜像内的 `/etc/apk/repositories.d/tb-official-kmods.list` 必须与它一致。

## 两种 vermagic

OpenWrt 构建系统把最终内核配置中所有 `CONFIG_*=y/m` 的行排序后计算 MD5，写入内核构建目录的 `.vermagic`，再让每个 kmod 精确依赖：

```text
kernel (= 6.12.94~<hash>-r1)
```

这是包管理层的兼容门槛，并不是 `.ko` 内部由 Linux 检查的 vermagic。本项目构建时先把真实计算结果保存为 `.vermagic.native`；只有它仍等于已审计的 `cfceb14a...` 时，才把包管理使用的 `.vermagic` 写成官方 `5fab3a97...`。配置意外漂移时构建会立即失败，而不是继续沿用旧的官方标识。

实机审计中，本项目 `exfat.ko` 与从上述官方仓库解包的 `exfat.ko` 都报告：

```text
6.12.94 SMP mod_unload aarch64
```

两者都没有 `modversions` 标志。也就是说，Linux 会检查内核版本、SMP、模块卸载能力和架构，并在加载时解析所需符号，但不会用 `CONFIG_MODVERSIONS` 的符号原型 CRC 阻止潜在的配置级 ABI 差异。因此，包管理检查能够受控放行，最终兼容性仍要由模块加载和功能测试确认。

## 为什么当前范围可以受控使用

本项目的 Linux 源码改动集中于 RK3399 Type-C PHY、DWC3 私有实现以及 SDHCI CQE quirk。当前补丁没有修改 `include/linux/`、架构公共头文件或 `EXPORT_SYMBOL*`。CPU thermal、debugfs、HDMI/DRM 和 DWC3 dual-role 等 Kconfig 差异会改变 OpenWrt 的配置哈希，但没有把整个内核替换成 vendor fork。

因此，与上述改动无关、且来自完全相同发布基线的模块通常具有较高兼容概率。若模块依赖的功能没有进入本项目内核，加载会以 `Unknown symbol` 等错误失败；更少见但更严重的风险是配置影响了相同符号背后的结构布局。由于当前没有符号 CRC 防线，首次使用新模块必须完成下面的实机验收。

## 支持边界

适合作为兼容层候选的范围包括：

- PCIe 网卡及其他独立端点驱动；
- USB 串口、输入设备和通用 USB 外设；
- 额外文件系统与网络文件系统；
- VPN、隧道、QoS 和常规 netfilter 扩展；
- hwmon、I2C、SPI 等与板级关键启动链无关的外设驱动。

以下子系统使用本项目内建或随镜像提供的版本，不用官方 kmod 替换：

- RK3399 Type-C PHY、FUSB302/TCPM 连接生命周期；
- DWC3 core、DRD、Rockchip glue 和本板两个 USB3 控制器；
- Rockchip DRM、VOP、DW-HDMI 和 HDMI console；
- RK3399 SDHCI、eMMC host、CQE 策略；
- 已经固化到镜像并承担启动、存储或主网络职责的板级驱动。

不要使用其他 OpenWrt 版本、snapshot、其他 target/subtarget 或其他 kmod ABI 目录，也不要用 APK 的强制选项绕过这里固定的版本边界。

## 安装和验收新模块

先确认设备仍使用固定仓库和内核依赖：

```sh
cat /etc/apk/repositories.d/tb-official-kmods.list
apk info kernel
uname -r
```

更新索引并安装所需模块：

```sh
apk update
apk add kmod-<name>
```

随后至少完成：

```sh
modinfo <module-name>
modprobe <module-name>
dmesg | tail -n 100
```

验收要求为：

1. 没有 `invalid module format`、`Unknown symbol`、Oops、warning 或 taint 异常增长；
2. 目标硬件或协议功能实际工作，而不只是 `.ko` 成功加载；
3. 完成与用途相符的持续 I/O、吞吐、断开重连或错误恢复测试；
4. 重启后模块、设备和服务仍正常；
5. 对承担网络、存储等关键职责的模块，把型号、包名和测试结论补充到项目文档后再视为交付能力。

APK 后装的模块位于 ext4 overlay。执行 `factoryreset -y -r` 或完整重刷 `openwrt.img` 会删除它们；镜像内置模块仍来自只读 SquashFS。

## 构建保护与升级规则

`patches/openwrt/0002-tb-rk3399prod-official-kmod-abi-compat.patch` 只改变 OpenWrt 包管理使用的哈希，不修改 Linux 模块内部 vermagic。构建阶段同时验证：

- 当前 OpenWrt commit、Linux 版本和 kernel release 与兼容基线一致；
- 实际生成的 `.vermagic.native` 没有变化；
- 最终 `.vermagic` 和固件 manifest 中的 `kernel` 依赖使用官方 ABI；
- 固件中的 kmod 仓库 URL 精确指向同一官方 ABI 目录；
- canonical Linux 补丁没有开始修改公共头文件或导出符号。

`out/openwrt/kmod-compat.buildinfo` 会记录原生 ABI、对外 ABI 和仓库地址，`dist` 中的 `BUILD-METADATA.txt` 也保留同样信息。

升级 OpenWrt、Linux、Kconfig 或驱动补丁时，不允许只更新官方哈希。应先移除旧假设，重新生成并比较本项目与官方配置，审计公共头文件、导出符号和内部 module vermagic，再选取代表性官方模块完成加载与压力测试。新基线必须通过完整 `openwrt.img` 部署；不能用 boot-only 更新把新内核和旧 rootfs/overlay 中的模块混合。
