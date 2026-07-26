#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 1 ] || fail "usage: $0 OPENWRT_IMG"
[ -f "$1" ] || fail "OpenWrt image not found: $1"

image=$(readlink -f -- "$1")
[ "$(stat -c '%s' "$image")" -eq "$OPENWRT_IMAGE_SIZE" ] || \
	fail "openwrt.img is not exactly $OPENWRT_IMAGE_SIZE bytes"

e2fsck -fn "$image" >/dev/null 2>&1 || \
	fail "openwrt.img boot_linux filesystem failed e2fsck"
debugfs -R 'stat /boot.scr' "$image" 2>&1 | \
	grep -q '^Inode:' || fail "openwrt.img is missing /boot.scr"
debugfs -R 'stat /openwrt.itb' "$image" 2>&1 | \
	grep -q '^Inode:' || fail "openwrt.img is missing /openwrt.itb"

rootfs_magic=$(dd if="$image" bs=1 skip="$OPENWRT_ROOTFS_OFFSET" \
	count=4 status=none | od -An -tx1 | tr -d ' \n')
[ "$rootfs_magic" = 68737173 ] || \
	fail "openwrt.img has no SquashFS at byte $OPENWRT_ROOTFS_OFFSET"

echo "Verified OpenWrt deployment image: $image"
