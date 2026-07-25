.PHONY: init uboot openwrt all package

init:
	bash scripts/init.sh

uboot:
	bash scripts/build.sh uboot

openwrt:
	bash scripts/build.sh openwrt

all:
	bash scripts/build.sh all

package:
	bash scripts/package.sh
