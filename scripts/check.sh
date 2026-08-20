#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
# shellcheck source=lib.sh
. "$SCRIPT_DIR/lib.sh"

assert_file()
{
	[ -f "$1" ] || fail "required project file not found: $1"
}

assert_exact_line()
{
	file=$1
	line=$2
	[ "$(grep -Fxc -- "$line" "$file")" -eq 1 ] || \
		fail "expected exactly one line in $file: $line"
}

for script in "$SCRIPT_DIR"/*.sh; do
	bash -n "$script"
done
bash "$SCRIPT_DIR/test-net-tuning.sh"
for script in "$PROJECT_DIR"/rootfs/etc/init.d/* \
	"$PROJECT_DIR"/rootfs/etc/uci-defaults/* \
	"$PROJECT_DIR"/rootfs/etc/hotplug.d/iface/* \
	"$PROJECT_DIR"/rootfs/usr/sbin/*; do
	sh -n "$script"
done

if grep -Eq 'scripts/feeds|make[[:space:]]+(defconfig|download)|init\.sh' \
	"$SCRIPT_DIR/build.sh"; then
	fail "build stage must not initialize feeds, configuration or downloads"
fi
grep -Fq './scripts/feeds update -a' "$SCRIPT_DIR/init.sh" || \
	fail "init stage does not update OpenWrt feeds"
grep -Fq 'make defconfig' "$SCRIPT_DIR/init.sh" || \
	fail "init stage does not generate the OpenWrt configuration"
grep -Fq 'make download' "$SCRIPT_DIR/init.sh" || \
	fail "init stage does not download OpenWrt source archives"
grep -Fq 'normalize_kmod_names "$kmods_raw"' "$SCRIPT_DIR/init.sh" || \
	fail "init stage does not validate the optional kmod pool"
grep -Fq 'kmod package is already built into the firmware' \
	"$SCRIPT_DIR/init.sh" || \
	fail "init stage can demote an in-firmware driver into the optional kmod pool"

# A patch file's own context lines intentionally begin with one space.  When a
# new patch is itself shown in a repository diff, Git's outer whitespace check
# misreads those context prefixes as indentation.  Validate project sources
# here and validate patch payloads structurally below.
git -C "$PROJECT_DIR" diff --check -- . \
	':(exclude,glob)patches/**/*.patch'
git -C "$PROJECT_DIR" diff --cached --check -- . \
	':(exclude,glob)patches/**/*.patch'

if git -C "$PROJECT_DIR" ls-files | grep -Eq \
	'(^|/)(debug|logs?|captures?)(/|$)|(^|/)(dmesg|info|eth[0-9]+|iperf|ethtool).*\.txt$|\.(log|dump|trace)$'; then
	fail "tracked debug capture or device-state file found"
fi

openwrt_patch="$PROJECT_DIR/patches/openwrt/0001-tb-rk3399prod-board-support.patch"
kernel_patch_dir="$PROJECT_DIR/patches/kernel"
typec_phy_patch="$kernel_patch_dir/144-phy-rockchip-typec-orientation-switch.patch"
typec_dwc_patch="$kernel_patch_dir/145-usb-dwc3-rk3399-typec-runtime-pm.patch"
ddr_probe_patch="$kernel_patch_dir/146-devfreq-rk3399-round-rate-probe-only.patch"
pcie_switch_patch="$kernel_patch_dir/147-pcie-rockchip-pi7c9x2g304-safe-scan.patch"
uboot_patch="$PROJECT_DIR/patches/u-boot/0001-tb-rk3399prod-board-support.patch"
assert_file "$openwrt_patch"
assert_file "$typec_phy_patch"
assert_file "$typec_dwc_patch"
assert_file "$ddr_probe_patch"
assert_file "$pcie_switch_patch"
assert_file "$uboot_patch"
assert_file "$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dts"
assert_file "$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi"
assert_file "$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning"
assert_file "$PROJECT_DIR/rootfs/etc/hotplug.d/iface/90-tb-net-tuning"
assert_file "$PROJECT_DIR/rootfs/etc/uci-defaults/99-tb-network-offload"
assert_file "$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag"
assert_file "$PROJECT_DIR/rootfs/usr/sbin/tb-rtl8125-diag"
assert_file "$PROJECT_DIR/configs/openwrt.config"
assert_file "$PROJECT_DIR/configs/feeds.conf"
assert_file "$PROJECT_DIR/boot/boot.cmd"
assert_file "$PROJECT_DIR/scripts/clean.sh"
assert_file "$PROJECT_DIR/scripts/clean-openwrt-kernel.sh"
assert_file "$PROJECT_DIR/scripts/build-kmod.sh"
assert_file "$PROJECT_DIR/scripts/make-openwrt-image.sh"
assert_file "$PROJECT_DIR/scripts/reset.sh"
assert_file "$PROJECT_DIR/scripts/sync-openwrt-rootfs.sh"
assert_file "$PROJECT_DIR/scripts/sync-openwrt-kernel-patches.sh"
assert_file "$PROJECT_DIR/scripts/verify-openwrt-image.sh"
assert_file "$PROJECT_DIR/scripts/verify-rkbin-images.sh"
assert_file "$PROJECT_DIR/docs/BOOT-CHAIN.md"
assert_file "$PROJECT_DIR/docs/DDR-DVFS.md"
assert_file "$PROJECT_DIR/docs/HDMI-CONSOLE.md"
assert_file "$PROJECT_DIR/docs/KMOD-BUILDER.md"
assert_file "$PROJECT_DIR/docs/NETWORK-PERFORMANCE.md"
assert_file "$PROJECT_DIR/docs/PCIE-RTL8125.md"
assert_file "$PROJECT_DIR/docs/USB-TYPE-C.md"

grep -Fq '## 适配分层与改造点' "$PROJECT_DIR/README.md" || \
	fail "README does not describe the project adaptation layers"
grep -Fq '## 硬件支持矩阵' "$PROJECT_DIR/README.md" || \
	fail "README does not expose the board hardware support matrix"
grep -Fq '## 实测性能' "$PROJECT_DIR/README.md" || \
	fail "README does not publish the measured performance baseline"
if grep -Eq '8 ?(GiB|GB|G)[[:space:]]*内存|8G内存|内存(的)?主机.*8 ?(GiB|GB|G)' \
	"$PROJECT_DIR/README.md" "$PROJECT_DIR/docs/BUILD.md"; then
	fail "non-portable 8 GiB build-host guidance remains"
fi
grep -Fq '达到板级工程交付条件' \
	"$PROJECT_DIR/docs/USB-TYPE-C.md" || \
	fail "Type-C acceptance result is missing from the canonical document"
if grep -R -Eq '待新镜像验收|重构后的热插拔待|Type-C.*生命周期重构待验收' \
	"$PROJECT_DIR/README.md" "$PROJECT_DIR/docs"; then
	fail "stale Type-C pre-acceptance wording remains in project documentation"
