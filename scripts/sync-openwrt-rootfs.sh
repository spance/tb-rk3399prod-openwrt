#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 1 ] || fail "usage: $0 OPENWRT_SOURCE_DIR"
openwrt_dir=$(readlink -m "$1")
source_root="$PROJECT_DIR/rootfs"
dest_root="$openwrt_dir/target/linux/rockchip/base-files"

[ -d "$source_root" ] || fail "canonical rootfs overlay not found: $source_root"
[ -d "$dest_root" ] || fail "OpenWrt Rockchip base-files not found: $dest_root"

while IFS= read -r -d '' source_file; do
	relative_path=${source_file#"$source_root"/}
	dest_file="$dest_root/$relative_path"
	mode=0644
	case "$relative_path" in
	etc/init.d/*|etc/uci-defaults/*|usr/sbin/*) mode=0755 ;;
	esac
	install -D -m "$mode" "$source_file" "$dest_file"
	cmp -s "$source_file" "$dest_file" || \
		fail "rootfs synchronization failed: $relative_path"
done < <(find "$source_root" -type f -print0 | sort -z)

echo "Synchronized canonical rootfs overlay to OpenWrt Rockchip base-files"
