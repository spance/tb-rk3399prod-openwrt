#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 0 ] || fail "usage: $0"
[ "$WORK_DIR" != / ] || fail "refusing to reset worktrees below filesystem root"
[ "$WORK_DIR" != "$PROJECT_DIR" ] || \
	fail "TB_WORK_DIR must not be the project root"
if [ -n "${HOME:-}" ]; then
	[ "$WORK_DIR" != "$(readlink -m "$HOME")" ] || \
		fail "TB_WORK_DIR must not be the home directory"
fi

reset_checkout()
{
	local repo expected_url expected_commit label actual_url
	repo=$(readlink -m "$1")
	expected_url=$2
	expected_commit=$3
	label=$4

	[ -e "$repo" ] || return 0
	case "$repo/" in
		"$WORK_DIR/"*) ;;
		*) fail "refusing to reset repository outside TB_WORK_DIR: $repo" ;;
	esac
	[ -d "$repo/.git" ] || fail "$label path is not a Git checkout: $repo"
	actual_url=$(git -C "$repo" remote get-url origin 2>/dev/null || true)
	[ "$actual_url" = "$expected_url" ] || \
		fail "unexpected origin for $label: $actual_url"
	git -C "$repo" cat-file -e "$expected_commit^{commit}" 2>/dev/null || \
		fail "pinned commit is unavailable in $label: $expected_commit"

	git -C "$repo" reset --hard "$expected_commit"
	git -C "$repo" clean -fd
	echo "Reset $label to $expected_commit"
}

if [ ! -d "$WORK_DIR" ]; then
	echo "Work directory does not exist; nothing to reset: $WORK_DIR"
	exit 0
fi

reset_checkout "$WORK_DIR/u-boot" "$UBOOT_URL" "$UBOOT_COMMIT" U-Boot
reset_checkout "$WORK_DIR/rkbin" "$RKBIN_URL" "$RKBIN_COMMIT" rkbin
reset_checkout "$WORK_DIR/prebuilts/gcc" "$TOOLCHAIN_URL" \
	"$TOOLCHAIN_COMMIT" toolchain
reset_checkout "$WORK_DIR/openwrt" "$OPENWRT_URL" "$OPENWRT_COMMIT" OpenWrt

while read -r kind name location extra; do
	case "$kind" in
		''|'#'*) continue ;;
	esac
	[ "$kind" = src-git ] || fail "unsupported feed kind: $kind"
	[ -z "${extra:-}" ] || fail "invalid feed entry: $kind $name $location $extra"
	feed_url=${location%^*}
	feed_commit=${location##*^}
	[ "$feed_url" != "$location" ] || fail "feed is not pinned: $name"
	reset_checkout "$WORK_DIR/openwrt/feeds/$name" "$feed_url" \
		"$feed_commit" "OpenWrt feed $name"
done < "$PROJECT_DIR/configs/feeds.conf"

rm -f -- "$WORK_DIR/BASELINES"
echo "Worktrees reset; run 'make init J=<jobs>' before building"
