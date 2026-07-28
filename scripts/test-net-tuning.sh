#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_DIR=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
fixture=$(mktemp -d /tmp/tb-rk3399prod-net-test.XXXXXX)
case "$fixture" in
	/tmp/tb-rk3399prod-net-test.*) ;;
	*)
		echo "unexpected test fixture path: $fixture" >&2
		exit 1
		;;
esac
trap 'rm -rf -- "$fixture"' EXIT

sysfs="$fixture/sys"
proc_irq="$fixture/proc/irq"
proc_interrupts="$fixture/proc/interrupts"
board_name_file="$fixture/tmp/sysinfo/board_name"

mkdir -p \
	"$(dirname "$board_name_file")" \
	"$sysfs/bus/platform/devices/fe300000.ethernet/net/lan-test" \
	"$sysfs/class/net/wan-test/device/msi_irqs" \
	"$sysfs/drivers/r8169" \
	"$sysfs/devices/system/cpu/cpu4" \
	"$sysfs/devices/system/cpu/cpu5" \
	"$proc_irq/41" \
	"$proc_irq/77"

printf '%s\n' 'rockchip,rk3399pro-toybrick-prod' >"$board_name_file"
printf '%s\n' 1 >"$sysfs/devices/system/cpu/cpu4/online"
printf '%s\n' 1 >"$sysfs/devices/system/cpu/cpu5/online"
printf '%s\n' 0x10ec >"$sysfs/class/net/wan-test/device/vendor"
printf '%s\n' 0x8125 >"$sysfs/class/net/wan-test/device/device"
ln -s "$sysfs/drivers/r8169" "$sysfs/class/net/wan-test/device/driver"
: >"$sysfs/class/net/wan-test/device/msi_irqs/77"
printf '%s\n' ' 41: 1 0 0 0 0 0 GICv3 41 Level lan-test' >"$proc_interrupts"
printf '%s\n' 0-5 >"$proc_irq/41/smp_affinity_list"
printf '%s\n' 0-5 >"$proc_irq/77/smp_affinity_list"

export TB_SYSFS_ROOT="$sysfs"
export TB_PROC_INTERRUPTS="$proc_interrupts"
export TB_IRQ_ROOT="$proc_irq"
export TB_BOARD_NAME_FILE="$board_name_file"

logger()
{
	:
}

# shellcheck source=../rootfs/etc/init.d/tb-net-tuning
. "$PROJECT_DIR/rootfs/etc/init.d/tb-net-tuning"

assert_value()
{
	local expected="$1" file="$2"
	local actual
	actual=$(cat "$file")
	[ "$actual" = "$expected" ] || {
		echo "expected $file to contain '$expected', got '$actual'" >&2
		exit 1
	}
}

start
assert_value 4 "$proc_irq/41/smp_affinity_list"
assert_value 5 "$proc_irq/77/smp_affinity_list"

# A different Realtek device must not inherit the RTL8125-specific policy.
printf '%s\n' 0x8168 >"$sysfs/class/net/wan-test/device/device"
printf '%s\n' 0 >"$proc_irq/77/smp_affinity_list"
start
assert_value 0 "$proc_irq/77/smp_affinity_list"

# An offline CPU must be left untouched; bringing it online enables tuning.
printf '%s\n' 0x8125 >"$sysfs/class/net/wan-test/device/device"
printf '%s\n' 0 >"$sysfs/devices/system/cpu/cpu5/online"
start
assert_value 0 "$proc_irq/77/smp_affinity_list"
printf '%s\n' 1 >"$sysfs/devices/system/cpu/cpu5/online"
start
assert_value 5 "$proc_irq/77/smp_affinity_list"

echo "Network IRQ tuning behavior passed"
