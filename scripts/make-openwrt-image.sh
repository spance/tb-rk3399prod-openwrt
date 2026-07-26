#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 3 ] || \
	fail "usage: $0 BOOT_LINUX_IMG ROOTFS_IMG OUTPUT_IMG"
[ -f "$1" ] || fail "boot_linux image not found: $1"
[ -f "$2" ] || fail "rootfs image not found: $2"

boot_image=$(readlink -f -- "$1")
rootfs_image=$(readlink -f -- "$2")
output_image=$(readlink -m -- "$3")
[ "$output_image" != "$boot_image" ] || fail "output must differ from boot image"
[ "$output_image" != "$rootfs_image" ] || fail "output must differ from rootfs image"

[ "$(stat -c '%s' "$boot_image")" -eq "$BOOT_LINUX_IMAGE_SIZE" ] || \
	fail "boot_linux.img is not exactly $BOOT_LINUX_IMAGE_SIZE bytes"
[ "$(stat -c '%s' "$rootfs_image")" -eq "$ROOTFS_IMAGE_SIZE" ] || \
	fail "rootfs.img is not exactly $ROOTFS_IMAGE_SIZE bytes"
[ "$(od -An -tx1 -N4 "$rootfs_image" | tr -d ' \n')" = 68737173 ] || \
	fail "rootfs.img does not start with a SquashFS superblock"
[ $((OPENWRT_ROOTFS_OFFSET % (1024 * 1024))) -eq 0 ] || \
	fail "rootfs offset is not MiB-aligned"
[ "$BOOT_LINUX_IMAGE_SIZE" -le "$OPENWRT_ROOTFS_OFFSET" ] || \
	fail "boot_linux.img exceeds its partition boundary"

output_dir=$(dirname -- "$output_image")
mkdir -p "$output_dir"
image_tmp=$(mktemp "$output_dir/.openwrt.img.XXXXXX")
cleanup()
{
	[ -z "$image_tmp" ] || rm -f -- "$image_tmp"
}
trap cleanup EXIT

truncate -s "$OPENWRT_IMAGE_SIZE" "$image_tmp"
dd if="$boot_image" of="$image_tmp" bs=1M conv=notrunc,sparse status=none
dd if="$rootfs_image" of="$image_tmp" bs=1M \
	seek=$((OPENWRT_ROOTFS_OFFSET / (1024 * 1024))) \
	conv=notrunc,sparse status=none

cmp -n "$BOOT_LINUX_IMAGE_SIZE" "$image_tmp" "$boot_image"
gap_size=$((OPENWRT_ROOTFS_OFFSET - BOOT_LINUX_IMAGE_SIZE))
cmp -n "$gap_size" "$image_tmp" /dev/zero "$BOOT_LINUX_IMAGE_SIZE" 0
cmp -n "$ROOTFS_IMAGE_SIZE" "$image_tmp" "$rootfs_image" \
	"$OPENWRT_ROOTFS_OFFSET" 0
bash "$SCRIPT_DIR/verify-openwrt-image.sh" "$image_tmp" >/dev/null

mv -f -- "$image_tmp" "$output_image"
image_tmp=
echo "OpenWrt deployment image: $output_image"
echo "  flash LBA: 0x$(printf '%x' "$BOOT_LINUX_LBA")"
echo "  rootfs byte offset: $OPENWRT_ROOTFS_OFFSET"
