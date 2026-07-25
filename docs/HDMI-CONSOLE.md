# HDMI Linux console

## 功能边界

本工程在 Linux 接管显示控制器后，通过 Rockchip DRM 的 fbdev emulation 把内核虚拟终端映射到 HDMI。它提供启动日志、OpenWrt 文本终端和 USB 键盘登录，不包含 U-Boot HDMI 输出、桌面环境、图形加速或 HDMI 音频。

U-Boot 和 Linux earlycon 仍只通过 UART2 输出；显示器从 Linux DRM/VOP/HDMI 完成 probe 后才开始显示。串口始终保留为恢复通道。

## 实现

- DTS 启用 RK3399 HDMI TX、VOPB、VOPB IOMMU 和 HDMI DDC 使用的 I2C3。
- HDMI 0.9 V/1.8 V 模拟供电分别使用现有 `vcca_0v9` 和 `vcca_1v8`。
- OpenWrt Rockchip 内核内建 `DRM_ROCKCHIP`、`ROCKCHIP_DW_HDMI`、`PHY_ROCKCHIP_INNO_HDMI`、DRM fbdev emulation、framebuffer console 和字体；不依赖根文件系统加载显示模块。
- 启动参数同时指定 `console=tty0` 和 `console=ttyS2,1500000n8`。串口列在最后，因此 `/dev/console` 和 OpenWrt `askconsole` 继续落在 UART2，而内核日志同时输出到 HDMI。
- Rockchip target 的 `inittab` 额外在 `tty1` 启动 `askfirst`；profile 包含 `kmod-usb-hid`，显示器前可使用普通 USB 键盘登录。

不强制写死视频模式。驱动通过 HDMI DDC 读取显示器 EDID 并选择模式，避免固定分辨率导致兼容性下降。

## 上板验收

连接 HDMI 显示器和 USB 键盘后冷启动，串口应从 BootROM/U-Boot 开始输出；HDMI 应在 Linux DRM 初始化后出现文本。系统中执行：

```sh
cat /proc/cmdline
dmesg | grep -Ei 'drm|rockchip|vop|hdmi|fbcon|frame buffer|console'
ls -l /dev/fb0 /dev/tty1
ls -l /sys/class/drm/
cat /sys/class/drm/card*-HDMI-A-*/status
cat /sys/class/drm/card*-HDMI-A-*/modes
```

预期条件：

- `/proc/cmdline` 同时包含 `console=tty0` 和 UART2 console。
- HDMI connector 为 `connected`，且至少报告一个 EDID mode。
- 日志出现 Rockchip DRM、VOPB、DW-HDMI 绑定和 framebuffer console 接管信息。
- HDMI 能持续显示内核/OpenWrt 日志，USB 键盘在 `tty1` 可获得登录终端。
- 拔插 HDMI、软重启和冷启动不影响串口、千兆网、PCIe、USB 或 eMMC。

若 DRM 已初始化但 connector 始终为 `disconnected`，优先检查显示器/线缆、HDMI 0.9 V/1.8 V 电源和 I2C3 DDC/EDID；若已有 `/dev/fb0` 和正确模式但没有文本，检查 `console=tty0`、framebuffer console 和 `tty1`。开机早期只在串口显示属于预期行为。
