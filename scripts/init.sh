#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -le 1 ] || fail "usage: $0 [jobs]"
jobs=${1:-$(nproc)}
case "$jobs" in
''|*[!0-9]*) fail "jobs must be a positive integer" ;;
esac
[ "$jobs" -gt 0 ] || fail "jobs must be greater than zero"

invalidate_stale_kernel_abi_cache()
{
	local openwrt_dir abi_file kernel_dir cached_abi
	openwrt_dir=$1
	[ -d "$openwrt_dir/build_dir" ] || return 0

	while IFS= read -r -d '' abi_file; do
		cached_abi=$(cat "$abi_file")
		[ "$cached_abi" = "$TB_KERNEL_ABI" ] && continue
		kernel_dir=$(dirname -- "$abi_file")
		case "$kernel_dir/" in
			"$openwrt_dir/build_dir/"*) ;;
			*) fail "refusing to invalidate kernel cache outside OpenWrt build_dir: $kernel_dir" ;;
		esac
		rm -f -- "$kernel_dir/.configured" "$kernel_dir/.vermagic" \
			"$kernel_dir/.vermagic.native"
		find "$kernel_dir" -maxdepth 1 -type f -name '.configured_*' -delete
		echo "Invalidated stale kernel ABI cache: $cached_abi"
	done < <(find "$openwrt_dir/build_dir" -type f \
		-path "*/linux-rockchip_armv8/linux-$LINUX_VERSION/.vermagic" -print0)
}

bash "$SCRIPT_DIR/check-env.sh"
require_case_sensitive_dir "$WORK_DIR"

ensure_checkout "$UBOOT_URL" "$UBOOT_COMMIT" "$UBOOT_COMMIT" \
	"$WORK_DIR/u-boot"
ensure_checkout "$RKBIN_URL" "$RKBIN_COMMIT" "$RKBIN_COMMIT" \
	"$WORK_DIR/rkbin"
ensure_checkout "$TOOLCHAIN_URL" "$TOOLCHAIN_COMMIT" "$TOOLCHAIN_COMMIT" \
	"$WORK_DIR/prebuilts/gcc"

ensure_patches_applied "$WORK_DIR/u-boot" \
	"$PROJECT_DIR/patches/u-boot/0001-modern-linux-host-build-compat.patch" \
	"$PROJECT_DIR/patches/u-boot/0002-tb-rk3399prod-dwmmc-tf-reliability.patch"

ensure_checkout "$OPENWRT_URL" "refs/tags/$OPENWRT_TAG" "$OPENWRT_COMMIT" \
	"$WORK_DIR/openwrt"
openwrt_patches=(
	"$PROJECT_DIR/patches/openwrt/0001-tb-rk3399prod-board-support.patch"
)
ensure_patches_applied "$WORK_DIR/openwrt" "${openwrt_patches[@]}"
bash "$SCRIPT_DIR/sync-openwrt-kernel-patches.sh" "$WORK_DIR/openwrt"
bash "$SCRIPT_DIR/sync-openwrt-dts.sh" "$WORK_DIR/openwrt"
bash "$SCRIPT_DIR/sync-openwrt-rootfs.sh" "$WORK_DIR/openwrt"
install -m 0644 "$PROJECT_DIR/configs/feeds.conf" \
	"$WORK_DIR/openwrt/feeds.conf"
cmp -s "$PROJECT_DIR/configs/feeds.conf" "$WORK_DIR/openwrt/feeds.conf" || \
	fail "OpenWrt feeds configuration synchronization failed"

if ! feeds_match_config "$WORK_DIR/openwrt" \
	"$PROJECT_DIR/configs/feeds.conf"; then
	(
		cd "$WORK_DIR/openwrt"
		retry 3 10 ./scripts/feeds update -a
	)
fi
feeds_match_config "$WORK_DIR/openwrt" "$PROJECT_DIR/configs/feeds.conf" || \
	fail "OpenWrt feeds do not match the pinned configuration; use an empty TB_WORK_DIR"

(
	cd "$WORK_DIR/openwrt"
	./scripts/feeds install -a
	install -m 0644 "$PROJECT_DIR/configs/openwrt.config" .config
	make defconfig
	invalidate_stale_kernel_abi_cache "$WORK_DIR/openwrt"
	make download -j"$jobs"
)

printf '%s\n' \
	"U-Boot=$UBOOT_COMMIT" \
	"rkbin=$RKBIN_COMMIT" \
	"toolchain=$TOOLCHAIN_COMMIT" \
	"OpenWrt=$OPENWRT_COMMIT" \
	"Linux=$LINUX_VERSION" \
	"kernel-abi=$TB_KERNEL_ABI" > "$WORK_DIR/BASELINES"
sed 's/^/feed=/' "$PROJECT_DIR/configs/feeds.conf" >> "$WORK_DIR/BASELINES"

bash "$SCRIPT_DIR/check.sh"
echo "Initialization complete: $WORK_DIR"
