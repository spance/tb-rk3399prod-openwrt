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
openwrt_patch="$PROJECT_DIR/patches/openwrt/0001-tb-rk3399prod-board-support.patch"
ensure_patches_applied "$WORK_DIR/openwrt" "$openwrt_patch"
bash "$SCRIPT_DIR/sync-openwrt-dts.sh" "$WORK_DIR/openwrt"
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
	make download -j"$jobs"
)

printf '%s\n' \
	"U-Boot=$UBOOT_COMMIT" \
	"rkbin=$RKBIN_COMMIT" \
	"toolchain=$TOOLCHAIN_COMMIT" \
	"OpenWrt=$OPENWRT_COMMIT" \
	"Linux=$LINUX_VERSION" > "$WORK_DIR/BASELINES"
sed 's/^/feed=/' "$PROJECT_DIR/configs/feeds.conf" >> "$WORK_DIR/BASELINES"

bash "$SCRIPT_DIR/check.sh"
echo "Initialization complete: $WORK_DIR"
