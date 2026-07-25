.PHONY: check init uboot openwrt all package

JOBS ?= $(shell nproc)

check:
	bash scripts/check.sh

init:
	bash scripts/init.sh "$(JOBS)"

uboot:
	bash scripts/build.sh uboot

openwrt:
	bash scripts/build.sh openwrt "$(JOBS)"

all:
	bash scripts/build.sh all "$(JOBS)"

package:
	bash scripts/package.sh
