#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 3 ] || \
	fail "usage: $0 OPENWRT_FIT MKIMAGE OUTPUT_IMG"

[ -f "$1" ] || fail "OpenWrt FIT not found: $1"
[ -x "$2" ] || fail "mkimage is not executable: $2"

fit_image=$(readlink -f -- "$1")
mkimage=$(readlink -f -- "$2")
boot_image=$(readlink -m -- "$3")
boot_dir=$(dirname -- "$boot_image")
build_epoch=${SOURCE_DATE_EPOCH:-946684800}
case "$build_epoch" in
	''|*[!0-9]*) fail "SOURCE_DATE_EPOCH must be a non-negative integer" ;;
esac

"$mkimage" -l "$fit_image" | grep -q '^FIT description:' || \
	fail "input is not a valid FIT image: $fit_image"

mkdir -p "$boot_dir"
boot_stage=$(mktemp -d "${TMPDIR:-/tmp}/tb-boot-linux.XXXXXX")
image_tmp=$(mktemp "$boot_dir/.boot_linux.img.XXXXXX")

cleanup()
{
	rm -rf -- "$boot_stage"
	[ -z "$image_tmp" ] || rm -f -- "$image_tmp"
}
trap cleanup EXIT

cp -- "$fit_image" "$boot_stage/openwrt.itb"
cp -- "$PROJECT_DIR/boot/boot.cmd" "$boot_stage/boot.cmd"
SOURCE_DATE_EPOCH=$build_epoch "$mkimage" \
	-A arm64 -O linux -T script -C none \
	-n "TB-RK3399ProD OpenWrt boot" \
	-d "$boot_stage/boot.cmd" "$boot_stage/boot.scr"
"$mkimage" -l "$boot_stage/boot.scr" >/dev/null 2>&1 || \
	fail "generated boot.scr is invalid"
(
	cd "$boot_stage"
	sha256sum boot.cmd boot.scr openwrt.itb > SHA256SUMS
)

# Keep imported inode timestamps stable across build hosts.
touch -d "@$build_epoch" "$boot_stage" "$boot_stage"/*

truncate -s "$BOOT_LINUX_IMAGE_SIZE" "$image_tmp"
E2FSPROGS_FAKE_TIME=$build_epoch \
	mke2fs -q -F -t ext2 -b 4096 -i 8192 -m 0 \
	-L boot_linux -U 8b3399d0-0000-4000-8000-000000000001 \
	-O '^64bit,^metadata_csum' \
	-E root_owner=0:0,hash_seed=8b3399d0-0000-4000-8000-000000000001 \
	-d "$boot_stage" "$image_tmp"

[ "$(stat -c '%s' "$image_tmp")" -eq "$BOOT_LINUX_IMAGE_SIZE" ] || \
	fail "boot_linux.img is not exactly 64 MiB"
e2fsck -fn "$image_tmp" >/dev/null 2>&1 || \
	fail "boot_linux.img failed e2fsck"
debugfs -R 'stat /boot.scr' "$image_tmp" 2>&1 | \
	grep -q '^Inode:' || fail "boot_linux.img is missing /boot.scr"
debugfs -R 'stat /openwrt.itb' "$image_tmp" 2>&1 | \
	grep -q '^Inode:' || fail "boot_linux.img is missing /openwrt.itb"

mv -f -- "$image_tmp" "$boot_image"
image_tmp=
echo "Boot partition image: $boot_image"