fi

grep -Fq '$(filter -j%,$(MAKEFLAGS))' "$PROJECT_DIR/Makefile" || \
	fail "Makefile must derive parallelism from GNU Make -j"
for file in "$PROJECT_DIR/Makefile" "$PROJECT_DIR/README.md" \
	"$PROJECT_DIR/docs/BUILD.md"; do
	if grep -Eq 'make .*\b(J|JOBS)=[0-9]' "$file"; then
		fail "non-standard parallelism variable remains in $file"
	fi
done
grep -Fq 'bash scripts/clean.sh' "$PROJECT_DIR/Makefile" || \
	fail "Makefile clean target is missing"
grep -Fq 'bash scripts/clean-openwrt-kernel.sh' "$PROJECT_DIR/Makefile" || \
	fail "Makefile kernel-clean target is missing"
grep -Fq 'remove_openwrt_kernel_build_state "$openwrt_dir"' \
	"$PROJECT_DIR/scripts/sync-openwrt-kernel-patches.sh" || \
	fail "changed canonical kernel patches do not invalidate the kernel build"
grep -Fq 'remove_openwrt_kernel_build_state "$source"' \
	"$PROJECT_DIR/scripts/build-kmod.sh" || \
	fail "failed kmod builds do not use the non-interactive kernel cleanup"
if grep -R -Eq 'make[[:space:]]+target/linux/clean' "$PROJECT_DIR/scripts"; then
	fail "OpenWrt target/linux/clean can enter interactive configuration"
fi
grep -Fq 'bash scripts/reset.sh' "$PROJECT_DIR/Makefile" || \
	fail "Makefile reset target is missing"
grep -Fq 'bash scripts/build-kmod.sh "$(MAKE_JOBS)" "$(KMODS)"' \
	"$PROJECT_DIR/Makefile" || \
	fail "Makefile kmod target is missing"
assert_exact_line "$PROJECT_DIR/scripts/lib.sh" \
	'UBOOT_URL=https://github.com/rockchip-linux/u-boot.git'
assert_exact_line "$PROJECT_DIR/scripts/lib.sh" \
	'UBOOT_COMMIT=aeec6f2bfd5ce0cfcdfe0ffc7f84d9d143683856'
assert_exact_line "$PROJECT_DIR/scripts/lib.sh" \
	'RKBIN_URL=https://github.com/rockchip-linux/rkbin.git'
assert_exact_line "$PROJECT_DIR/scripts/lib.sh" \
	'RKBIN_COMMIT=ecb4fcbe954edf38b3ae037d5de6d9f5bccf81f4'
for firmware_setting in \
	'RKBIN_LOADER_IMAGE=rk3399pro_loader_v1.30.126.bin' \
	'RKBIN_LOADER_IMAGE_SIZE=452942' \
	'RKBIN_LOADER_DDR_SIZE=147456' \
	'RKBIN_LOADER_DDR_SHA256=e35891be5ac1cd75230544530a5d7923e0cd59d31dd9f0138696f0e5de987ad3' \
	'RKBIN_LOADER_MINILOADER_SIZE=86016' \
	'RKBIN_LOADER_MINILOADER_SHA256=6f5e885f968225711f99ef4bd70f26551c11393bc90a6c853f032be67e42d93c' \
	'RKBIN_LOADER_USBPLUG_SIZE=71680' \
	'RKBIN_LOADER_USBPLUG_SHA256=099876f8d98e22dce58894d40176f5d49c6460edd3c417ed42f9cc952fd28979' \
	'RKBIN_TRUST_IMAGE=trust.img' \
	'RKBIN_TRUST_IMAGE_SIZE=4194304' \
	'RKBIN_TRUST_IMAGE_SHA256=63ce40c87dc3cb0c0d8e84b46acb95fa5ab39601c77bfbedf3e112fb4c30d774'; do
	assert_exact_line "$PROJECT_DIR/scripts/lib.sh" "$firmware_setting"
done
grep -Fq 'bash "$SCRIPT_DIR/verify-rkbin-images.sh" "$loader" "$trust"' \
	"$PROJECT_DIR/scripts/build.sh" || \
	fail "U-Boot build does not structurally verify loader and trust images"
grep -Fq './make.sh "CROSS_COMPILE=$uboot_cross" rk3399pro' \
	"$PROJECT_DIR/scripts/build.sh" || \
	fail "U-Boot build does not pass the pinned cross compiler explicitly"
grep -Fq "grep -aFq 'optee api revision: %d.%d'" \
	"$PROJECT_DIR/scripts/build.sh" || \
	fail "U-Boot build does not verify the compatible OP-TEE client"
grep -Fq 'uboot_identity="tb-rk3399prod-g${UBOOT_COMMIT:0:7}"' \
	"$PROJECT_DIR/scripts/build.sh" || \
	fail "U-Boot build does not verify the pinned source identity"
if grep -Eq 'strings .*u-boot\.bin.*\|' "$PROJECT_DIR/scripts/build.sh"; then
	fail "U-Boot binary checks must not use a pipe that fails under pipefail"
fi
grep -Fq '"$boot_merger" unpack -i "$loader" -o "$stage"' \
	"$PROJECT_DIR/scripts/verify-rkbin-images.sh" || \
	fail "loader verification does not use the pinned official unpacker"
grep -Fq '"$OUT_DIR/uboot/$RKBIN_LOADER_IMAGE"' \
	"$PROJECT_DIR/scripts/package.sh" || \
	fail "release package does not require the official loader"
grep -Fq '"$OUT_DIR/uboot/$RKBIN_TRUST_IMAGE"' \
	"$PROJECT_DIR/scripts/package.sh" || \
	fail "release package does not require the official trust image"
grep -Fq '+CONFIG_LOADER_INI="RK3399PROMINIALL.ini"' "$uboot_patch" || \
	fail "U-Boot patch does not pin the RK3399Pro loader INI"
grep -Fq '+CONFIG_TRUST_INI="RK3399PROTRUST.ini"' "$uboot_patch" || \
	fail "U-Boot patch does not pin the RK3399Pro trust INI"
grep -Fq 'fifo-mode;' "$uboot_patch" || \
	fail "U-Boot patch does not force the reliable TF FIFO path"
grep -Fq 'if (!host->fifo_mode) {' "$uboot_patch" || \
	fail "U-Boot patch does not preserve the board DT FIFO request"
grep -Fq 'Standard mkimage uses zero as the terminating size entry' \
	"$uboot_patch" || \
	fail "U-Boot patch does not support standard legacy script images"
grep -Fq '*data != IMAGE_PARAM_INVAL' "$uboot_patch" || \
	fail "U-Boot patch no longer supports the Rockchip script terminator"
