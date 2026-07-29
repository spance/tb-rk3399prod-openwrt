#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 0 ] || fail "usage: $0"
remove_openwrt_kernel_build_state "$WORK_DIR/openwrt"
