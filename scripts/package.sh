#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

bash "$SCRIPT_DIR/check-env.sh"
[ "$#" -eq 0 ] || fail "usage: $0"

for required in \
	"$OUT_DIR/uboot/uboot.img" \
	"$OUT_DIR/openwrt/openwrt.img" \
	"$OUT_DIR/openwrt/kmod-compat.buildinfo"; do
	[ -e "$required" ] || fail "missing build output: $required; run make all first"
done
[ "$(stat -c '%s' "$OUT_DIR/uboot/uboot.img")" -eq 4194304 ] || \
	fail "uboot.img is not exactly 4 MiB"
bash "$SCRIPT_DIR/verify-openwrt-image.sh" \
	"$OUT_DIR/openwrt/openwrt.img" >/dev/null
compat_info="$OUT_DIR/openwrt/kmod-compat.buildinfo"
for expected in \
	"openwrt_commit=$OPENWRT_COMMIT" \
	"linux_version=$LINUX_VERSION" \
	"linux_release=$TB_KMOD_LINUX_RELEASE" \
	"native_kconfig_abi=$TB_KMOD_NATIVE_ABI" \
	"package_kmod_abi=$TB_KMOD_OFFICIAL_ABI" \
	"official_kmod_repository=$TB_KMOD_REPOSITORY"; do
	[ "$(grep -Fxc -- "$expected" "$compat_info")" -eq 1 ] || \
		fail "stale or inconsistent OpenWrt kmod compatibility record: $expected"
done

mark_managed_dir "$DIST_DIR" dist
stage=$(mktemp -d "$DIST_DIR/.stage.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT

mkdir -p "$stage/firmware"
cp -- "$OUT_DIR/uboot/uboot.img" "$stage/firmware/uboot.img"
cp --sparse=always -- "$OUT_DIR/openwrt/openwrt.img" \
	"$stage/firmware/openwrt.img"
chmod 0644 "$stage/firmware/uboot.img" "$stage/firmware/openwrt.img"

printf '%s\n' \
	"Board: TB-RK3399ProD" \
	"U-Boot: $UBOOT_COMMIT" \
	"rkbin: $RKBIN_COMMIT" \
	"toolchain: $TOOLCHAIN_COMMIT" \
	"OpenWrt: $OPENWRT_TAG ($OPENWRT_COMMIT)" \
	"Linux: $LINUX_VERSION" \
	"Native kernel Kconfig ABI: $TB_KMOD_NATIVE_ABI" \
	"Package-visible kmod ABI: $TB_KMOD_OFFICIAL_ABI" \
	"Pinned official kmod repository: $TB_KMOD_REPOSITORY" \
	"Official kmod scope: audited modules outside the patched Type-C/DWC3/Rockchip PHY/MMC/DRM paths" \
	"uboot.img: flash at LBA 0x$(printf '%x' "$UBOOT_LBA")" \
	"openwrt.img: flash at LBA 0x$(printf '%x' "$BOOT_LINUX_LBA")" \
	"openwrt.img rootfs: byte offset $OPENWRT_ROOTFS_OFFSET, eMMC LBA 0x$(printf '%x' "$ROOTFS_LBA")" \
	> "$stage/BUILD-METADATA.txt"

(
	cd "$stage"
	find firmware -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

archive="$DIST_DIR/tb-rk3399prod-openwrt-$OPENWRT_VERSION.tar.gz"
tar --sparse --sparse-version=1.0 --sort=name \
	--mtime="@${SOURCE_DATE_EPOCH:-0}" \
	--owner=0 --group=0 --numeric-owner -C "$stage" -czf "$archive.tmp" .
mv -f "$archive.tmp" "$archive"
(
	cd "$DIST_DIR"
	sha256sum "$(basename -- "$archive")" > "$(basename -- "$archive").sha256"
)

echo "Release package: $archive"
