#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 0 ] || fail "usage: $0"

remove_managed_output()
{
	local dir kind default_dir marker
	dir=$(readlink -m "$1")
	kind=$2
	default_dir=$(readlink -m "$PROJECT_DIR/$kind")

	[ "$dir" != / ] || fail "refusing to remove filesystem root"
	[ "$dir" != "$PROJECT_DIR" ] || fail "refusing to remove project root"
	[ "$dir" != "$WORK_DIR" ] || fail "refusing to remove work directory"
	if [ -n "${HOME:-}" ]; then
		[ "$dir" != "$(readlink -m "$HOME")" ] || \
			fail "refusing to remove the home directory"
	fi

	[ -e "$dir" ] || return 0
	if [ "$dir" != "$default_dir" ]; then
		marker="$dir/.tb-rk3399prod-managed"
		[ -f "$marker" ] || \
			fail "custom $kind directory is not marked as project-managed: $dir"
		[ "$(cat "$marker")" = "tb-rk3399prod:$kind" ] || \
			fail "unexpected project marker in $dir"
	fi
	rm -rf -- "$dir"
	echo "Removed $kind directory: $dir"
}

[ "$OUT_DIR" != "$DIST_DIR" ] || \
	fail "TB_OUT_DIR and TB_DIST_DIR must not resolve to the same directory"
remove_managed_output "$OUT_DIR" out
remove_managed_output "$DIST_DIR" dist
