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

git -C "$PROJECT_DIR" diff --check
git -C "$PROJECT_DIR" diff --cached --check

openwrt_patch="$PROJECT_DIR/patches/openwrt/0001-tb-rk3399prod-board-support.patch"
assert_file "$openwrt_patch"
assert_file "$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dts"
assert_file "$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi"
assert_file "$PROJECT_DIR/configs/openwrt.config"
assert_file "$PROJECT_DIR/configs/feeds.conf"
assert_file "$PROJECT_DIR/boot/boot.cmd"

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

[ "$(wc -l < "$PROJECT_DIR/configs/feeds.conf")" -eq 5 ] || \
	fail "configs/feeds.conf must contain exactly five pinned feeds"
while IFS= read -r feed; do
	printf '%s\n' "$feed" | grep -Eq \
		'^src-git [a-z0-9_-]+ https://[^[:space:]]+\^[0-9a-f]{40}$' || \
		fail "feed is not pinned to an exact commit: $feed"
done < "$PROJECT_DIR/configs/feeds.conf"

grep -Fq 'setenv fitaddr 0x10000000' "$PROJECT_DIR/boot/boot.cmd" || \
	fail "boot script FIT address is missing or unexpected"
grep -Fq 'root=PARTLABEL=rootfs' "$PROJECT_DIR/boot/boot.cmd" || \
	fail "boot script persistent rootfs argument is missing"

if [ -d "$WORK_DIR/openwrt/.git" ]; then
	[ "$(git -C "$WORK_DIR/openwrt" rev-parse HEAD)" = "$OPENWRT_COMMIT" ] || \
		fail "OpenWrt checkout is not at the pinned commit"
	git -C "$WORK_DIR/openwrt" apply --reverse --check "$openwrt_patch"
	cmp -s "$PROJECT_DIR/configs/feeds.conf" \
		"$WORK_DIR/openwrt/feeds.conf" || \
		fail "OpenWrt worktree feeds.conf differs from the canonical file"

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
