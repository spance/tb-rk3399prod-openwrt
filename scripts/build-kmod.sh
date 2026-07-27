#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

[ "$#" -eq 2 ] || fail "usage: $0 jobs 'kmod-package ...'"
jobs=$1
kmods_raw=$2
case "$jobs" in
	''|*[!0-9]*) fail "jobs must be a positive integer" ;;
esac
[ "$jobs" -gt 0 ] || fail "jobs must be greater than zero"
[ -n "$kmods_raw" ] || \
	fail "no packages requested; use make kmod KMODS='kmod-foo [kmod-bar]'"

normalized_kmods=$(normalize_kmod_names "$kmods_raw")
requested=()
if [ -n "$normalized_kmods" ]; then
	mapfile -t requested <<< "$normalized_kmods"
fi
[ "${#requested[@]}" -gt 0 ] || fail "no kmod package names were parsed"

bash "$SCRIPT_DIR/check-env.sh"
[ -d "$WORK_DIR/openwrt/.git" ] || \
	fail "OpenWrt worktree is not initialized; run make init first"
[ -f "$WORK_DIR/BASELINES" ] || \
	fail "initialization baseline record is missing; run make init first"
bash "$SCRIPT_DIR/check.sh"

source=$WORK_DIR/openwrt
metadata=$source/tmp/.packageinfo
[ -f "$metadata" ] || \
	fail "OpenWrt package metadata is missing; run make init first"

mapfile -d '' manifests < <(find "$OUT_DIR/openwrt" -maxdepth 1 -type f \
	-name '*toybrick_tb-rk3399prod.manifest' -print0 2>/dev/null)
[ "${#manifests[@]}" -eq 1 ] || \
	fail "expected one built TB-RK3399ProD manifest; run make openwrt first"
mapfile -t manifest_kernel_versions < <(awk \
	'$1 == "kernel" && $2 == "-" { print $3 }' "${manifests[0]}")
[ "${#manifest_kernel_versions[@]}" -eq 1 ] || \
	fail "firmware manifest does not contain exactly one kernel package version"
baseline_kernel_version=${manifest_kernel_versions[0]}
printf '%s\n' "$baseline_kernel_version" | grep -Eq \
	"^${LINUX_VERSION//./\\.}~[0-9a-f]{32}-r[0-9]+$" || \
	fail "unexpected firmware kernel package version: $baseline_kernel_version"

read_worktree_kernel_version()
{
	local records
	mapfile -d '' records < <(find "$source/staging_dir" -mindepth 2 \
		-maxdepth 2 -type f -name kernel.version -print0 2>/dev/null)
	[ "${#records[@]}" -eq 1 ] || return 1
	cat "${records[0]}"
}

worktree_kernel_version=$(read_worktree_kernel_version || true)
[ -n "$worktree_kernel_version" ] || \
	fail "OpenWrt kernel build record is missing; run make openwrt first"
[ "$worktree_kernel_version" = "$baseline_kernel_version" ] || \
	fail "OpenWrt build tree and out/openwrt firmware use different kernels; run make openwrt"

for package in "${requested[@]}"; do
	openwrt_package_source_makefile "$source" "$package" >/dev/null || \
		fail "package is not uniquely defined by the pinned OpenWrt sources: $package"
done

package_runtime_depends()
{
	local package_name
	package_name=$1
	awk -v wanted="$package_name" '
		$1 == "Package:" { active = ($2 == wanted) }
		active && /^Depends:[[:space:]]*/ {
			line = $0
			sub(/^Depends:[[:space:]]*/, "", line)
			print line
			exit
		}
	' "$metadata"
}

lock_dir=$WORK_DIR/.kmod-build.lock
mkdir "$lock_dir" 2>/dev/null || \
	fail "another kmod build is active, or a stale lock remains: $lock_dir"
config_backup=
candidate_config=
bundle_list=
source_dirs=
base_selected=
base_builtins=
stage=
next_config=
config_modified=0
kernel_build_started=0

restore_config()
{
	[ "$config_modified" -eq 1 ] || return 0
	cp "$config_backup" "$source/.config"
	touch "$source/.config"
	config_modified=0
}

