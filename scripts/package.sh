#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

bash "$SCRIPT_DIR/check-env.sh"
[ "$#" -eq 0 ] || fail "usage: $0"

for required in \
	"$OUT_DIR/uboot/uboot.img" \
	"$OUT_DIR/openwrt/boot_linux.img" \
	"$OUT_DIR/openwrt/rootfs.img"; do
	[ -e "$required" ] || fail "missing build output: $required; run make all first"
done

mkdir -p "$DIST_DIR"
stage=$(mktemp -d "$DIST_DIR/.stage.XXXXXX")
trap 'rm -rf -- "$stage"' EXIT

mkdir -p "$stage/firmware"
cp -a "$OUT_DIR/uboot" "$stage/firmware/"
cp -a "$OUT_DIR/openwrt" "$stage/firmware/"

printf '%s\n' \
	"Board: TB-RK3399ProD" \
	"U-Boot: $UBOOT_COMMIT" \
	"rkbin: $RKBIN_COMMIT" \
	"toolchain: $TOOLCHAIN_COMMIT" \
	"OpenWrt: $OPENWRT_TAG ($OPENWRT_COMMIT)" \
	"Linux: $LINUX_VERSION" > "$stage/BUILD-METADATA.txt"

(
	cd "$stage"
	find firmware -type f -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
)

archive="$DIST_DIR/tb-rk3399prod-openwrt-$OPENWRT_VERSION.tar.gz"
tar --sort=name --mtime="@${SOURCE_DATE_EPOCH:-0}" \
	--owner=0 --group=0 --numeric-owner -C "$stage" -czf "$archive.tmp" .
mv -f "$archive.tmp" "$archive"
(
	cd "$DIST_DIR"
	sha256sum "$(basename -- "$archive")" > "$(basename -- "$archive").sha256"
)

echo "Release package: $archive"
