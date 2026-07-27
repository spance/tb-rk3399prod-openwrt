#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -le 2 ] || fail "usage: $0 [jobs] [kmod-package-list]"
jobs=${1:-$(nproc)}
kmods_raw=${2:-}
case "$jobs" in
''|*[!0-9]*) fail "jobs must be a positive integer" ;;
esac
[ "$jobs" -gt 0 ] || fail "jobs must be greater than zero"
normalized_kmods=$(normalize_kmod_names "$kmods_raw")
optional_kmods=()
if [ -n "$normalized_kmods" ]; then
	mapfile -t optional_kmods <<< "$normalized_kmods"
fi

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
	for package in "${optional_kmods[@]}"; do
		openwrt_package_source_makefile "$WORK_DIR/openwrt" "$package" \
			>/dev/null || \
			fail "kmod package is not defined by the pinned OpenWrt sources: $package"
		if grep -Fqx "CONFIG_PACKAGE_$package=y" .config; then
			fail "kmod package is already built into the firmware: $package"
		fi
		if grep -Fqx "CONFIG_PACKAGE_$package=m" .config; then
			continue
		fi
		printf 'CONFIG_PACKAGE_%s=m\n' "$package" >> .config
	done
	if [ "${#optional_kmods[@]}" -gt 0 ]; then
		make defconfig
		for package in "${optional_kmods[@]}"; do
			grep -Fqx "CONFIG_PACKAGE_$package=m" .config || \
				fail "kmod package cannot be selected for this target: $package"
		done
	fi
	make download -j"$jobs"
)

kmod_baseline=$(IFS=,; printf '%s' "${optional_kmods[*]}")
printf '%s\n' \
	"U-Boot=$UBOOT_COMMIT" \
	"rkbin=$RKBIN_COMMIT" \
	"toolchain=$TOOLCHAIN_COMMIT" \
	"OpenWrt=$OPENWRT_COMMIT" \
	"Linux=$LINUX_VERSION" \
	"KMODS=$kmod_baseline" > "$WORK_DIR/BASELINES"
sed 's/^/feed=/' "$PROJECT_DIR/configs/feeds.conf" >> "$WORK_DIR/BASELINES"

bash "$SCRIPT_DIR/check.sh"
echo "Initialization complete: $WORK_DIR"