grep -Fq 'env_get_yesno("bootm-no-reloc") != 1' "$uboot_patch" || \
	fail "U-Boot patch does not require an explicit no-relocation setting"
grep -Fq '#if defined(CONFIG_FIT_CIPHER) || defined(CONFIG_FIT_IMAGE_POST_PROCESS)' \
	"$uboot_patch" || \
	fail "U-Boot patch still requires load addresses for ordinary FIT images"
grep -Fq 'Failed to load FDT from FIT image' "$uboot_patch" || \
	fail "U-Boot patch does not reject failed FIT FDT loads"
grep -Fq 'if (*fit_uname_config_copy)' "$uboot_patch" || \
	fail "U-Boot patch retains unsafe FIT configuration-name parsing"
grep -Fq '#define CONFIG_BOOTCOMMAND "run distro_bootcmd"' \
	"$uboot_patch" || \
	fail "RK3399Pro U-Boot does not enter standard distro boot directly"
grep -Eq '^\+#define CONFIG_SYS_BOOTM_LEN[[:space:]]+\(128 << 20\)' \
	"$uboot_patch" || \
	fail "RK3399Pro U-Boot does not allow the 128 MiB recovery kernel window"
if grep -Fq 'diff --git a/make.sh b/make.sh' "$uboot_patch"; then
	fail "current Rockchip U-Boot must use its native rkbin packaging scripts"
fi
grep -Fq './tools/trust_merger RKTRUST/RK3399PROTRUST.ini' \
	"$PROJECT_DIR/docs/EMMC-INSTALL.md" || \
	fail "official trust generation command is not documented"
grep -Fq './tools/boot_merger RKBOOT/RK3399PROMINIALL.ini' \
	"$PROJECT_DIR/docs/EMMC-INSTALL.md" || \
	fail "official loader generation command is not documented"
grep -Fq '同一下载镜像会话' "$PROJECT_DIR/docs/EMMC-INSTALL.md" || \
	fail "eMMC deployment guide does not require paired U-Boot/trust writes"
grep -Fq 'optee api revision mismatch with u-boot/kernel' \
	"$PROJECT_DIR/docs/EMMC-INSTALL.md" || \
	fail "eMMC deployment guide is missing the observed compatibility failure"
if grep -Eq '先只(写|换|刷).*trust\.img' \
	"$PROJECT_DIR/docs/EMMC-INSTALL.md" \
	"$PROJECT_DIR/docs/BOOT-CHAIN.md"; then
	fail "U-Boot and trust must not be documented as independent boot trials"
fi
grep -Fq 'bash scripts/init.sh "$(MAKE_JOBS)" "$(KMODS)"' \
	"$PROJECT_DIR/Makefile" || \
	fail "Makefile does not pass the optional kmod pool to init"
grep -Fq 'mark_managed_dir "$OUT_DIR" out' "$PROJECT_DIR/scripts/build.sh" || \
	fail "custom output directories are not marked as project-managed"
grep -Fq 'mark_managed_dir "$DIST_DIR" dist' \
	"$PROJECT_DIR/scripts/package.sh" || \
	fail "custom distribution directories are not marked as project-managed"
grep -Fq '"$SCRIPT_DIR/make-openwrt-image.sh"' \
	"$PROJECT_DIR/scripts/build.sh" || \
	fail "OpenWrt deployment image is not assembled by the build stage"
grep -Fq '"$OUT_DIR/openwrt/openwrt.img"' \
	"$PROJECT_DIR/scripts/package.sh" || \
	fail "release package does not require the combined OpenWrt image"
grep -Fq 'candidate_kernel_version' "$PROJECT_DIR/scripts/build-kmod.sh" || \
	fail "kmod builder does not validate the candidate kernel"
grep -Fq 'baseline_kernel_version' "$PROJECT_DIR/scripts/build-kmod.sh" || \
	fail "kmod builder does not validate against the firmware manifest"
grep -Fq 'refusing standalone APK output' \
	"$PROJECT_DIR/scripts/build-kmod.sh" || \
	fail "kmod builder does not reject a changed kernel ABI"
grep -Fq 'restore_config' "$PROJECT_DIR/scripts/build-kmod.sh" || \
	fail "kmod builder does not restore the formal OpenWrt configuration"
grep -Fq 'out/kmods/' "$PROJECT_DIR/docs/KMOD-BUILDER.md" || \
	fail "kmod output layout is not documented"
if grep -Eq -- '--force-depends|insmod[[:space:]]+-f|\.vermagic.*(printf|echo|sed)' \
	"$PROJECT_DIR/scripts/build-kmod.sh"; then
	fail "unsafe kmod compatibility override is present"
fi
for layout in \
	'SECTOR_SIZE=512' \
	'UBOOT_LBA=$((0x2000))' \
	'TRUST_LBA=$((0x4000))' \
	'BOOT_LINUX_LBA=$((0x6000))' \
	'ROOTFS_LBA=$((0x36000))' \
	'BOOT_LINUX_IMAGE_SIZE=$((64 * 1024 * 1024))' \
	'ROOTFS_IMAGE_SIZE=$((128 * 1024 * 1024))'; do
	grep -Fqx "$layout" "$PROJECT_DIR/scripts/lib.sh" || \
		fail "eMMC image layout setting is missing: $layout"
done
[ "$OPENWRT_ROOTFS_OFFSET" -eq 100663296 ] || \
	fail "combined image rootfs offset is not exactly 96 MiB"
[ "$OPENWRT_IMAGE_SIZE" -eq 234881024 ] || \
	fail "combined OpenWrt image is not exactly 224 MiB"
[ $((BOOT_LINUX_LBA + OPENWRT_ROOTFS_OFFSET / SECTOR_SIZE)) \
	-eq "$ROOTFS_LBA" ] || \
	fail "combined image rootfs does not land at the vendor rootfs LBA"
if grep -Eq 'git[[:space:]].*(reset|clean)' "$PROJECT_DIR/scripts/clean.sh"; then
	fail "ordinary clean must not mutate Git worktrees"
fi
grep -Fq 'git -C "$repo" reset --hard "$expected_commit"' \
	"$PROJECT_DIR/scripts/reset.sh" || \
	fail "reset does not reset verified repositories"
grep -Fq 'git -C "$repo" clean -fd' \
	"$PROJECT_DIR/scripts/reset.sh" || \
	fail "reset does not remove untracked source changes"

[ "$(find "$PROJECT_DIR/patches/openwrt" -mindepth 1 -maxdepth 1 \
	-type d | wc -l)" -eq 0 ] || \
	fail "OpenWrt patch directory must not contain subdirectories"
[ "$(find "$PROJECT_DIR/patches/openwrt" -maxdepth 1 -type f \
	-name '*.patch' | wc -l)" -eq 1 ] || \
	fail "exactly one current OpenWrt patch is required"
