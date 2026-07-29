# 按需 kmod 构建器

## 目标

本工程可以从固定的 OpenWrt、Linux 和 feed 源码按包名构建内核模块 APK，但不会把 OpenWrt 官方预编译 `.ko` 或 APK 声明为兼容包，也不会改写 kernel package 哈希、模块 vermagic 或 APK 依赖。

构建入口是：

```sh
make -j4 kmod KMODS="kmod-dummy kmod-veth"
```

该命令要求先完成 `make init` 和 `make openwrt`/`make all`。它使用 `out/openwrt` 中已经生成的固件 manifest 作为交付基线，而不是猜测设备上的内核版本。

## 模块池

新的 `CONFIG_PACKAGE_kmod-*=m` 可能改变最终 Linux Kconfig，进而改变 OpenWrt kernel package ABI。希望日后不重刷固件便能安装的模块，必须在构建这份固件时预先放进模块池：

```sh
make -j4 init KMODS="kmod-dummy kmod-veth"
make -j4 all
make package
```

`init` 会完成以下动作：

1. 只接受符合 `kmod-[a-z0-9][a-z0-9+._-]*` 的包名；
2. 确认每个包由当前固定源码唯一提供，并且适用于 `rockchip/armv8`；已经内置进固件的驱动会被拒绝，不会降级成可选模块；
3. 将其设为 `<M>` 后执行 `make defconfig`；
4. 下载模块和依赖源码；
5. 把排序后的模块池写入 `.work/BASELINES`。

`<M>` 表示编译包而不把它加入 SquashFS。第一次增加模块池后，应部署这次 `make all` 生成的完整 `openwrt.img`，确保设备内核与模块池使用同一 Kconfig。以后可以反复从这个工作树导出池内模块，不再为安装其中一个模块重刷固件。

`KMODS` 是本次工作树的显式构建参数，不会自动写入项目的正式基础配置。每次执行 `init` 或 `reinit` 都必须重复同一组包名；不带 `KMODS` 初始化会恢复基础配置。

## 构建与校验

在匹配的固件完成后执行：

```sh
make -j4 kmod KMODS="kmod-dummy"
```

构建器会：

1. 检查工作树固定 commit、补丁、DTS、feeds 和 musl 配置；
2. 确认工作树 `kernel.version` 与 `out/openwrt` manifest 一致；
3. 暂存正式 `.config`，临时选择请求包并解析实际 kmod 依赖闭包；
4. 执行源码下载、`target/linux/compile`、`package/kernel/linux/compile` 以及对应外部模块 package 目标；
5. 再次读取构建产生的真实 `kernel.version`；
6. 只有候选值与固件值逐字节相同才输出 APK；
7. 恢复正式 `.config`。

若请求模块不在当前模块池中，并导致 kernel package ABI 变化，命令会失败并显示固件与候选版本。它不会生成“强制可安装”的 APK，同时会清理候选内核和 kmod 缓存，避免后续构建误用。此时应以包含该模块的新 `KMODS` 重新初始化、构建和部署完整固件。

## 输出与安装

成功输出示例：

```text
out/kmods/6.12.94-<abi>-r1/kmod-dummy-<request-id>/
├── BUILDINFO
├── INSTALL.txt
├── PACKAGES
├── REQUESTED
├── SHA256SUMS
├── kmod-dummy-*.apk
└── 需要的其它-kmod-*.apk
```

`BUILDINFO` 记录 OpenWrt commit、Linux 版本、target 和完整 kernel package 版本。`REQUESTED` 是用户输入，`PACKAGES` 是实际交付的内核模块依赖闭包。

安装前先确认设备确实运行该目录 `BUILDINFO` 中的 kernel package 版本。将整个目录复制到设备，例如 `/tmp/tb-kmods/`，然后一次性提交全部本地 APK：

```sh
apk add --allow-untrusted /tmp/tb-kmods/*.apk
```

模块及 APK 数据库修改保存在 overlay。固件内核升级后，旧模块不再视为兼容模块，应在升级前移除，并从新固件对应的工作树重新构建。

## 边界

- 根文件系统、块设备、overlay、关键网络启动路径等早期启动必需驱动不能依赖 overlay 中的 APK，必须放进设备 profile。
- 构建器交付 kmod 依赖；模块附带的用户态管理工具仍按普通 OpenWrt 软件包处理。
- `make package` 的正式发布包包含 U-Boot 启动链三项固件和 `openwrt.img`；`out/kmods/` 是按具体内核生成的独立附加产物。
- 不使用 `--force-depends`、`insmod -f`、哈希覆盖或官方预编译 `.ko`。
