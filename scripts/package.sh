#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

bash "$SCRIPT_DIR/check-env.sh"
[ "$#" -eq 0 ] || fail "usage: $0"

for required in \
	"$OUT_DIR/uboot/uboot.img" \
	"$OUT_DIR/uboot/$RKBIN_LOADER_IMAGE" \
	"$OUT_DIR/uboot/$RKBIN_TRUST_IMAGE" \
	"$OUT_DIR/openwrt/openwrt.img"; do
	[ -e "$required" ] || fail "missing build output: $required; run make all first"
done
[ "$(stat -c '%s' "$OUT_DIR/uboot/uboot.img")" -eq 4194304 ] || \
	fail "uboot.img is not exactly 4 MiB"
bash "$SCRIPT_DIR/verify-rkbin-images.sh" \
	"$OUT_DIR/uboot/$RKBIN_LOADER_IMAGE" \
	"$OUT_DIR/uboot/$RKBIN_TRUST_IMAGE"
bash "$SCRIPT_DIR/verify-openwrt-image.sh" \
	"$OUT_DIR/openwrt/openwrt.img" >/dev/null

mark_managed_dir "$DIST_DIR" dist
stage=$(mktemp -d "$DIST_DIR/.stage.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT

mkdir -p "$stage/firmware"
cp -- "$OUT_DIR/uboot/uboot.img" "$stage/firmware/uboot.img"
cp -- "$OUT_DIR/uboot/$RKBIN_LOADER_IMAGE" \
	"$stage/firmware/$RKBIN_LOADER_IMAGE"
cp -- "$OUT_DIR/uboot/$RKBIN_TRUST_IMAGE" \
	"$stage/firmware/$RKBIN_TRUST_IMAGE"
cp --sparse=always -- "$OUT_DIR/openwrt/openwrt.img" \
	"$stage/firmware/openwrt.img"
chmod 0644 "$stage/firmware/uboot.img" \
	"$stage/firmware/$RKBIN_LOADER_IMAGE" \
	"$stage/firmware/$RKBIN_TRUST_IMAGE" \
	"$stage/firmware/openwrt.img"

printf '%s\n' \
	"Board: TB-RK3399ProD" \
	"U-Boot: $UBOOT_COMMIT" \
	"rkbin: $RKBIN_COMMIT" \
	"loader: DDR v$RKBIN_DDR_VERSION + miniloader v$RKBIN_MINILOADER_VERSION" \
	"trust: BL31 v$RKBIN_BL31_VERSION + BL32/OP-TEE v$RKBIN_BL32_VERSION" \
	"toolchain: $TOOLCHAIN_COMMIT" \
	"OpenWrt: $OPENWRT_TAG ($OPENWRT_COMMIT)" \
	"Linux: $LINUX_VERSION" \
	"$RKBIN_LOADER_IMAGE: use Rockchip Upgrade Loader; not a GPT partition image" \
	"uboot.img: flash at LBA 0x$(printf '%x' "$UBOOT_LBA")" \
	"trust.img: flash at LBA 0x$(printf '%x' "$TRUST_LBA")" \
	"openwrt.img: flash at LBA 0x$(printf '%x' "$BOOT_LINUX_LBA")" \
	"openwrt.img rootfs: byte offset $OPENWRT_ROOTFS_OFFSET, eMMC LBA 0x$(printf '%x' "$ROOTFS_LBA")" \
	> "$stage/BUILD-METADATA.txt"

(
	cd "$stage"
	find firmware -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

archive="$DIST_DIR/tb-rk3399prod-openwrt-$OPENWRT_VERSION.tar.gz"
tar --sparse --sparse-version=1.0 --sort=name \
	--mtime="@${SOURCE_DATE_EPOCH:-0}" \
	--owner=0 --group=0 --numeric-owner -C "$stage" -czf "$archive.tmp" .
mv -f "$archive.tmp" "$archive"
(
	cd "$DIST_DIR"
	sha256sum "$(basename -- "$archive")" > "$(basename -- "$archive").sha256"
)

echo "Release package: $archive"
