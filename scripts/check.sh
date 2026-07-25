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

git -C "$PROJECT_DIR" diff --check
git -C "$PROJECT_DIR" diff --cached --check

openwrt_patch="$PROJECT_DIR/patches/openwrt/0001-tb-rk3399prod-board-support.patch"
assert_file "$openwrt_patch"
assert_file "$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dts"
assert_file "$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi"
assert_file "$PROJECT_DIR/configs/openwrt.config"
assert_file "$PROJECT_DIR/configs/feeds.conf"
assert_file "$PROJECT_DIR/boot/boot.cmd"
assert_file "$PROJECT_DIR/scripts/clean.sh"
assert_file "$PROJECT_DIR/scripts/reset.sh"
assert_file "$PROJECT_DIR/docs/BOOT-CHAIN.md"
assert_file "$PROJECT_DIR/docs/HDMI-CONSOLE.md"

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
grep -Fq 'kmod-rtw88-8822ce' "$openwrt_patch" || \
	fail "RTL8822CE PCIe wireless driver is missing from the device profile"
grep -Fq 'kmod-usb-hid' "$openwrt_patch" || \
	fail "USB HID support for the HDMI console is missing from the device profile"
for config in \
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
	dts_dest="$WORK_DIR/openwrt/target/linux/rockchip/files-$kernel_patchver/arch/arm64/boot/dts/rockchip"
	for name in rk3399pro-toybrick-prod.dts rk3399pro-toybrick-prod.dtsi; do
		cmp -s "$PROJECT_DIR/dts/$name" "$dts_dest/$name" || \
			fail "OpenWrt worktree DTS is not synchronized: $name"
	done
fi

if [ -d "$WORK_DIR/u-boot/.git" ]; then
	[ "$(git -C "$WORK_DIR/u-boot" rev-parse HEAD)" = "$UBOOT_COMMIT" ] || \
		fail "U-Boot checkout is not at the pinned commit"
	for patch in "$PROJECT_DIR"/patches/u-boot/*.patch; do
		git -C "$WORK_DIR/u-boot" apply --reverse --check "$patch"
	done
fi

echo "Project checks passed"
