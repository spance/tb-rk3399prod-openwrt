#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 2 ] || fail "usage: $0 loader-image trust-image"
loader=$(readlink -m "$1")
trust=$(readlink -m "$2")
boot_merger="$WORK_DIR/rkbin/tools/boot_merger"

[ -x "$boot_merger" ] || \
	fail "pinned rkbin boot_merger is unavailable: $boot_merger"
[ "$(stat -c '%s' "$loader")" -eq "$RKBIN_LOADER_IMAGE_SIZE" ] || \
	fail "$RKBIN_LOADER_IMAGE has an unexpected size"
[ "$(stat -c '%s' "$trust")" -eq "$RKBIN_TRUST_IMAGE_SIZE" ] || \
	fail "$RKBIN_TRUST_IMAGE is not exactly 4 MiB"
verify_sha256 "$trust" "$RKBIN_TRUST_IMAGE_SHA256"

temp_root=$(readlink -m "${TMPDIR:-/tmp}")
stage=$(mktemp -d "$temp_root/tb-rk3399prod-loader-verify.XXXXXX")
cleanup()
{
	case "$stage/" in
	"$temp_root/"tb-rk3399prod-loader-verify.*/) rm -rf -- "$stage" ;;
	*) fail "refusing to remove unexpected verification directory: $stage" ;;
	esac
}
trap cleanup EXIT

"$boot_merger" unpack -i "$loader" -o "$stage"
[ "$(find "$stage" -mindepth 1 -maxdepth 1 -type f | wc -l)" -eq 4 ] || \
	fail "loader does not unpack to exactly four expected payloads"

verify_payload()
{
	local name size hash file
	name=$1
	size=$2
	hash=$3
	file="$stage/$name"
	[ -f "$file" ] || fail "loader payload is missing: $name"
	[ "$(stat -c '%s' "$file")" -eq "$size" ] || \
		fail "loader payload has an unexpected size: $name"
	verify_sha256 "$file" "$hash"
}

verify_payload rk3399pro_ddr_800MH.bin \
	"$RKBIN_LOADER_DDR_SIZE" "$RKBIN_LOADER_DDR_SHA256"
verify_payload FlashData.bin \
	"$RKBIN_LOADER_DDR_SIZE" "$RKBIN_LOADER_DDR_SHA256"
verify_payload FlashBoot.bin \
	"$RKBIN_LOADER_MINILOADER_SIZE" "$RKBIN_LOADER_MINILOADER_SHA256"
verify_payload rk3399pro_usbplug_v.bin \
	"$RKBIN_LOADER_USBPLUG_SIZE" "$RKBIN_LOADER_USBPLUG_SHA256"
cmp -s "$stage/rk3399pro_ddr_800MH.bin" "$stage/FlashData.bin" || \
	fail "loader CODE471 and FlashData DDR payloads differ"

echo "Verified Rockchip loader payloads and trust image"
