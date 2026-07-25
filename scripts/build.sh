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

bash "$SCRIPT_DIR/check-env.sh"
[ -d "$WORK_DIR/u-boot/.git" ] || \
	fail "U-Boot worktree is not initialized; run make init first"
[ -d "$WORK_DIR/openwrt/.git" ] || \
	fail "OpenWrt worktree is not initialized; run make init first"
[ -f "$WORK_DIR/BASELINES" ] || \
	fail "initialization baseline record is missing; run make init first"
bash "$SCRIPT_DIR/check.sh"
mark_managed_dir "$OUT_DIR" out

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

	(
		cd "$source"
		if ! make -j"$jobs" </dev/null; then
			echo "Parallel OpenWrt build failed; retrying non-interactively with -j1 V=sc" >&2
			make -j1 V=sc </dev/null
		fi
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

	fit_count=0
	fit_image=
	while IFS= read -r -d '' file; do
		fit_image=$file
		fit_count=$((fit_count + 1))
	done < <(find "$dest" -maxdepth 1 -type f \
		-name '*toybrick_tb-rk3399prod-kernel.bin' -print0)
	[ "$fit_count" -eq 1 ] || \
		fail "expected exactly one TB-RK3399ProD normal FIT, found $fit_count"

	rootfs_count=0
	rootfs_image=
	while IFS= read -r -d '' file; do
		rootfs_image=$file
		rootfs_count=$((rootfs_count + 1))
	done < <(find "$dest" -maxdepth 1 -type f \
		-name '*toybrick_tb-rk3399prod-squashfs-rootfs.img' -print0)
	[ "$rootfs_count" -eq 1 ] || \
		fail "expected exactly one TB-RK3399ProD SquashFS rootfs image, found $rootfs_count"
	[ "$(stat -c '%s' "$rootfs_image")" -eq 134217728 ] || \
		fail "SquashFS rootfs image is not exactly 128 MiB"
	[ "$(od -An -tx1 -N4 "$rootfs_image" | tr -d ' \n')" = 68737173 ] || \
		fail "rootfs image does not start with a SquashFS superblock"

	rootfs_original_name=$(basename -- "$rootfs_image")
	mv -- "$rootfs_image" "$dest/rootfs.img"
	ln -s rootfs.img "$dest/$rootfs_original_name"

	mkimage="$source/staging_dir/host/bin/mkimage"
	[ -x "$mkimage" ] || fail "OpenWrt host mkimage not found: $mkimage"
	bash "$SCRIPT_DIR/make-boot-linux.sh" \
		"$fit_image" "$mkimage" "$dest/boot_linux.img"
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