cleanup()
{
	local status
	status=$?
	trap - EXIT INT TERM
	restore_config || status=1
	if [ "$status" -ne 0 ] && [ "$kernel_build_started" -eq 1 ]; then
		echo "Discarding candidate kernel state after unsuccessful kmod build..." >&2
		( cd "$source" && make target/linux/clean >/dev/null 2>&1 ) || true
		find "$source/bin" -type f -name 'kmod-*.apk' -delete \
			2>/dev/null || true
	fi
	[ -z "$stage" ] || rm -rf -- "$stage"
	[ -z "$next_config" ] || rm -f -- "$next_config"
	[ -z "$config_backup" ] || rm -f -- "$config_backup"
	[ -z "$candidate_config" ] || rm -f -- "$candidate_config"
	[ -z "$bundle_list" ] || rm -f -- "$bundle_list"
	[ -z "$source_dirs" ] || rm -f -- "$source_dirs"
	[ -z "$base_selected" ] || rm -f -- "$base_selected"
	[ -z "$base_builtins" ] || rm -f -- "$base_builtins"
	rmdir "$lock_dir" 2>/dev/null || true
	exit "$status"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

config_backup=$(mktemp "$WORK_DIR/.kmod-config.XXXXXX")
candidate_config=$(mktemp "$WORK_DIR/.kmod-candidate.XXXXXX")
bundle_list=$(mktemp "$WORK_DIR/.kmod-bundle.XXXXXX")
source_dirs=$(mktemp "$WORK_DIR/.kmod-sources.XXXXXX")
base_selected=$(mktemp "$WORK_DIR/.kmod-base-selected.XXXXXX")
base_builtins=$(mktemp "$WORK_DIR/.kmod-base-builtins.XXXXXX")
cp "$source/.config" "$config_backup"
cp "$config_backup" "$candidate_config"
for package in "${requested[@]}"; do
	if grep -Fqx "CONFIG_PACKAGE_$package=y" "$config_backup"; then
		fail "$package is already built into the current firmware"
	fi
	next_config=$(mktemp "$WORK_DIR/.kmod-next.XXXXXX")
	awk -v yes="CONFIG_PACKAGE_$package=y" \
		-v module="CONFIG_PACKAGE_$package=m" \
		-v disabled="# CONFIG_PACKAGE_$package is not set" \
		'$0 != yes && $0 != module && $0 != disabled { print }' \
		"$candidate_config" > "$next_config"
	printf 'CONFIG_PACKAGE_%s=m\n' "$package" >> "$next_config"
	mv -- "$next_config" "$candidate_config"
	next_config=
done
cp "$candidate_config" "$source/.config"
config_modified=1

(
	cd "$source"
	make defconfig </dev/null
)
for package in "${requested[@]}"; do
	grep -Fqx "CONFIG_PACKAGE_$package=m" "$source/.config" || \
		fail "package cannot be selected as a module for this target: $package"
done

sed -n 's/^CONFIG_PACKAGE_\(kmod-[^=]*\)=[my]$/\1/p' "$source/.config" | \
	LC_ALL=C sort -u > "$candidate_config"
sed -n 's/^CONFIG_PACKAGE_\(kmod-[^=]*\)=[my]$/\1/p' "$config_backup" | \
	LC_ALL=C sort -u > "$base_selected"
sed -n 's/^CONFIG_PACKAGE_\(kmod-[^=]*\)=y$/\1/p' "$config_backup" | \
	LC_ALL=C sort -u > "$base_builtins"
comm -13 "$base_selected" "$candidate_config" > "$bundle_list"

declare -A seen_dependencies=()
dependency_queue=("${requested[@]}")
queue_index=0
while [ "$queue_index" -lt "${#dependency_queue[@]}" ]; do
	package=${dependency_queue[$queue_index]}
	queue_index=$((queue_index + 1))
	[ -z "${seen_dependencies[$package]+present}" ] || continue
	seen_dependencies[$package]=1
	if ! grep -Fqx "$package" "$base_builtins"; then
		printf '%s\n' "$package" >> "$bundle_list"
	fi
	dependencies=$(package_runtime_depends "$package")
	for dependency in $dependencies; do
		while [ "${dependency#?}" != "$dependency" ]; do
			case "$dependency" in
				[+@]*) dependency=${dependency#?} ;;
				*) break ;;
			esac
		done
		case "$dependency" in
			*:*) dependency=${dependency##*:} ;;
		esac
		dependency=${dependency%%(*}
		dependency=${dependency%%@*}
		case "$dependency" in
			kmod-*) ;;
			*) continue ;;
		esac
		if grep -Fqx "CONFIG_PACKAGE_$dependency=m" "$source/.config" || \
			grep -Fqx "CONFIG_PACKAGE_$dependency=y" "$source/.config"; then
			dependency_queue+=("$dependency")
		fi
	done
