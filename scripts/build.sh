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
	uboot_toolchain_name=gcc-linaro-6.3.1-2017.05-x86_64_aarch64-linux-gnu
	uboot_toolchain="$WORK_DIR/prebuilts/gcc/aarch64/$uboot_toolchain_name/bin"
	uboot_cross="$uboot_toolchain/aarch64-linux-gnu-"
	[ -x "${uboot_cross}gcc" ] || \
		fail "U-Boot cross compiler not found: ${uboot_cross}gcc"
	(
		cd "$WORK_DIR/u-boot"
		rm -f -- uboot.img "$RKBIN_LOADER_IMAGE" "$RKBIN_TRUST_IMAGE"
		./make.sh "CROSS_COMPILE=$uboot_cross" rk3399pro
	)

	image="$WORK_DIR/u-boot/uboot.img"
	loader="$WORK_DIR/u-boot/$RKBIN_LOADER_IMAGE"
	trust="$WORK_DIR/u-boot/$RKBIN_TRUST_IMAGE"
	[ -f "$image" ] || fail "U-Boot build did not produce $image"
	[ -f "$loader" ] || fail "U-Boot build did not produce $loader"
	[ -f "$trust" ] || fail "U-Boot build did not produce $trust"
	grep -Fqx 'CONFIG_LOADER_INI="RK3399PROMINIALL.ini"' \
		"$WORK_DIR/u-boot/.config" || \
		fail "U-Boot did not select the RK3399Pro loader INI"
	grep -Fqx 'CONFIG_TRUST_INI="RK3399PROTRUST.ini"' \
		"$WORK_DIR/u-boot/.config" || \
		fail "U-Boot did not select the RK3399Pro trust INI"
	grep -Fqx '# CONFIG_ROCKCHIP_FIT_IMAGE is not set' \
		"$WORK_DIR/u-boot/.config" || \
		fail "U-Boot unexpectedly enabled the private Rockchip FIT boot path"
	grep -aFq 'optee api revision: %d.%d' \
		"$WORK_DIR/u-boot/u-boot.bin" || \
		fail "U-Boot is missing the OP-TEE API revision 2 client"
	if grep -aFq 'BOOTM: transferring to board FIT' \
		"$WORK_DIR/u-boot/u-boot.bin"; then
		fail "U-Boot still intercepts standard FIT images with the private boot_fit path"
	fi
	grep -Fqx 'CONFIG_BOOTCOMMAND="run distro_bootcmd"' \
		"$WORK_DIR/u-boot/include/autoconf.mk" || \
		fail "U-Boot default command does not enter standard distro boot directly"
	uboot_identity="tb-rk3399prod-g${UBOOT_COMMIT:0:7}"
	grep -aFq "$uboot_identity" "$WORK_DIR/u-boot/u-boot.bin" || \
		fail "U-Boot binary does not identify the pinned source commit"
	[ "$(stat -c '%s' "$image")" -eq 4194304 ] || \
		fail "uboot.img is not exactly 4 MiB"
	bash "$SCRIPT_DIR/verify-rkbin-images.sh" "$loader" "$trust"

	dest="$OUT_DIR/uboot"
	reset_generated_dir "$dest"
	cp "$image" "$dest/uboot.img"
	cp "$loader" "$dest/$RKBIN_LOADER_IMAGE"
	cp "$trust" "$dest/$RKBIN_TRUST_IMAGE"
	(
		cd "$dest"
		sha256sum uboot.img "$RKBIN_LOADER_IMAGE" \
			"$RKBIN_TRUST_IMAGE" > SHA256SUMS
	)
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

	manifest_count=0
	manifest=
	while IFS= read -r -d '' file; do
		manifest=$file
		manifest_count=$((manifest_count + 1))
	done < <(find "$dest" -maxdepth 1 -type f \
		-name '*toybrick_tb-rk3399prod.manifest' -print0)
	[ "$manifest_count" -eq 1 ] || \
		fail "expected exactly one TB-RK3399ProD package manifest, found $manifest_count"
	for package in tar xz xz-utils; do
		grep -Eq "^${package}[[:space:]]+-[[:space:]]+" "$manifest" || \
			fail "OpenWrt manifest does not contain required package: $package"
	done

	mapfile -d '' root_dirs < <(find "$source/build_dir" -mindepth 2 \
		-maxdepth 2 -type d -name root-rockchip -print0)
	[ "${#root_dirs[@]}" -eq 1 ] || \
		fail "expected exactly one staged Rockchip rootfs, found ${#root_dirs[@]}"
	[ -x "${root_dirs[0]}/usr/libexec/tar-gnu" ] || \
		fail "staged rootfs does not contain GNU tar"

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
	[ "$(stat -c '%s' "$rootfs_image")" -eq "$ROOTFS_IMAGE_SIZE" ] || \
		fail "SquashFS rootfs image is not exactly 128 MiB"
	[ "$(od -An -tx1 -N4 "$rootfs_image" | tr -d ' \n')" = 68737173 ] || \
		fail "rootfs image does not start with a SquashFS superblock"

	rootfs_original_name=$(basename -- "$rootfs_image")
	mv -- "$rootfs_image" "$dest/rootfs.img"
	ln -s rootfs.img "$dest/$rootfs_original_name"
	rootfs_image="$dest/rootfs.img"

	mkimage="$source/staging_dir/host/bin/mkimage"
	[ -x "$mkimage" ] || fail "OpenWrt host mkimage not found: $mkimage"
	bash "$SCRIPT_DIR/make-boot-linux.sh" \
		"$fit_image" "$mkimage" "$dest/boot_linux.img"
	bash "$SCRIPT_DIR/make-openwrt-image.sh" \
		"$dest/boot_linux.img" "$rootfs_image" "$dest/openwrt.img"
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
