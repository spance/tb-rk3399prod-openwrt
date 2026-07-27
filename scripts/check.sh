#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

assert_file()
{
	[ -f "$1" ] || fail "required project file not found: $1"
}

assert_exact_line()
{
	file=$1
	line=$2
	[ "$(grep -Fxc -- "$line" "$file")" -eq 1 ] || \
		fail "expected exactly one line in $file: $line"
}

for script in "$SCRIPT_DIR"/*.sh; do
	bash -n "$script"
done
for script in "$PROJECT_DIR"/rootfs/etc/init.d/* \
	"$PROJECT_DIR"/rootfs/etc/uci-defaults/* \
	"$PROJECT_DIR"/rootfs/etc/hotplug.d/iface/* \
	"$PROJECT_DIR"/rootfs/usr/sbin/*; do
	sh -n "$script"
done

if grep -Eq 'scripts/feeds|make[[:space:]]+(defconfig|download)|init\.sh' \
	"$SCRIPT_DIR/build.sh"; then
	fail "build stage must not initialize feeds, configuration or downloads"
fi
grep -Fq './scripts/feeds update -a' "$SCRIPT_DIR/init.sh" || \
	fail "init stage does not update OpenWrt feeds"
grep -Fq 'make defconfig' "$SCRIPT_DIR/init.sh" || \
	fail "init stage does not generate the OpenWrt configuration"
grep -Fq 'make download' "$SCRIPT_DIR/init.sh" || \
	fail "init stage does not download OpenWrt source archives"

# A patch file's own context lines intentionally begin with one space.  When a
# new patch is itself shown in a repository diff, Git's outer whitespace check
# misreads those context prefixes as indentation.  Validate project sources
# here and validate patch payloads structurally below.
git -C "$PROJECT_DIR" diff --check -- . \
	':(exclude,glob)patches/**/*.patch'
git -C "$PROJECT_DIR" diff --cached --check -- . \
	':(exclude,glob)patches/**/*.patch'

openwrt_patch="$PROJECT_DIR/patches/openwrt/0001-tb-rk3399prod-board-support.patch"
kernel_patch_dir="$PROJECT_DIR/patches/kernel"
typec_phy_patch="$kernel_patch_dir/144-phy-rockchip-typec-orientation-switch.patch"
typec_dwc_patch="$kernel_patch_dir/145-usb-dwc3-rk3399-typec-runtime-pm.patch"
assert_file "$openwrt_patch"
assert_file "$typec_phy_patch"
assert_file "$typec_dwc_patch"
assert_file "$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dts"
assert_file "$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi"
assert_file "$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning"
assert_file "$PROJECT_DIR/rootfs/etc/hotplug.d/iface/90-tb-net-tuning"
assert_file "$PROJECT_DIR/rootfs/etc/uci-defaults/99-tb-network-offload"
assert_file "$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag"
assert_file "$PROJECT_DIR/configs/openwrt.config"
assert_file "$PROJECT_DIR/configs/feeds.conf"
assert_file "$PROJECT_DIR/boot/boot.cmd"
assert_file "$PROJECT_DIR/scripts/clean.sh"
assert_file "$PROJECT_DIR/scripts/make-openwrt-image.sh"
assert_file "$PROJECT_DIR/scripts/reset.sh"
assert_file "$PROJECT_DIR/scripts/sync-openwrt-rootfs.sh"
assert_file "$PROJECT_DIR/scripts/sync-openwrt-kernel-patches.sh"
assert_file "$PROJECT_DIR/scripts/verify-openwrt-image.sh"
assert_file "$PROJECT_DIR/docs/BOOT-CHAIN.md"
assert_file "$PROJECT_DIR/docs/HDMI-CONSOLE.md"
assert_file "$PROJECT_DIR/docs/NETWORK-PERFORMANCE.md"
assert_file "$PROJECT_DIR/docs/USB-TYPE-C.md"

grep -Fq '$(filter -j%,$(MAKEFLAGS))' "$PROJECT_DIR/Makefile" || \
	fail "Makefile must derive parallelism from GNU Make -j"