for patch in "$PROJECT_DIR"/patches/openwrt/*.patch; do
	git apply --numstat "$patch" >/dev/null
done

[ "$(find "$kernel_patch_dir" -mindepth 1 -maxdepth 1 -type d | wc -l)" -eq 0 ] || \
	fail "kernel patch directory must not contain subdirectories"
[ "$(find "$kernel_patch_dir" -maxdepth 1 -type f -name '*.patch' | wc -l)" -eq 4 ] || \
	fail "exactly four canonical kernel patches are required"
for patch in "$kernel_patch_dir"/*.patch; do
	git apply --numstat "$patch" >/dev/null
done
grep -Fq 'PCI_DEVICE_ID_PERICOM_PI7C9X2G304SV' "$pcie_switch_patch" || \
	fail "PI7C9X2G304SV switch topology quirk is missing"
grep -Fq 'PCI_EXP_LNKSTA_DLLLA' "$pcie_switch_patch" || \
	fail "PI7C9X2G304SV empty-link guard is missing"

[ "$(find "$PROJECT_DIR/patches/u-boot" -mindepth 1 -maxdepth 1 \
	-type d | wc -l)" -eq 0 ] || \
	fail "U-Boot patch directory must not contain subdirectories"
[ "$(find "$PROJECT_DIR/patches/u-boot" -maxdepth 1 -type f \
	-name '*.patch' | wc -l)" -eq 1 ] || \
	fail "exactly one current U-Boot patch is required"
for patch in "$PROJECT_DIR"/patches/u-boot/*.patch; do
	git apply --numstat "$patch" >/dev/null
done

if grep -Eq '^diff --git a/.*rk3399pro-toybrick-prod\.dtsi? ' \
	"$openwrt_patch"; then
	fail "canonical board DTS files must not be duplicated in patches"
fi

assert_exact_line "$PROJECT_DIR/configs/openwrt.config" \
	'CONFIG_TARGET_rockchip_armv8_DEVICE_toybrick_tb-rk3399prod=y'
assert_exact_line "$PROJECT_DIR/configs/openwrt.config" \
	'CONFIG_TARGET_ROOTFS_SQUASHFS=y'
assert_exact_line "$PROJECT_DIR/configs/openwrt.config" \
	'CONFIG_TARGET_ROOTFS_INITRAMFS=y'
assert_exact_line "$PROJECT_DIR/configs/openwrt.config" \
	'CONFIG_DROPBEAR_SFTPSERVER=y'
assert_exact_line "$PROJECT_DIR/configs/openwrt.config" 'CONFIG_USE_MUSL=y'
if grep -Fqx 'CONFIG_USE_GLIBC=y' "$PROJECT_DIR/configs/openwrt.config"; then
	fail "glibc must not be selected for the OpenWrt target"
fi

[ "$(wc -l < "$PROJECT_DIR/configs/feeds.conf")" -eq 2 ] || \
	fail "configs/feeds.conf must contain exactly the packages and LuCI feeds"
while IFS= read -r feed; do
	printf '%s\n' "$feed" | grep -Eq \
		'^src-git [a-z0-9_-]+ https://[^[:space:]]+\^[0-9a-f]{40}$' || \
		fail "feed is not pinned to an exact commit: $feed"
done < "$PROJECT_DIR/configs/feeds.conf"
grep -Eq '^src-git packages ' "$PROJECT_DIR/configs/feeds.conf" || \
	fail "the required OpenWrt packages feed is missing"
grep -Eq '^src-git luci ' "$PROJECT_DIR/configs/feeds.conf" || \
	fail "the required OpenWrt LuCI feed is missing"

grep -Fq 'setenv fitaddr 0x10000000' "$PROJECT_DIR/boot/boot.cmd" || \
	fail "boot script FIT address is missing or unexpected"
grep -Fq '+  KERNEL_LOADADDR := 0x00280000' "$openwrt_patch" || \
	fail "TB-RK3399ProD FIT does not use the verified low-memory kernel address"
grep -Fq 'console=tty0 console=ttyS2,1500000n8' "$PROJECT_DIR/boot/boot.cmd" || \
	fail "boot script HDMI/serial dual console arguments are missing"
grep -Fq 'root=PARTLABEL=rootfs' "$PROJECT_DIR/boot/boot.cmd" || \
	fail "boot script persistent rootfs argument is missing"
if grep -Eq 'kmod-rtw88|rtl8822|mac80211|cfg80211' "$openwrt_patch"; then
	fail "unused wireless drivers or firmware remain in the device profile"
fi
for package in bash blkid blockdev coreutils-base64 coreutils-dd coreutils-stat \
	diffutils dnsmasq-full fdisk file findutils-find findutils-xargs fstrim \
	gawk grep gzip lsblk lscpu mount-utils wdctl ca-bundle curl htop jq less \
	lsof patch procps-ng rsync sed tar tmux vim-full \
	luci-ssl luci-i18n-base-zh-cn luci-i18n-firewall-zh-cn \
	luci-i18n-package-manager-zh-cn openssh-sftp-server strace tree \
	ip-full tcpdump-mini kmod-fs-exfat kmod-fs-vfat kmod-inet-diag \
	kmod-nft-tproxy kmod-r8169 kmod-tun python3-light unzip xz-utils; do
	grep -Eq "[[:space:]]$package([[:space:]\\\\]|$)" "$openwrt_patch" || \
		fail "required maintenance package is missing: $package"
done
if grep -Eq '[[:space:]]kmod-r8125([[:space:]\\]|$)' "$openwrt_patch"; then
	fail "out-of-tree Realtek r8125 driver must not replace mainline r8169"
fi
if grep -Eq '[[:space:]]luci([[:space:]\\]|$)|luci-app-attendedsysupgrade' \
	"$openwrt_patch"; then
	fail "unsupported attended sysupgrade must not be exposed through LuCI"
fi
if grep -Eq '[[:space:]]ruby(-yaml)?([[:space:]\\]|$)' "$openwrt_patch"; then
	fail "Ruby must remain an on-demand overlay package"
fi
grep -Eq '[[:space:]]-dnsmasq([[:space:]\\]|$)' "$openwrt_patch" || \
	fail "default dnsmasq is not removed when dnsmasq-full is selected"
grep -Eq '[[:space:]]-ip-tiny([[:space:]\\]|$)' "$openwrt_patch" || \
	fail "ip-tiny is not removed when ip-full is selected"
grep -Eq '[[:space:]]ss([[:space:]\\]|$)' "$openwrt_patch" || \
	fail "socket diagnostics utility is missing: ss"
if grep -Fq '143-mmc-sdhci-of-arasan-disable-rk3399-cqe.patch' \
	"$openwrt_patch" || \
	grep -Fq 'SDHCI_QUIRK_BROKEN_CQE' "$openwrt_patch"; then
	fail "RK3399 eMMC CQE experiment is overridden by a broken-CQE quirk"
fi
grep -Fq 'tcphy_set_orientation' "$typec_phy_patch" || \
	fail "RK3399 Type-C orientation callback is missing"
grep -Fq 'tcphy->new_mode = MODE_DISCONNECT;' "$typec_phy_patch" || \
	fail "RK3399 Type-C detach state is not recorded by the PHY"
grep -Fq 'return tcphy->new_mode;' "$typec_phy_patch" || \
	fail "RK3399 Type-C PHY does not consume the TCPM mode"
grep -Fq '#define POWER_ON_TRIES' "$typec_phy_patch" || \
	fail "RK3399 Type-C PHY power-on retries are missing"
grep -Fq 'rk3399-typec: PIPE status read failed:' "$typec_phy_patch" || \
	fail "RK3399 Type-C PIPE regmap read errors are not observable"
grep -Fq 'rk3399-typec: USB3 host GRF enable failed:' "$typec_phy_patch" || \
	fail "RK3399 Type-C GRF programming errors are not observable"
grep -Fq 'pipe_read_ret=%d' "$typec_phy_patch" || \
	fail "RK3399 Type-C final PHY failure log lacks the PIPE read status"
grep -Fq 'ignoring to keep power state balanced' "$typec_phy_patch" || \
	fail "RK3399 Type-C PHY power-off errors can leak the generic PHY power count"
grep -Fq 'mode = 0;' "$typec_dwc_patch" || \
	fail "RK3399 USB_ROLE_NONE is not represented as a true idle role"
grep -Fq 'if (!dwc->rk3399_typec)' "$typec_dwc_patch" || \
	fail "RK3399 Type-C role switch still schedules an initial non-idle role"
grep -Fq 'role_pm_held' "$typec_dwc_patch" || \
	fail "RK3399 Type-C active-role runtime-PM hold is missing"
grep -Fq 'pm_runtime_put_noidle(dwc->dev);' "$typec_dwc_patch" || \
	fail "RK3399 Type-C detach does not release its attached-role PM hold"
grep -Fq 'pm_usage=%d' "$typec_dwc_patch" || \
	fail "RK3399 Type-C PM reference counts are absent from transition logs"
grep -Fq 'pm_runtime_put_sync_suspend(dwc->dev);' "$typec_dwc_patch" || \
	fail "RK3399 Type-C detach does not synchronously suspend DWC3"
grep -Fq 'pm_runtime_set_autosuspend_delay(dev, 100);' "$typec_dwc_patch" || \
	fail "RK3399 DWC3 detach delay is not bounded"
grep -Fq 'pm_runtime_put_sync_suspend(dev);' "$typec_dwc_patch" || \
	fail "RK3399 DWC3 is not suspended while Type-C is unattached"
grep -Fq 'dwc3_core_init_for_resume(dwc);' "$typec_dwc_patch" || \
	fail "RK3399 DWC3/PHY resume lifecycle is missing"
grep -Fq 'dwc3_rk3399_typec_rearm_runtime_pm(dwc, ret);' \
	"$typec_dwc_patch" || \
	fail "RK3399 Type-C cannot recover from a failed runtime resume"
grep -Fq 'of_property_read_bool(dev->of_node, "usb-role-switch")' \
	"$typec_dwc_patch" || \
	fail "RK3399 DWC3 Type-C behavior is not restricted to a role-switch child"
grep -Fq 'drivers/usb/dwc3/dwc3-of-simple.c' "$typec_dwc_patch" || \
	fail "RK3399 parent DWC3 glue reset lifecycle is missing"
grep -Fq 'of_property_read_bool(child, "usb-role-switch");' \
	"$typec_dwc_patch" || \
	fail "RK3399 runtime reset is not restricted to the Type-C role-switch controller"
grep -Fq 'reset_control_assert(simple->resets);' "$typec_dwc_patch" || \
	fail "RK3399 usb3-otg reset assert is missing before PHY resume"
grep -Fq 'udelay(1);' "$typec_dwc_patch" || \
	fail "RK3399 usb3-otg reset pulse width is missing"
grep -Fq 'usleep_range(10000, 11000);' "$typec_dwc_patch" || \
	fail "Toybrick stable 4.4 PHY settle time is missing before xHCI probe"
grep -Fq 'reset_control_deassert(simple->resets);' "$typec_dwc_patch" || \
	fail "RK3399 usb3-otg reset deassert is missing before PHY resume"
grep -Fq 'rockchip-toybrick/kernel/blob/a80be5749ac552821967eff313df53f9e0cd1e01/drivers/usb/dwc3/dwc3-rockchip.c' \
	"$typec_dwc_patch" || \
	fail "Toybrick stable 4.4 DWC3 behavior is not pinned as the board baseline"
for marker in \
	'rk3399-typec: role transition' \
	'rk3399-typec: USB3 PHY power-on failed' \
	'rk3399-typec: wait PMA ready timeout' \
	'rk3399-typec: wait PIPE ready timeout' \
	'rk3399-typec: usb3-otg reset pulse complete'; do
	grep -Fq "$marker" "$kernel_patch_dir"/*.patch || \
		fail "Type-C diagnostic marker is missing: $marker"
done
grep -Fq '+CONFIG_DEBUG_FS=y' "$openwrt_patch" || \
	fail "TCPM/FUSB302 debug rings are unavailable without CONFIG_DEBUG_FS"
grep -Fq '/sys/kernel/debug/usb/fusb302-*/log' \
	"$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag" || \
	fail "Type-C diagnostic tool does not collect the FUSB302 event ring"
