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
OPENWRT_VERSION=${OPENWRT_TAG#v}
LINUX_VERSION=6.12.94

# Raw eMMC layout inherited from the vendor GPT. Values are 512-byte LBAs.
SECTOR_SIZE=512
UBOOT_LBA=$((0x2000))
TRUST_LBA=$((0x4000))
BOOT_LINUX_LBA=$((0x6000))
ROOTFS_LBA=$((0x36000))
BOOT_LINUX_IMAGE_SIZE=$((64 * 1024 * 1024))
ROOTFS_IMAGE_SIZE=$((128 * 1024 * 1024))
OPENWRT_ROOTFS_OFFSET=$(((ROOTFS_LBA - BOOT_LINUX_LBA) * SECTOR_SIZE))
OPENWRT_IMAGE_SIZE=$((OPENWRT_ROOTFS_OFFSET + ROOTFS_IMAGE_SIZE))

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

ensure_patches_applied()
{
	dest=$1
	shift

	for patch in "$@"; do
		[ -f "$patch" ] || fail "patch file not found: $patch"
		if git -C "$dest" apply --reverse --check "$patch" \
			>/dev/null 2>&1; then
			continue
		fi
		git -C "$dest" apply --check "$patch" || \
			fail "patch does not apply cleanly: $patch"
		git -C "$dest" apply "$patch"
	done

	git -C "$dest" diff --check
	for patch in "$@"; do
		git -C "$dest" apply --reverse --check "$patch" || \
			fail "applied patch cannot be verified: $patch"
	done
}

feeds_match_config()
{
	openwrt_dir=$1
	feeds_config=$2
	expected=0

	while read -r kind name location extra; do
		case "$kind" in
		''|'#'*) continue ;;
		esac
		[ "$kind" = src-git ] || return 1
		[ -z "${extra:-}" ] || return 1
		url=${location%^*}
		commit=${location##*^}
		[ "$url" != "$location" ] || return 1
		expected=$((expected + 1))

		repo="$openwrt_dir/feeds/$name"
		[ -d "$repo/.git" ] || return 1
		[ -f "$openwrt_dir/feeds/$name.index" ] || return 1
		[ "$(git -C "$repo" remote get-url origin 2>/dev/null)" = "$url" ] || \
			return 1
		[ "$(git -C "$repo" rev-parse HEAD 2>/dev/null)" = "$commit" ] || \
			return 1
		git -C "$repo" diff --quiet || return 1
		git -C "$repo" diff --cached --quiet || return 1
	done < "$feeds_config"

	[ "$expected" -gt 0 ] || return 1
	actual=0
	for repo in "$openwrt_dir"/feeds/*; do
		[ -d "$repo/.git" ] || continue
		actual=$((actual + 1))
	done
	[ "$actual" -eq "$expected" ]
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

mark_managed_dir()
{
	local dir kind
	dir=$(readlink -m "$1")
	kind=$2
	mkdir -p "$dir"
	printf 'tb-rk3399prod:%s\n' "$kind" > \
		"$dir/.tb-rk3399prod-managed"
}
