#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 1 ] || fail "usage: $0 OPENWRT_SOURCE_DIR"
openwrt_dir=$(readlink -m "$1")
rockchip_makefile="$openwrt_dir/target/linux/rockchip/Makefile"
source_dir="$PROJECT_DIR/patches/kernel"

[ -f "$rockchip_makefile" ] || \
	fail "OpenWrt Rockchip target Makefile not found: $rockchip_makefile"
[ -d "$source_dir" ] || fail "canonical kernel patch directory not found: $source_dir"

kernel_patchver=$(sed -n \
	's/^[[:space:]]*KERNEL_PATCHVER[[:space:]]*:=[[:space:]]*//p' \
	"$rockchip_makefile")
case "$kernel_patchver" in
	''|*[!0-9.]*|*.*.*|.*|*.)
		fail "unable to determine one Rockchip KERNEL_PATCHVER"
		;;
	*.*) ;;
	*) fail "unable to determine one Rockchip KERNEL_PATCHVER" ;;
esac

dest="$openwrt_dir/target/linux/rockchip/patches-$kernel_patchver"
[ -d "$dest" ] || fail "OpenWrt kernel patch directory not found: $dest"

count=0
for source_file in "$source_dir"/*.patch; do
	[ -f "$source_file" ] || continue
	name=${source_file##*/}
	install -m 0644 "$source_file" "$dest/$name"
	cmp -s "$source_file" "$dest/$name" || \
		fail "kernel patch synchronization failed: $name"
	count=$((count + 1))
done
[ "$count" -gt 0 ] || fail "no canonical kernel patches found in $source_dir"

echo "Synchronized $count canonical patches to OpenWrt patches-$kernel_patchver"
