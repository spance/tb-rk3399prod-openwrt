#!/usr/bin/env bash

export PATH=${TB_HOST_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}

PROJECT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
WORK_DIR=$(readlink -m "${TB_WORK_DIR:-$PROJECT_DIR/.work}")
OUT_DIR=$(readlink -m "${TB_OUT_DIR:-$PROJECT_DIR/out}")
DIST_DIR=$(readlink -m "${TB_DIST_DIR:-$PROJECT_DIR/dist}")

UBOOT_URL=https://github.com/rockchip-linux/u-boot.git
UBOOT_COMMIT=aeec6f2bfd5ce0cfcdfe0ffc7f84d9d143683856
RKBIN_URL=https://github.com/rockchip-linux/rkbin.git
RKBIN_COMMIT=ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4
RKBIN_DDR_VERSION=1.30
RKBIN_MINILOADER_VERSION=1.26
RKBIN_BL31_VERSION=1.35
RKBIN_BL32_VERSION=2.12
RKBIN_LOADER_IMAGE=rk3399pro_loader_v1.30.126.bin
RKBIN_LOADER_IMAGE_SIZE=452942
RKBIN_LOADER_DDR_SIZE=147456
RKBIN_LOADER_DDR_SHA256=e35891be5ac1cd75230544530a5d7923e0cd59d31dd9f0138696f0e5de987ad3
RKBIN_LOADER_MINILOADER_SIZE=86016
RKBIN_LOADER_MINILOADER_SHA256=6f5e885f968225711f99ef4bd70f26551c11393bc90a6c853f032be67e42d93c
RKBIN_LOADER_USBPLUG_SIZE=71680
RKBIN_LOADER_USBPLUG_SHA256=099876f8d98e22dce58894d40176f5d49c6460edd3c417ed42f9cc952fd28979
RKBIN_TRUST_IMAGE=trust.img
RKBIN_TRUST_IMAGE_SIZE=4194304
RKBIN_TRUST_IMAGE_SHA256=63ce40c87dc3cb0c0d8e84b46acb95fa5ab39601c77bfbedf3e112fb4c30d774
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

verify_sha256()
{
	local file expected actual
	file=$1
	expected=$2
	[ -f "$file" ] || fail "file not found for SHA256 verification: $file"
	actual=$(sha256sum "$file" | awk '{ print $1 }')
	[ "$actual" = "$expected" ] || \
		fail "SHA256 mismatch for $file: expected $expected, got $actual"
}

remove_openwrt_kernel_build_state()
{
	local source path resolved removed
	source=$(readlink -m "$1")
	case "$source/" in
		"$WORK_DIR/"*) ;;
		*) fail "refusing to clean an OpenWrt tree outside TB_WORK_DIR: $source" ;;
	esac
	[ -d "$source/.git" ] || \
		fail "OpenWrt worktree is not initialized: $source"
	removed=0

	for path in "$source"/build_dir/target-*/linux-rockchip_armv8; do
		[ -e "$path" ] || continue
		resolved=$(readlink -m "$path")
		case "$resolved/" in
			"$source/build_dir/"*/linux-rockchip_armv8/) ;;
			*) fail "refusing to remove unexpected kernel build path: $resolved" ;;
		esac
		rm -rf -- "$resolved"
		echo "Removed OpenWrt kernel build directory: $resolved"
		removed=1
	done

	for path in "$source"/staging_dir/target-*/stamp/.target_compile; do
		[ -e "$path" ] || continue
		resolved=$(readlink -m "$path")
		case "$resolved" in
			"$source/staging_dir/"*/stamp/.target_compile) ;;
			*) fail "refusing to remove unexpected target stamp: $resolved" ;;
		esac
		rm -f -- "$resolved"
		echo "Removed OpenWrt target compile stamp: $resolved"
		removed=1
	done

	[ "$removed" -eq 1 ] || \
		echo "OpenWrt kernel build state is already clean: $source"
}

normalize_kmod_names()
{
	local raw package
	local -a input
	raw=$1
	[ -n "$raw" ] || return 0
	read -r -a input <<< "$raw"
	for package in "${input[@]}"; do
		printf '%s\n' "$package" | grep -Eq \
			'^kmod-[a-z0-9][a-z0-9+._-]*$' || \
			fail "invalid kmod package name: $package"
	done
	printf '%s\n' "${input[@]}" | LC_ALL=C sort -u
}

openwrt_package_source_makefile()
{
	local openwrt_dir package_name metadata
	openwrt_dir=$1
	package_name=$2
	metadata=$openwrt_dir/tmp/.packageinfo
	[ -f "$metadata" ] || return 1
	awk -v wanted="$package_name" '
		/^Source-Makefile:[[:space:]]*/ {
			source = $0
			sub(/^Source-Makefile:[[:space:]]*/, "", source)
			next
		}
		$1 == "Package:" && $2 == wanted {
			count++
			answer = source
		}
		END {
			if (count == 1 && answer != "")
				print answer
			else
				exit 1
		}
	' "$metadata"
}

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