for file in "$PROJECT_DIR/Makefile" "$PROJECT_DIR/README.md" \
	"$PROJECT_DIR/docs/BUILD.md"; do
	if grep -Eq 'make .*\b(J|JOBS)=[0-9]' "$file"; then
		fail "non-standard parallelism variable remains in $file"
	fi
done
grep -Fq 'bash scripts/clean.sh' "$PROJECT_DIR/Makefile" || \
	fail "Makefile clean target is missing"
grep -Fq 'bash scripts/reset.sh' "$PROJECT_DIR/Makefile" || \
	fail "Makefile reset target is missing"
grep -Fq 'mark_managed_dir "$OUT_DIR" out' "$PROJECT_DIR/scripts/build.sh" || \
	fail "custom output directories are not marked as project-managed"
grep -Fq 'mark_managed_dir "$DIST_DIR" dist' \
	"$PROJECT_DIR/scripts/package.sh" || \
	fail "custom distribution directories are not marked as project-managed"
grep -Fq '"$SCRIPT_DIR/make-openwrt-image.sh"' \
	"$PROJECT_DIR/scripts/build.sh" || \
	fail "OpenWrt deployment image is not assembled by the build stage"
grep -Fq '"$OUT_DIR/openwrt/openwrt.img"' \
	"$PROJECT_DIR/scripts/package.sh" || \
	fail "release package does not require the combined OpenWrt image"
for layout in \
	'SECTOR_SIZE=512' \
	'UBOOT_LBA=$((0x2000))' \
	'TRUST_LBA=$((0x4000))' \
	'BOOT_LINUX_LBA=$((0x6000))' \
	'ROOTFS_LBA=$((0x36000))' \
	'BOOT_LINUX_IMAGE_SIZE=$((64 * 1024 * 1024))' \
	'ROOTFS_IMAGE_SIZE=$((128 * 1024 * 1024))'; do
	grep -Fqx "$layout" "$PROJECT_DIR/scripts/lib.sh" || \
		fail "eMMC image layout setting is missing: $layout"
done
[ "$OPENWRT_ROOTFS_OFFSET" -eq 100663296 ] || \
	fail "combined image rootfs offset is not exactly 96 MiB"
[ "$OPENWRT_IMAGE_SIZE" -eq 234881024 ] || \
	fail "combined OpenWrt image is not exactly 224 MiB"
[ $((BOOT_LINUX_LBA + OPENWRT_ROOTFS_OFFSET / SECTOR_SIZE)) \
	-eq "$ROOTFS_LBA" ] || \
	fail "combined image rootfs does not land at the vendor rootfs LBA"
if grep -Eq 'git[[:space:]].*(reset|clean)' "$PROJECT_DIR/scripts/clean.sh"; then
	fail "ordinary clean must not mutate Git worktrees"
fi
grep -Fq 'git -C "$repo" reset --hard "$expected_commit"' \
	"$PROJECT_DIR/scripts/reset.sh" || \
	fail "reset does not reset verified repositories"
grep -Fq 'git -C "$repo" clean -fd' \
	"$PROJECT_DIR/scripts/reset.sh" || \
	fail "reset does not remove untracked source changes"

[ "$(find "$PROJECT_DIR/patches/openwrt" -mindepth 1 -maxdepth 1 \
	-type d | wc -l)" -eq 0 ] || \
	fail "OpenWrt patch directory must not contain subdirectories"
[ "$(find "$PROJECT_DIR/patches/openwrt" -maxdepth 1 -type f \
	-name '*.patch' | wc -l)" -eq 1 ] || \
	fail "exactly one current OpenWrt patch is required"
git apply --numstat "$openwrt_patch" >/dev/null

[ "$(find "$kernel_patch_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ] || \
	fail "kernel patch directory must not contain subdirectories"
[ "$(find "$kernel_patch_dir" -maxdepth 1 -type f -name '*.patch' | wc -l)" -eq 2 ] || \
	fail "exactly two canonical Type-C kernel patches are required"
