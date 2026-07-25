#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 1 ] || fail "usage: $0 OPENWRT_SOURCE_DIR"
openwrt_dir=$(readlink -m "$1")
rockchip_makefile="$openwrt_dir/target/linux/rockchip/Makefile"
[ -f "$rockchip_makefile" ] || \
	fail "OpenWrt Rockchip target Makefile not found: $rockchip_makefile"

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

dest="$openwrt_dir/target/linux/rockchip/files-$kernel_patchver/arch/arm64/boot/dts/rockchip"
install -d "$dest"

for name in rk3399pro-toybrick-prod.dts rk3399pro-toybrick-prod.dtsi; do
	source_file="$PROJECT_DIR/dts/$name"
	[ -f "$source_file" ] || fail "canonical DTS file not found: $source_file"
	if [ ! -f "$dest/$name" ] || ! cmp -s "$source_file" "$dest/$name"; then
		install -m 0644 "$source_file" "$dest/$name"
	fi
	cmp -s "$source_file" "$dest/$name" || fail "DTS synchronization failed: $name"
done

echo "Synchronized canonical DTS files to OpenWrt files-$kernel_patchver"
