#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

bash "$SCRIPT_DIR/check-env.sh"
require_case_sensitive_dir "$WORK_DIR"

ensure_checkout "$UBOOT_URL" "$UBOOT_COMMIT" "$UBOOT_COMMIT" \
	"$WORK_DIR/u-boot"
ensure_checkout "$RKBIN_URL" "$RKBIN_COMMIT" "$RKBIN_COMMIT" \
	"$WORK_DIR/rkbin"
ensure_checkout "$TOOLCHAIN_URL" "$TOOLCHAIN_COMMIT" "$TOOLCHAIN_COMMIT" \
	"$WORK_DIR/prebuilts/gcc"

apply_patch_set "$WORK_DIR/u-boot" .tb-rk3399prod-patches-applied \
	"$PROJECT_DIR/patches/u-boot/0001-modern-linux-host-build-compat.patch" \
	"$PROJECT_DIR/patches/u-boot/0002-tb-rk3399prod-dwmmc-tf-reliability.patch"

ensure_checkout "$OPENWRT_URL" "refs/tags/$OPENWRT_TAG" "$OPENWRT_COMMIT" \
	"$WORK_DIR/openwrt"
apply_patch_set "$WORK_DIR/openwrt" .tb-rk3399prod-patch-applied \
	"$PROJECT_DIR/patches/openwrt/0001-tb-rk3399prod-board-support.patch"
apply_patch_set "$WORK_DIR/openwrt" .tb-rk3399prod-overlay-patch-applied \
	"$PROJECT_DIR/patches/openwrt/0002-tb-rk3399prod-persistent-overlay.patch"

printf '%s\n' \
	"U-Boot=$UBOOT_COMMIT" \
	"rkbin=$RKBIN_COMMIT" \
	"toolchain=$TOOLCHAIN_COMMIT" \
	"OpenWrt=$OPENWRT_COMMIT" > "$WORK_DIR/BASELINES"

echo "Initialization complete: $WORK_DIR"