for patch in "$kernel_patch_dir"/*.patch; do
	git apply --numstat "$patch" >/dev/null
done

[ "$(find "$PROJECT_DIR/patches/u-boot" -mindepth 1 -maxdepth 1 \
	-type d | wc -l)" -eq 0 ] || \
	fail "U-Boot patch directory must not contain subdirectories"
[ "$(find "$PROJECT_DIR/patches/u-boot" -maxdepth 1 -type f \
	-name '*.patch' | wc -l)" -eq 2 ] || \
	fail "exactly two current U-Boot patches are required"
for patch in "$PROJECT_DIR"/patches/u-boot/*.patch; do
	git apply --numstat "$patch" >/dev/null
done

if grep -Eq '^diff --git a/.*rk3399pro-toybrick-prod\.dtsi? ' \
	"$openwrt_patch"; then
	fail "canonical board DTS files must not be duplicated in patches"
fi

assert_exact_line "$PROJECT_DIR/configs/openwrt.config" \
	'CONFIG_TARGET_rockchip_armv8_DEVICE_toybrick_tb-rk3399prod=y'
assert_exact_line "$PROJECT_DIR/configs/openwrt.config" \
	'CONFIG_TARGET_ROOTFS_SQUASHFS=y'
assert_exact_line "$PROJECT_DIR/configs/openwrt.config" \
	'CONFIG_TARGET_ROOTFS_INITRAMFS=y'

[ "$(wc -l < "$PROJECT_DIR/configs/feeds.conf")" -eq 1 ] || \
	fail "configs/feeds.conf must contain exactly one required feed"
while IFS= read -r feed; do
	printf '%s\n' "$feed" | grep -Eq \
		'^src-git [a-z0-9_-]+ https://[^[:space:]]+\^[0-9a-f]{40}$' || \
		fail "feed is not pinned to an exact commit: $feed"
done < "$PROJECT_DIR/configs/feeds.conf"
grep -Eq '^src-git packages ' "$PROJECT_DIR/configs/feeds.conf" || \
	fail "the required OpenWrt packages feed is missing"

grep -Fq 'setenv fitaddr 0x10000000' "$PROJECT_DIR/boot/boot.cmd" || \
	fail "boot script FIT address is missing or unexpected"
grep -Fq 'console=tty0 console=ttyS2,1500000n8' "$PROJECT_DIR/boot/boot.cmd" || \
	fail "boot script HDMI/serial dual console arguments are missing"
grep -Fq 'root=PARTLABEL=rootfs' "$PROJECT_DIR/boot/boot.cmd" || \
	fail "boot script persistent rootfs argument is missing"
if grep -Eq 'kmod-rtw88|rtl8822|mac80211|cfg80211' "$openwrt_patch"; then
	fail "unused wireless drivers or firmware remain in the device profile"
fi
for package in blkid blockdev fdisk fstrim lsblk lscpu mount-utils wdctl \
	ca-bundle curl htop jq lsof strace ip-full tcpdump-mini kmod-fs-exfat \
	kmod-fs-vfat; do
	grep -Eq "[[:space:]]$package([[:space:]\\\\]|$)" "$openwrt_patch" || \
		fail "required maintenance package is missing: $package"
done
grep -Eq '[[:space:]]-ip-tiny([[:space:]\\]|$)' "$openwrt_patch" || \
	fail "ip-tiny is not removed when ip-full is selected"
grep -Eq '[[:space:]]ss([[:space:]\\]|$)' "$openwrt_patch" || \
	fail "socket diagnostics utility is missing: ss"
grep -Fq '143-mmc-sdhci-of-arasan-disable-rk3399-cqe.patch' \
	"$openwrt_patch" || \
	fail "RK3399 eMMC CQE reliability patch is missing"
grep -Fq 'SDHCI_QUIRK_BROKEN_CQE' "$openwrt_patch" || \
	fail "RK3399 eMMC CQE is not disabled with the standard SDHCI quirk"
grep -Fq 'tcphy_set_orientation' "$typec_phy_patch" || \
	fail "RK3399 Type-C orientation callback is missing"
grep -Fq 'tcphy->new_mode = MODE_DISCONNECT;' "$typec_phy_patch" || \
	fail "RK3399 Type-C detach state is not recorded by the PHY"
grep -Fq 'return tcphy->new_mode;' "$typec_phy_patch" || \
	fail "RK3399 Type-C PHY does not consume the TCPM mode"
grep -Fq '#define POWER_ON_TRIES' "$typec_phy_patch" || \
	fail "RK3399 Type-C PHY power-on retries are missing"
grep -Fq 'rk3399-typec: PIPE status read failed:' "$typec_phy_patch" || \
	fail "RK3399 Type-C PIPE regmap read errors are not observable"
grep -Fq 'rk3399-typec: USB3 host GRF enable failed:' "$typec_phy_patch" || \
	fail "RK3399 Type-C GRF programming errors are not observable"
grep -Fq 'pipe_read_ret=%d' "$typec_phy_patch" || \
	fail "RK3399 Type-C final PHY failure log lacks the PIPE read status"
grep -Fq 'mode = 0;' "$typec_dwc_patch" || \
	fail "RK3399 USB_ROLE_NONE is not represented as a true idle role"
grep -Fq 'if (!dwc->rk3399_typec)' "$typec_dwc_patch" || \
	fail "RK3399 Type-C role switch still schedules an initial non-idle role"
grep -Fq 'role_pm_held' "$typec_dwc_patch" || \
	fail "RK3399 Type-C active-role runtime-PM hold is missing"
grep -Fq 'pm_runtime_put_noidle(dwc->dev);' "$typec_dwc_patch" || \
	fail "RK3399 Type-C detach does not release its attached-role PM hold"
grep -Fq 'pm_usage=%d' "$typec_dwc_patch" || \
	fail "RK3399 Type-C PM reference counts are absent from transition logs"
grep -Fq 'pm_runtime_put_sync_suspend(dwc->dev);' "$typec_dwc_patch" || \
	fail "RK3399 Type-C detach does not synchronously suspend DWC3"
grep -Fq 'pm_runtime_set_autosuspend_delay(dev, 100);' "$typec_dwc_patch" || \
	fail "RK3399 DWC3 detach delay is not bounded"
grep -Fq 'pm_runtime_put_sync_suspend(dev);' "$typec_dwc_patch" || \
	fail "RK3399 DWC3 is not suspended while Type-C is unattached"
grep -Fq 'dwc3_core_init_for_resume(dwc);' "$typec_dwc_patch" || \
	fail "RK3399 DWC3/PHY resume lifecycle is missing"
grep -Fq 'drivers/usb/dwc3/dwc3-of-simple.c' "$typec_dwc_patch" || \
	fail "RK3399 parent DWC3 glue reset lifecycle is missing"
grep -Fq 'of_property_read_bool(child, "usb-role-switch");' \
	"$typec_dwc_patch" || \
	fail "RK3399 runtime reset is not restricted to the Type-C role-switch controller"
grep -Fq 'reset_control_assert(simple->resets);' "$typec_dwc_patch" || \
	fail "RK3399 usb3-otg reset assert is missing before PHY resume"
grep -Fq 'udelay(1);' "$typec_dwc_patch" || \
	fail "RK3399 usb3-otg reset pulse width is missing"
grep -Fq 'usleep_range(10000, 11000);' "$typec_dwc_patch" || \
	fail "Toybrick stable 4.4 PHY settle time is missing before xHCI probe"
grep -Fq 'reset_control_deassert(simple->resets);' "$typec_dwc_patch" || \
	fail "RK3399 usb3-otg reset deassert is missing before PHY resume"
grep -Fq 'rockchip-toybrick/kernel/blob/a80be5749ac552821967eff313df53f9e0cd1e01/drivers/usb/dwc3/dwc3-rockchip.c' \
	"$typec_dwc_patch" || \
	fail "Toybrick stable 4.4 DWC3 behavior is not pinned as the board baseline"
for marker in \
	'rk3399-typec: role transition' \
	'rk3399-typec: USB3 PHY power-on failed' \
	'rk3399-typec: wait PMA ready timeout' \
	'rk3399-typec: wait PIPE ready timeout' \
	'rk3399-typec: usb3-otg reset pulse complete'; do
	grep -Fq "$marker" "$kernel_patch_dir"/*.patch || \
		fail "Type-C diagnostic marker is missing: $marker"
done
grep -Fq '+CONFIG_DEBUG_FS=y' "$openwrt_patch" || \
	fail "TCPM/FUSB302 debug rings are unavailable without CONFIG_DEBUG_FS"
grep -Fq '/sys/kernel/debug/usb/fusb302-*/log' \
	"$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag" || \
	fail "Type-C diagnostic tool does not collect the FUSB302 event ring"
