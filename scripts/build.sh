#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -ge 1 ] && [ "$#" -le 2 ] || \
	fail "usage: $0 uboot|openwrt|all [jobs]"

target=$1
jobs=${2:-$(nproc)}
case "$target" in
	uboot|openwrt|all) ;;
	*) fail "unknown build target: $target" ;;
esac
case "$jobs" in
	''|*[!0-9]*) fail "jobs must be a positive integer" ;;
esac
[ "$jobs" -gt 0 ] || fail "jobs must be greater than zero"

bash "$SCRIPT_DIR/init.sh"

build_uboot()
{
	(
		cd "$WORK_DIR/u-boot"
		./make.sh rk3399pro
	)

	image="$WORK_DIR/u-boot/uboot.img"
	[ -f "$image" ] || fail "U-Boot build did not produce $image"
	[ "$(stat -c '%s' "$image")" -eq 4194304 ] || \
		fail "uboot.img is not exactly 4 MiB"

	dest="$OUT_DIR/uboot"
	reset_generated_dir "$dest"
	cp "$image" "$dest/uboot.img"
	( cd "$dest" && sha256sum uboot.img > SHA256SUMS )
}

build_openwrt()
{
	source="$WORK_DIR/openwrt"
	config="$PROJECT_DIR/configs/openwrt.config"

	(
		cd "$source"
		./scripts/feeds update -a
		./scripts/feeds install -a
		cp "$config" .config
		make defconfig
		make download -j"$jobs"
		make -j"$jobs" || make -j1 V=s
	)

	target_dir="$source/bin/targets/rockchip/armv8"
	[ -d "$target_dir" ] || fail "OpenWrt output not found: $target_dir"
	dest="$OUT_DIR/openwrt"
	reset_generated_dir "$dest"

	found=0
	while IFS= read -r -d '' file; do
		cp "$file" "$dest/"
		found=1
	done < <(find "$target_dir" -maxdepth 1 -type f \( \
		-name '*toybrick*' -o -name '*.buildinfo' -o -name sha256sums -o \
		-name profiles.json \) \
		-print0)
	[ "$found" -eq 1 ] || fail "no TB-RK3399ProD OpenWrt output was found"
	(
		cd "$dest"
		find . -maxdepth 1 -type f ! -name TB-SHA256SUMS -print0 | \
			sort -z | xargs -0 -r sha256sum > TB-SHA256SUMS
	)
}

case "$target" in
	uboot) build_uboot ;;
	openwrt) build_openwrt ;;
	all)
		build_uboot
		build_openwrt
		;;
esac

echo "Build outputs: $OUT_DIR"
