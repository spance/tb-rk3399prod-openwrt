#!/usr/bin/env bash

export PATH=${TB_HOST_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(readlink -m "${TB_WORK_DIR:-$PROJECT_DIR/.work}")
OUT_DIR=$(readlink -m "${TB_OUT_DIR:-$PROJECT_DIR/out}")
DIST_DIR=$(readlink -m "${TB_DIST_DIR:-$PROJECT_DIR/dist}")

UBOOT_URL=https://github.com/rockchip-toybrick/u-boot.git
UBOOT_COMMIT=22af63bad708ff41513375a8ecf7fe8d2d521c84
RKBIN_URL=https://github.com/rockchip-toybrick/rkbin.git
RKBIN_COMMIT=78c1c4939634a76f6f4531c912c1a52a83f0451b
TOOLCHAIN_URL=https://github.com/rockchip-toybrick/linux-x86.git
TOOLCHAIN_COMMIT=32505a8032d04e9320dbdb817b08bf67bdfb5a0c
OPENWRT_URL=https://git.openwrt.org/openwrt/openwrt.git
OPENWRT_TAG=v25.12.5
OPENWRT_COMMIT=f0a60eee2fe051741c643ea6118718aae1ef17fb

fail() { echo "ERROR: $*" >&2; exit 1; }

retry()
{
	attempts=$1
	delay=$2
	shift 2
	current=1
	until "$@"; do
		[ "$current" -lt "$attempts" ] || return 1
		echo "Command failed; retrying in ${delay}s ($current/$attempts)..." >&2
		sleep "$delay"
		current=$((current + 1))
	done
}

require_case_sensitive_dir()
{
	dir=$1
	mkdir -p "$dir"
	lower="$dir/.tb-case-check-$$-a"
	upper="$dir/.tb-case-check-$$-A"
	: > "$lower"
	if [ -e "$upper" ]; then
		rm -f -- "$lower"
		fail "work directory must be on a case-sensitive Linux filesystem: $dir"
	fi
	rm -f -- "$lower"
}

ensure_checkout()
{
	url=$1
	ref=$2
	commit=$3
	dest=$4

	if [ -e "$dest" ] && [ ! -d "$dest/.git" ]; then
		fail "existing path is not a Git checkout: $dest"
	fi
	if [ ! -d "$dest/.git" ]; then
		mkdir -p "$(dirname -- "$dest")"
		git init "$dest"
	fi
	origin=$(git -C "$dest" remote get-url origin 2>/dev/null || true)
	if [ -z "$origin" ]; then
		git -C "$dest" remote add origin "$url"
	elif [ "$origin" != "$url" ]; then
		fail "unexpected origin in $dest: $origin"
	fi
	if ! git -C "$dest" rev-parse --verify HEAD >/dev/null 2>&1; then
		retry 3 10 git -C "$dest" fetch --depth=1 origin "$ref"
		git -C "$dest" checkout --detach FETCH_HEAD
	fi
	[ "$(git -C "$dest" rev-parse HEAD)" = "$commit" ] || \
		fail "unexpected commit in $dest"
}

apply_patch_set()
{
	dest=$1
	marker=$2
	shift 2

	if [ -f "$dest/$marker" ]; then
		git -C "$dest" apply --reverse --check "$@" || \
			fail "patch marker exists but patch state is inconsistent: $dest"
		return
	fi

	git -C "$dest" apply --check "$@"
	git -C "$dest" apply "$@"
	git -C "$dest" diff --check
	: > "$dest/$marker"
}

reset_generated_dir()
{
	dir=$(readlink -m "$1")
	[ "$dir" != "$OUT_DIR" ] || fail "refusing to reset OUT_DIR itself"
	case "$dir/" in
		"$OUT_DIR/"*) ;;
		*) fail "refusing to reset directory outside OUT_DIR: $dir" ;;
	esac
	rm -rf -- "$dir"
	mkdir -p "$dir"
}