grep -Fq '/sys/kernel/debug/usb/tcpm-*/log' \
	"$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag" || \
	fail "Type-C diagnostic tool does not collect the TCPM event ring"
grep -Fq 'event rings before test' \
	"$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag" || \
	fail "Type-C diagnostic tool does not preserve pre-test controller events"
grep -Fq 'tb-typec-diag: %s' \
	"$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag" || \
	fail "Type-C diagnostic tool does not place test boundaries in dmesg"
if grep -Fq 'tcphy_reinit_usb3' "$kernel_patch_dir"/*.patch; then
	fail "unsafe live Type-C PHY reinitialization remains"
fi
if grep -Eq 'rockchip,usb3-host-only|usb3_powered|USB3 host switched' \
	"$kernel_patch_dir"/*.patch; then
	fail "unsupported fixed-host Type-C lane switching remains"
fi
grep -Fq '+CONFIG_USB_DWC3_DUAL_ROLE=y' "$openwrt_patch" || \
	fail "DWC3 dual-role lifecycle is missing"
grep -Fq '+CONFIG_USB_GADGET=y' "$openwrt_patch" || \
	fail "DWC3 dual-role build dependency USB_GADGET is missing"
if grep -Fq '+CONFIG_USB_DWC3_HOST=y' "$openwrt_patch"; then
	fail "Type-C DWC3 must not use the static host-only lifecycle"
fi
grep -Fq 'Mini-PCIe 插座只接 USB2' \
	"$PROJECT_DIR/docs/HARDWARE-REFERENCE.md" || \
	fail "Mini-PCIe USB-only wiring constraint is not documented"
grep -Fq 'kmod-usb-hid' "$openwrt_patch" || \
	fail "USB HID support for the HDMI console is missing from the device profile"
grep -Fq 'GMAC_IRQ_CPU="4"' \
	"$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning" || \
	fail "GMAC IRQ is not assigned to the first Cortex-A72"
grep -Fqx 'START=99' \
	"$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning" || \
	fail "GMAC IRQ fallback service does not run after network startup"
grep -Fq '/etc/init.d/tb-net-tuning start' \
	"$PROJECT_DIR/rootfs/etc/hotplug.d/iface/90-tb-net-tuning" || \
	fail "GMAC IRQ affinity is not restored by the interface hotplug hook"
grep -Fq '[ "$ACTION" = "ifup" ] || exit 0' \
	"$PROJECT_DIR/rootfs/etc/hotplug.d/iface/90-tb-net-tuning" || \
	fail "GMAC IRQ hotplug hook is not restricted to interface-up events"
grep -Fq '[ "$INTERFACE" = "lan" ] || exit 0' \
	"$PROJECT_DIR/rootfs/etc/hotplug.d/iface/90-tb-net-tuning" || \
	fail "GMAC IRQ hotplug hook is not restricted to the LAN interface"
grep -Fq "flow_offloading='1'" \
	"$PROJECT_DIR/rootfs/etc/uci-defaults/99-tb-network-offload" || \
	fail "software flow offload is not enabled by default"
grep -Fq "flow_offloading_hw='0'" \
	"$PROJECT_DIR/rootfs/etc/uci-defaults/99-tb-network-offload" || \
	fail "unsupported hardware flow offload must remain disabled"
for config in \
	'CONFIG_CPU_FREQ_THERMAL=y' \
	'CONFIG_DRM=y' \
	'CONFIG_DRM_FBDEV_EMULATION=y' \
	'CONFIG_DRM_ROCKCHIP=y' \
	'CONFIG_FRAMEBUFFER_CONSOLE=y' \
	'CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y' \
	'# CONFIG_FRAMEBUFFER_CONSOLE_ROTATION is not set' \
	'CONFIG_PHY_ROCKCHIP_INNO_HDMI=y' \
	'# CONFIG_ROCKCHIP_ANALOGIX_DP is not set' \
	'# CONFIG_ROCKCHIP_CDN_DP is not set' \
	'CONFIG_ROCKCHIP_DW_HDMI=y' \
	'# CONFIG_ROCKCHIP_DW_MIPI_DSI is not set' \
	'# CONFIG_ROCKCHIP_INNO_HDMI is not set' \
	'# CONFIG_ROCKCHIP_LVDS is not set' \
	'# CONFIG_ROCKCHIP_RGB is not set' \
	'# CONFIG_ROCKCHIP_RK3066_HDMI is not set' \
	'CONFIG_ROCKCHIP_VOP=y' \
	'# CONFIG_ROCKCHIP_VOP2 is not set'; do
	grep -Fq "$config" "$openwrt_patch" || \
		fail "HDMI console kernel setting is missing: $config"
done
for obsolete_config in \
	'CONFIG_DRM_KMS_FB_HELPER' \
	'CONFIG_FB=y' \
	'CONFIG_FB_CORE=y' \
	'CONFIG_FB_DEVICE=y' \
	'CONFIG_FONTS=y'; do
	if grep -Fq "$obsolete_config" "$openwrt_patch"; then
		fail "obsolete or unnecessary HDMI kernel setting remains: $obsolete_config"
	fi
done
grep -Fq 'tty1::askfirst:/usr/libexec/login.sh' "$openwrt_patch" || \
	fail "HDMI tty1 login entry is missing"
for dts_setting in \
	'&{/watchdog@ff848000} {' \
	'snps,watchdog-tops = <0x00010000 0x00020000 0x00040000 0x00080000' \
	'&hdmi {' \
	'avdd-0v9-supply = <&vcca_0v9>;' \
	'avdd-1v8-supply = <&vcca_1v8>;' \
	'ddc-i2c-bus = <&i2c3>;' \
	'&i2c3 {' \
	'&vopb {' \
	'&vopb_mmu {'; do
	grep -Fq "$dts_setting" \
		"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi" || \
		fail "HDMI device-tree setting is missing: $dts_setting"
done
for typec_setting in \
	'&i2c8 {' \
	'compatible = "fcs,fusb302";' \
	'interrupts = <RK_PA2 IRQ_TYPE_LEVEL_LOW>;' \
	'gpio = <&gpio0 RK_PA1 GPIO_ACTIVE_LOW>;' \
	'data-role = "host";' \
	'power-role = "source";' \
	'PDO_FIXED(5000, 1500, PDO_FIXED_USB_COMM)' \
	'&tcphy0 {' \
	'&tcphy0_usb3 {' \
	'orientation-switch;' \
	'&usbdrd3_0 {' \
	'&usbdrd_dwc3_0 {' \
	'dr_mode = "otg";' \
	'usb-role-switch;' \
	'usbc0_role_sw: endpoint {' \
	'dwc3_0_role_switch: endpoint {' \
	'remote-endpoint = <&tcphy0_orientation_switch>;' \
	'remote-endpoint = <&dwc3_0_role_switch>;' \
	'remote-endpoint = <&usbc0_orien_sw>;' \
	'remote-endpoint = <&usbc0_role_sw>;'; do
	grep -Fq "$typec_setting" \
		"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi" || \
		fail "USB Type-C device-tree setting is missing: $typec_setting"
done
for vendor_typec_setting in \
	'compatible = "fairchild,fusb302";' \
	'vbus-5v-gpios' \
	'extcon = <&fusb0>' \
	'rockchip,usb3-host-only' \
	'u2phy0_typec_hs' \
	'usbc0_hs' \
	'tcphy0_typec_ss' \
	'usbc0_ss'; do
	if grep -Fq "$vendor_typec_setting" \
		"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi"; then
		fail "obsolete vendor Type-C binding remains: $vendor_typec_setting"
	fi
done

if [ -d "$WORK_DIR/openwrt/.git" ]; then
	[ "$(git -C "$WORK_DIR/openwrt" rev-parse HEAD)" = "$OPENWRT_COMMIT" ] || \
		fail "OpenWrt checkout is not at the pinned commit"
	git -C "$WORK_DIR/openwrt" apply --reverse --check "$openwrt_patch"
	cmp -s "$PROJECT_DIR/configs/feeds.conf" \
		"$WORK_DIR/openwrt/feeds.conf" || \
		fail "OpenWrt worktree feeds.conf differs from the canonical file"
	feeds_match_config "$WORK_DIR/openwrt" "$PROJECT_DIR/configs/feeds.conf" || \
		fail "OpenWrt feed checkout differs from the pinned configuration"
	[ -f "$WORK_DIR/openwrt/.config" ] || \
		fail "OpenWrt configuration has not been initialized"
	grep -Fqx 'CONFIG_TARGET_rockchip_armv8_DEVICE_toybrick_tb-rk3399prod=y' \
		"$WORK_DIR/openwrt/.config" || \
		fail "OpenWrt worktree does not select the board profile"

	rockchip_makefile="$WORK_DIR/openwrt/target/linux/rockchip/Makefile"
	kernel_patchver=$(sed -n \
		's/^[[:space:]]*KERNEL_PATCHVER[[:space:]]*:=[[:space:]]*//p' \
		"$rockchip_makefile")
	kernel_details="$WORK_DIR/openwrt/target/linux/generic/kernel-$kernel_patchver"
	kernel_suffix=$(sed -n \
		"s/^LINUX_VERSION-$kernel_patchver[[:space:]]*=[[:space:]]*//p" \
		"$kernel_details")
	[ "$kernel_patchver$kernel_suffix" = "$LINUX_VERSION" ] || \
		fail "OpenWrt Linux version differs from the pinned project baseline"
	rockchip_kernel_config="$WORK_DIR/openwrt/target/linux/rockchip/armv8/config-$kernel_patchver"
	for required_kernel_config in \
		'CONFIG_DEBUG_FS=y' \
		'CONFIG_PHY_ROCKCHIP_TYPEC=y' \
		'CONFIG_REGULATOR_FIXED_VOLTAGE=y' \
		'CONFIG_TYPEC=y' \
		'CONFIG_TYPEC_FUSB302=y' \
		'CONFIG_TYPEC_TCPM=y' \
		'CONFIG_USB_DWC3=y' \
		'CONFIG_USB_DWC3_DUAL_ROLE=y' \
		'CONFIG_USB_GADGET=y' \
		'CONFIG_USB_ROLE_SWITCH=y'; do
		grep -Fqx "$required_kernel_config" "$rockchip_kernel_config" || \
			fail "required Type-C kernel setting is missing: $required_kernel_config"
	done
	if grep -Fqx 'CONFIG_USB_DWC3_HOST=y' "$rockchip_kernel_config"; then
		fail "Type-C DWC3 still uses static host-only mode"
	fi
	dts_dest="$WORK_DIR/openwrt/target/linux/rockchip/files-$kernel_patchver/arch/arm64/boot/dts/rockchip"
	for name in rk3399pro-toybrick-prod.dts rk3399pro-toybrick-prod.dtsi; do
		cmp -s "$PROJECT_DIR/dts/$name" "$dts_dest/$name" || \
			fail "OpenWrt worktree DTS is not synchronized: $name"
	done
	kernel_patch_dest="$WORK_DIR/openwrt/target/linux/rockchip/patches-$kernel_patchver"
	for source_patch in "$kernel_patch_dir"/*.patch; do
		name=${source_patch##*/}
		cmp -s "$source_patch" "$kernel_patch_dest/$name" || \
			fail "OpenWrt worktree kernel patch is not synchronized: $name"
	done
	rootfs_dest="$WORK_DIR/openwrt/target/linux/rockchip/base-files"
	while IFS= read -r -d '' source_file; do
		relative_path=${source_file#"$PROJECT_DIR/rootfs"/}
		cmp -s "$source_file" "$rootfs_dest/$relative_path" || \
			fail "OpenWrt worktree rootfs is not synchronized: $relative_path"
	done < <(find "$PROJECT_DIR/rootfs" -type f -print0 | sort -z)
fi

if [ -d "$WORK_DIR/u-boot/.git" ]; then
	[ "$(git -C "$WORK_DIR/u-boot" rev-parse HEAD)" = "$UBOOT_COMMIT" ] || \
		fail "U-Boot checkout is not at the pinned commit"
	for patch in "$PROJECT_DIR"/patches/u-boot/*.patch; do
		git -C "$WORK_DIR/u-boot" apply --reverse --check "$patch"
	done
fi

echo "Project checks passed"