done
LC_ALL=C sort -u "$bundle_list" -o "$bundle_list"
[ -s "$bundle_list" ] || fail "no installable kmod packages were selected"
for package in "${requested[@]}"; do
	grep -Fqx "$package" "$bundle_list" || \
		fail "requested package is not installable outside the current rootfs: $package"
done

while IFS= read -r package; do
	makefile=$(openwrt_package_source_makefile "$source" "$package") || \
		fail "selected dependency is not uniquely defined: $package"
	case "$makefile" in
		package/*/Makefile) ;;
		*) fail "unexpected OpenWrt package source path for $package: $makefile" ;;
	esac
	printf '%s\n' "${makefile%/Makefile}"
done < "$bundle_list" | LC_ALL=C sort -u > "$source_dirs"

run_openwrt_make()
{
	local target label
	target=$1
	label=$2
	(
		cd "$source"
		if ! make -j"$jobs" "$target" </dev/null; then
			echo "$label failed in parallel; retrying with -j1 V=sc" >&2
			make -j1 V=sc "$target" </dev/null
		fi
	)
}

run_openwrt_make download "OpenWrt source download"
kernel_build_started=1
run_openwrt_make target/linux/compile "OpenWrt kernel module build"
run_openwrt_make package/kernel/linux/compile "OpenWrt in-tree kmod packaging"
candidate_kernel_version=$(read_worktree_kernel_version || true)
[ -n "$candidate_kernel_version" ] || \
	fail "candidate kernel package version was not generated"
if [ "$candidate_kernel_version" != "$baseline_kernel_version" ]; then
	printf '%s\n' \
		"ERROR: requested modules change the kernel Kconfig ABI" \
		"ERROR: firmware kernel:  $baseline_kernel_version" \
		"ERROR: candidate kernel: $candidate_kernel_version" \
		"ERROR: refusing standalone APK output; rebuild and deploy a complete matching firmware" >&2
	exit 1
fi
while IFS= read -r source_dir; do
	[ "$source_dir" != package/kernel/linux ] || continue
	run_openwrt_make "$source_dir/compile" "OpenWrt package build: $source_dir"
done < "$source_dirs"

mark_managed_dir "$OUT_DIR" out
request_hash=$(printf '%s\n' "${requested[@]}" | sha256sum | cut -c1-12)
kernel_id=${candidate_kernel_version//\~/-}
dest=$OUT_DIR/kmods/$kernel_id/${requested[0]}-$request_hash
stage=$(mktemp -d "$OUT_DIR/.kmod-stage.XXXXXX")

while IFS= read -r package; do
	mapfile -d '' package_files < <(find "$source/bin" -type f \
		-name "${package}-${LINUX_VERSION}*.apk" -print0)
	[ "${#package_files[@]}" -eq 1 ] || \
		fail "expected exactly one APK for $package, found ${#package_files[@]}"
	install -m 0644 "${package_files[0]}" "$stage/"
done < "$bundle_list"

printf '%s\n' "${requested[@]}" > "$stage/REQUESTED"
cp "$bundle_list" "$stage/PACKAGES"
printf '%s\n' \
	"openwrt_version=$OPENWRT_VERSION" \
	"openwrt_commit=$OPENWRT_COMMIT" \
	"linux_version=$LINUX_VERSION" \
	"kernel_package=$candidate_kernel_version" \
	"target=rockchip/armv8" > "$stage/BUILDINFO"
cat > "$stage/INSTALL.txt" <<EOF
These APKs were built for:
  kernel $candidate_kernel_version

Verify that the device runs exactly this kernel package version before installing.
Copy this directory to the device, then install the complete dependency bundle:
  apk add --allow-untrusted /tmp/tb-kmods/*.apk

Do not force installation on a different kernel. Remove or rebuild these packages
before upgrading the firmware kernel.
EOF

(
	cd "$stage"
	find . -maxdepth 1 -type f ! -name SHA256SUMS -print0 | \
		LC_ALL=C sort -z | xargs -0 -r sha256sum > SHA256SUMS
)
reset_generated_dir "$dest"
rmdir "$dest"
mv -- "$stage" "$dest"
stage=
restore_config

printf '%s\n' \
	"Compatible kmod bundle: $dest" \
	"Kernel package: $candidate_kernel_version" \
	"Requested: ${requested[*]}"
