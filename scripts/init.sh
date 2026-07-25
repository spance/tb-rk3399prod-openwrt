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
openwrt_patch="$PROJECT_DIR/patches/openwrt/0001-tb-rk3399prod-board-support.patch"
openwrt_marker="$WORK_DIR/openwrt/.tb-rk3399prod-patch-applied"
if [ -f "$openwrt_marker" ] && \
	! git -C "$WORK_DIR/openwrt" apply --reverse --check "$openwrt_patch" \
		>/dev/null 2>&1; then
	migration_patch="$PROJECT_DIR/patches/openwrt/migrations/0001-v1-profile-to-persistent-rootfs.patch"
	if git -C "$WORK_DIR/openwrt" apply --check "$migration_patch"; then
		git -C "$WORK_DIR/openwrt" apply "$migration_patch"
		git -C "$WORK_DIR/openwrt" diff --check
		git -C "$WORK_DIR/openwrt" apply --reverse --check "$openwrt_patch" || \
			fail "OpenWrt worktree migration did not reach the expected patch state"
		echo "Migrated existing OpenWrt worktree to the consolidated board profile"
	fi
fi
apply_patch_set "$WORK_DIR/openwrt" .tb-rk3399prod-patch-applied \
	"$openwrt_patch"
bash "$SCRIPT_DIR/sync-openwrt-dts.sh" "$WORK_DIR/openwrt"

printf '%s\n' \
	"U-Boot=$UBOOT_COMMIT" \
	"rkbin=$RKBIN_COMMIT" \
	"toolchain=$TOOLCHAIN_COMMIT" \
	"OpenWrt=$OPENWRT_COMMIT" > "$WORK_DIR/BASELINES"

echo "Initialization complete: $WORK_DIR"