grep -Fq '/sys/kernel/debug/usb/tcpm-*/log' \
	"$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag" || \
	fail "Type-C diagnostic tool does not collect the TCPM event ring"
grep -Fq 'event rings before test' \
	"$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag" || \
	fail "Type-C diagnostic tool does not preserve pre-test controller events"
grep -Fq 'tb-typec-diag: %s' \
	"$PROJECT_DIR/rootfs/usr/sbin/tb-typec-diag" || \
	fail "Type-C diagnostic tool does not place test boundaries in dmesg"
if grep -Fq 'tcphy_reinit_usb3' "$kernel_patch_dir"/*.patch; then
	fail "unsafe live Type-C PHY reinitialization remains"
fi
if grep -Eq 'rockchip,usb3-host-only|usb3_powered|USB3 host switched' \
	"$kernel_patch_dir"/*.patch; then
	fail "unsupported fixed-host Type-C lane switching remains"
fi
grep -Fq '+CONFIG_USB_DWC3_DUAL_ROLE=y' "$openwrt_patch" || \
	fail "DWC3 dual-role lifecycle is missing"
grep -Fq '+CONFIG_USB_GADGET=y' "$openwrt_patch" || \
	fail "DWC3 dual-role build dependency USB_GADGET is missing"
grep -Fq '+# CONFIG_USB_DWC3_GADGET is not set' "$openwrt_patch" || \
	fail "DWC3 mode choice does not explicitly disable gadget-only mode"
grep -Fq '+# CONFIG_USB_DWC3_HOST is not set' "$openwrt_patch" || \
	fail "DWC3 mode choice does not explicitly disable host-only mode"
if grep -Fq '+CONFIG_USB_DWC3_HOST=y' "$openwrt_patch"; then
	fail "Type-C DWC3 must not use the static host-only lifecycle"
fi
grep -Fq 'Mini-PCIe 插座只接 USB2' \
	"$PROJECT_DIR/docs/HARDWARE-REFERENCE.md" || \
	fail "Mini-PCIe USB-only wiring constraint is not documented"
grep -Fq 'max-link-speed = <2>;' \
	"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dts" || \
	fail "PCIe Gen2 is required for RTL8125BG 2.5GbE throughput"
grep -Fq 'num-lanes = <4>;' \
	"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dts" || \
	fail "RK3399 PCIe root-complex lane configuration changed unexpectedly"
grep -Fq 'kmod-usb-hid' "$openwrt_patch" || \
	fail "USB HID support for the HDMI console is missing from the device profile"
grep -Fq 'GMAC_IRQ_CPU="4"' \
	"$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning" || \
	fail "GMAC IRQ is not assigned to the first Cortex-A72"
grep -Fq 'RTL8125_IRQ_CPU="5"' \
	"$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning" || \
	fail "RTL8125 IRQ is not assigned to the second Cortex-A72"
grep -Fq 'RTL8125_VENDOR="0x10ec"' \
	"$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning" || \
	fail "RTL8125 discovery does not use the Realtek PCI vendor ID"
grep -Fq 'RTL8125_DEVICE="0x8125"' \
	"$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning" || \
	fail "RTL8125 discovery does not use the PCI device ID"
grep -Fq 'device/msi_irqs/' \
	"$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning" || \
	fail "PCIe NIC MSI discovery is missing"
grep -Fq 'current_affinity=$(cat "$affinity_file"' \
	"$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning" || \
	fail "GMAC IRQ tuning is not idempotent"
grep -Fqx 'START=99' \
	"$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning" || \
	fail "GMAC IRQ fallback service does not run after network startup"
grep -Fq '/etc/init.d/tb-net-tuning start' \
	"$PROJECT_DIR/rootfs/etc/hotplug.d/iface/90-tb-net-tuning" || \
	fail "GMAC IRQ affinity is not restored by the interface hotplug hook"
grep -Fq '[ "$ACTION" = "ifup" ] || exit 0' \
	"$PROJECT_DIR/rootfs/etc/hotplug.d/iface/90-tb-net-tuning" || \
	fail "network IRQ hotplug hook is not restricted to interface-up events"
if grep -Fq '[ "$INTERFACE" = "lan" ]' \
	"$PROJECT_DIR/rootfs/etc/hotplug.d/iface/90-tb-net-tuning"; then
	fail "network IRQ hotplug hook must cover the future RTL8125 WAN or LAN role"
fi
for marker in \
	'RTL8125_FIRMWARE="/lib/firmware/rtl_nic/rtl8125b-2.fw"' \
	'/sys/bus/pci/devices/*' \
	'current_link_speed' \
	'ethtool -S "$netdev"' \
	"dmesg | grep -Ei 'pcie|aer|r8169|rtl8125|rtl_nic|firmware'"; do
	grep -Fq "$marker" "$PROJECT_DIR/rootfs/usr/sbin/tb-rtl8125-diag" || \
		fail "RTL8125 diagnostic coverage is missing: $marker"
done
grep -Fq "flow_offloading='1'" \
	"$PROJECT_DIR/rootfs/etc/uci-defaults/99-tb-network-offload" || \
	fail "software flow offload is not enabled by default"
grep -Fq "flow_offloading_hw='0'" \
	"$PROJECT_DIR/rootfs/etc/uci-defaults/99-tb-network-offload" || \
	fail "unsupported hardware flow offload must remain disabled"
for config in \
	'CONFIG_ARM_RK3399_DMC_DEVFREQ=y' \
	'CONFIG_ARM_RK3399_DMC_DEVFREQ_ROUND_PROBE_ONLY=y' \
	'CONFIG_DEVFREQ_EVENT_ROCKCHIP_DFI=y' \
	'CONFIG_PM_DEVFREQ_EVENT=y' \
	'CONFIG_CPU_FREQ_THERMAL=y' \
	'CONFIG_DRM=y' \
	'CONFIG_DRM_FBDEV_EMULATION=y' \
	'CONFIG_DRM_ROCKCHIP=y' \
	'CONFIG_FRAMEBUFFER_CONSOLE=y' \
	'CONFIG_FRAMEBUFFER_CONSOLE_DETECT_PRIMARY=y' \
	'# CONFIG_FRAMEBUFFER_CONSOLE_ROTATION is not set' \
	'CONFIG_PHY_ROCKCHIP_INNO_HDMI=y' \
	'# CONFIG_ROCKCHIP_ANALOGIX_DP is not set' \
	'# CONFIG_ROCKCHIP_CDN_DP is not set' \
	'CONFIG_ROCKCHIP_DW_HDMI=y' \
	'# CONFIG_ROCKCHIP_DW_MIPI_DSI is not set' \
	'# CONFIG_ROCKCHIP_INNO_HDMI is not set' \
	'# CONFIG_ROCKCHIP_LVDS is not set' \
	'# CONFIG_ROCKCHIP_RGB is not set' \
	'# CONFIG_ROCKCHIP_RK3066_HDMI is not set' \
	'CONFIG_ROCKCHIP_VOP=y' \
	'# CONFIG_ROCKCHIP_VOP2 is not set'; do
	grep -Fq "$config" "$openwrt_patch" || \
		fail "required board kernel setting is missing: $config"
done
grep -Fq 'No DFI monitor, DRAM DFS initialization, regulator change or' \
	"$ddr_probe_patch" || \
	fail "DDR probe-only safety boundary is not documented in the kernel patch"
grep -Fq 'return rk3399_dmcfreq_round_probe(pdev, data);' \
	"$ddr_probe_patch" || \
	fail "DDR probe-only path does not return before normal devfreq setup"
grep -Fq '+	unsigned long current_rate;' "$ddr_probe_patch" || \
	fail "DDR probe-only clock-rate variable is missing or unsafe"
if grep -Fq '+	unsigned long current;' "$ddr_probe_patch"; then
	fail "DDR probe-only code collides with the Linux current task macro"
fi
grep -Fq 'if (dmcfreq->probe_only)' "$ddr_probe_patch" || \
	fail "DDR probe-only suspend/remove guards are missing"
for rate in 200000000 400000000 528000000 600000000 800000000; do
	grep -Fq "$rate," "$ddr_probe_patch" || \
		fail "DDR probe candidate is missing: $rate"
done
if grep -Eq '^\+[[:space:]]*err = clk_set_rate\(dmcfreq->dmc_clk' \
	"$ddr_probe_patch"; then
	fail "DDR probe patch adds a mutating clock-rate call"
fi
for obsolete_config in \
	'CONFIG_DRM_KMS_FB_HELPER' \
	'CONFIG_FB=y' \
	'CONFIG_FB_CORE=y' \
	'CONFIG_FB_DEVICE=y' \
	'CONFIG_FONTS=y'; do
	if grep -Fq "$obsolete_config" "$openwrt_patch"; then
		fail "obsolete or unnecessary HDMI kernel setting remains: $obsolete_config"
	fi
done
grep -Fq 'tty1::askfirst:/usr/libexec/login.sh' "$openwrt_patch" || \
	fail "HDMI tty1 login entry is missing"
for dts_setting in \
	'&dfi {' \
	'&dmc {' \
	'center-supply = <&vdd_log>;' \
	'operating-points-v2 = <&dmc_opp_table>;' \
	'opp-hz = /bits/ 64 <800000000>;' \
	'rockchip,enable-strobe-pulldown;' \
	'&{/watchdog@ff848000} {' \
	'snps,watchdog-tops = <0x00010000 0x00020000 0x00040000 0x00080000' \
	'&hdmi {' \
	'avdd-0v9-supply = <&vcca_0v9>;' \
	'avdd-1v8-supply = <&vcca_1v8>;' \
	'ddc-i2c-bus = <&i2c3>;' \
	'&i2c3 {' \
	'&vopb {' \
	'&vopb_mmu {'; do
	grep -Fq "$dts_setting" \
		"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi" || \
		fail "required board device-tree setting is missing: $dts_setting"
done
sed -n '/^&dfi {$/,/^};$/p' \
	"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi" | \
	grep -Fq 'status = "disabled";' || \
	fail "DFI must remain disabled during the DDR ROUND-only probe"
for led_setting in \
	'led-boot = &led_blue;' \
	'led-failsafe = &led_red;' \
	'led-running = &led_green;' \
	'led-upgrade = &led_red;' \
	'compatible = "gpio-leds";' \
	'function = LED_FUNCTION_STATUS;' \
	'function = LED_FUNCTION_FAULT;' \
	'gpios = <&gpio2 RK_PA5 GPIO_ACTIVE_HIGH>;' \
	'gpios = <&gpio2 RK_PA4 GPIO_ACTIVE_HIGH>;' \
	'gpios = <&gpio2 RK_PA3 GPIO_ACTIVE_HIGH>;'; do
	grep -Fq "$led_setting" \
		"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi" || \
		fail "board LED device-tree setting is missing: $led_setting"
done
grep -Fq '已确认故障复位' "$PROJECT_DIR/docs/HARDWARE-STATUS.md" || \
	fail "hardware watchdog reset acceptance result is not documented"
grep -Fq '三路逐一亮灭通过' "$PROJECT_DIR/docs/HARDWARE-STATUS.md" || \
	fail "board LED acceptance result is not documented"
for typec_setting in \
	'&i2c8 {' \
	'compatible = "fcs,fusb302";' \
	'interrupts = <RK_PA2 IRQ_TYPE_LEVEL_LOW>;' \
	'gpio = <&gpio0 RK_PA1 GPIO_ACTIVE_LOW>;' \
	'data-role = "host";' \
	'power-role = "source";' \
	'PDO_FIXED(5000, 1500, PDO_FIXED_USB_COMM)' \
	'&tcphy0 {' \
	'&tcphy0_usb3 {' \
	'orientation-switch;' \
	'&usbdrd3_0 {' \
	'&usbdrd_dwc3_0 {' \
	'dr_mode = "otg";' \
	'usb-role-switch;' \
	'usbc0_role_sw: endpoint {' \
	'dwc3_0_role_switch: endpoint {' \
	'remote-endpoint = <&tcphy0_orientation_switch>;' \
	'remote-endpoint = <&dwc3_0_role_switch>;' \
	'remote-endpoint = <&usbc0_orien_sw>;' \
	'remote-endpoint = <&usbc0_role_sw>;'; do
	grep -Fq "$typec_setting" \
		"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi" || \
		fail "USB Type-C device-tree setting is missing: $typec_setting"
done
for vendor_typec_setting in \
	'compatible = "fairchild,fusb302";' \
	'vbus-5v-gpios' \
	'extcon = <&fusb0>' \
	'rockchip,usb3-host-only' \
	'u2phy0_typec_hs' \
	'usbc0_hs' \
	'tcphy0_typec_ss' \
	'usbc0_ss'; do
	if grep -Fq "$vendor_typec_setting" \
		"$PROJECT_DIR/dts/rk3399pro-toybrick-prod.dtsi"; then
		fail "obsolete vendor Type-C binding remains: $vendor_typec_setting"
	fi
done

if [ -d "$WORK_DIR/openwrt/.git" ]; then
	[ "$(git -C "$WORK_DIR/openwrt" rev-parse HEAD)" = "$OPENWRT_COMMIT" ] || \
		fail "OpenWrt checkout is not at the pinned commit"
	for patch in "$PROJECT_DIR"/patches/openwrt/*.patch; do
		git -C "$WORK_DIR/openwrt" apply --reverse --check "$patch"
	done
	cmp -s "$PROJECT_DIR/configs/feeds.conf" \
		"$WORK_DIR/openwrt/feeds.conf" || \
		fail "OpenWrt worktree feeds.conf differs from the canonical file"
	feeds_match_config "$WORK_DIR/openwrt" "$PROJECT_DIR/configs/feeds.conf" || \
		fail "OpenWrt feed checkout differs from the pinned configuration"
	[ -f "$WORK_DIR/openwrt/.config" ] || \
		fail "OpenWrt configuration has not been initialized"
	grep -Fqx 'CONFIG_TARGET_rockchip_armv8_DEVICE_toybrick_tb-rk3399prod=y' \
		"$WORK_DIR/openwrt/.config" || \
		fail "OpenWrt worktree does not select the board profile"
	grep -Fqx 'CONFIG_DROPBEAR_SFTPSERVER=y' \
		"$WORK_DIR/openwrt/.config" || \
		fail "OpenWrt worktree does not enable the Dropbear SFTP subsystem"
	grep -Fqx 'CONFIG_USE_MUSL=y' "$WORK_DIR/openwrt/.config" || \
		fail "OpenWrt worktree does not use musl"
	grep -Fqx 'CONFIG_PACKAGE_kmod-r8169=y' "$WORK_DIR/openwrt/.config" || \
		fail "OpenWrt worktree does not include mainline RTL8125 support"
	grep -Fqx 'CONFIG_PACKAGE_r8169-firmware=y' "$WORK_DIR/openwrt/.config" || \
		fail "OpenWrt worktree does not include RTL8125 firmware"
	for required_archive_package in tar xz xz-utils; do
		grep -Fqx "CONFIG_PACKAGE_$required_archive_package=y" \
			"$WORK_DIR/openwrt/.config" || \
			fail "OpenWrt worktree does not include $required_archive_package"
	done
	grep -Fqx 'CONFIG_PACKAGE_TAR_XZ=y' "$WORK_DIR/openwrt/.config" || \
		fail "OpenWrt GNU tar does not include XZ support"
	if grep -Fqx 'CONFIG_USE_GLIBC=y' "$WORK_DIR/openwrt/.config"; then
		fail "OpenWrt worktree unexpectedly selects glibc"
	fi
	[ -f "$WORK_DIR/BASELINES" ] || \
		fail "initialization baseline record is missing"
	[ "$(grep -c '^KMODS=' "$WORK_DIR/BASELINES")" -eq 1 ] || \
		fail "initialization baseline does not contain exactly one kmod pool record"
	kmod_baseline=$(sed -n 's/^KMODS=//p' "$WORK_DIR/BASELINES")
	if [ -n "$kmod_baseline" ]; then
		printf '%s\n' "$kmod_baseline" | grep -Eq \
			'^kmod-[a-z0-9][a-z0-9+._-]*(,kmod-[a-z0-9][a-z0-9+._-]*)*$' || \
			fail "invalid kmod pool baseline: $kmod_baseline"
		old_ifs=$IFS
		IFS=,
		for package in $kmod_baseline; do
			grep -Fqx "CONFIG_PACKAGE_$package=m" \
				"$WORK_DIR/openwrt/.config" || \
				fail "kmod pool package is not selected as a module: $package"
		done
		IFS=$old_ifs
	fi

	rockchip_makefile="$WORK_DIR/openwrt/target/linux/rockchip/Makefile"
	kernel_patchver=$(sed -n \
		's/^[[:space:]]*KERNEL_PATCHVER[[:space:]]*:=[[:space:]]*//p' \
		"$rockchip_makefile")
	kernel_details="$WORK_DIR/openwrt/target/linux/generic/kernel-$kernel_patchver"
	kernel_suffix=$(sed -n \
		"s/^LINUX_VERSION-$kernel_patchver[[:space:]]*=[[:space:]]*//p" \
		"$kernel_details")
	[ "$kernel_patchver$kernel_suffix" = "$LINUX_VERSION" ] || \
		fail "OpenWrt Linux version differs from the pinned project baseline"
	rockchip_kernel_config="$WORK_DIR/openwrt/target/linux/rockchip/armv8/config-$kernel_patchver"
	for required_kernel_config in \
		'CONFIG_ARM_RK3399_DMC_DEVFREQ=y' \
		'CONFIG_ARM_RK3399_DMC_DEVFREQ_ROUND_PROBE_ONLY=y' \
		'CONFIG_DEBUG_FS=y' \
		'CONFIG_DEVFREQ_EVENT_ROCKCHIP_DFI=y' \
		'CONFIG_PM_DEVFREQ_EVENT=y' \
		'CONFIG_PHY_ROCKCHIP_TYPEC=y' \
		'CONFIG_REGULATOR_FIXED_VOLTAGE=y' \
		'CONFIG_TYPEC=y' \
		'CONFIG_TYPEC_FUSB302=y' \
		'CONFIG_TYPEC_TCPM=y' \
		'CONFIG_USB_DWC3=y' \
		'CONFIG_USB_DWC3_DUAL_ROLE=y' \
		'# CONFIG_USB_DWC3_GADGET is not set' \
		'# CONFIG_USB_DWC3_HOST is not set' \
		'CONFIG_USB_GADGET=y' \
		'CONFIG_USB_ROLE_SWITCH=y'; do
		grep -Fqx "$required_kernel_config" "$rockchip_kernel_config" || \
			fail "required Type-C kernel setting is missing: $required_kernel_config"
	done
	if grep -Fqx 'CONFIG_USB_DWC3_HOST=y' "$rockchip_kernel_config"; then
		fail "Type-C DWC3 still uses static host-only mode"
	fi
	dts_dest="$WORK_DIR/openwrt/target/linux/rockchip/files-$kernel_patchver/arch/arm64/boot/dts/rockchip"
	for name in rk3399pro-toybrick-prod.dts rk3399pro-toybrick-prod.dtsi; do
		cmp -s "$PROJECT_DIR/dts/$name" "$dts_dest/$name" || \
			fail "OpenWrt worktree DTS is not synchronized: $name"
	done
	kernel_patch_dest="$WORK_DIR/openwrt/target/linux/rockchip/patches-$kernel_patchver"
	for source_patch in "$kernel_patch_dir"/*.patch; do
		name=${source_patch##*/}
		cmp -s "$source_patch" "$kernel_patch_dest/$name" || \
			fail "OpenWrt worktree kernel patch is not synchronized: $name"
	done
	rootfs_dest="$WORK_DIR/openwrt/target/linux/rockchip/base-files"
	while IFS= read -r -d '' source_file; do
		relative_path=${source_file#"$PROJECT_DIR/rootfs"/}
		cmp -s "$source_file" "$rootfs_dest/$relative_path" || \
			fail "OpenWrt worktree rootfs is not synchronized: $relative_path"
	done < <(find "$PROJECT_DIR/rootfs" -type f -print0 | sort -z)
fi

if [ -d "$WORK_DIR/u-boot/.git" ]; then
	[ "$(git -C "$WORK_DIR/u-boot" rev-parse HEAD)" = "$UBOOT_COMMIT" ] || \
		fail "U-Boot checkout is not at the pinned commit"
	for patch in "$PROJECT_DIR"/patches/u-boot/*.patch; do
		git -C "$WORK_DIR/u-boot" apply --reverse --check "$patch"
	done
fi

if [ -d "$WORK_DIR/rkbin/.git" ]; then
	[ "$(git -C "$WORK_DIR/rkbin" rev-parse HEAD)" = "$RKBIN_COMMIT" ] || \
		fail "rkbin checkout is not at the pinned commit"
	[ "$(git -C "$WORK_DIR/rkbin" remote get-url origin)" = "$RKBIN_URL" ] || \
		fail "rkbin checkout has an unexpected origin"
	[ -z "$(git -C "$WORK_DIR/rkbin" status --porcelain --untracked-files=all)" ] || \
		fail "rkbin checkout contains generated or modified files"
fi

echo "Project checks passed"
