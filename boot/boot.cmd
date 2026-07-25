# TB-RK3399ProD OpenWrt persistent-system boot script
# Loaded by U-Boot distro_bootcmd from the boot_linux ext2 partition.

setenv fitaddr 0x10000000
setenv bootargs console=ttyS2,1500000n8 earlycon=uart8250,mmio32,0xff1a0000 loglevel=8 root=PARTLABEL=rootfs rootwait rootfstype=squashfs fstools_overlay_fstype=ext4

if test -z "${devtype}"; then
	setenv devtype mmc
fi
if test -z "${devnum}"; then
	setenv devnum 0
fi
if test -z "${distro_bootpart}"; then
	setenv distro_bootpart 3
fi

echo "Loading TB-RK3399ProD OpenWrt FIT from ${devtype} ${devnum}:${distro_bootpart}..."
if load ${devtype} ${devnum}:${distro_bootpart} ${fitaddr} /openwrt.itb; then
	bootm ${fitaddr}
	echo "ERROR: bootm returned"
else
	echo "ERROR: unable to load /openwrt.itb from boot_linux"
fi
