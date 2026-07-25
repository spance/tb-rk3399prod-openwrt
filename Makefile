.PHONY: check init uboot openwrt all package clean reset-work reinit

J ?= $(shell nproc)

check:
	bash scripts/check.sh

init:
	bash scripts/init.sh "$(J)"

uboot:
	bash scripts/build.sh uboot

openwrt:
	bash scripts/build.sh openwrt "$(J)"

all:
	bash scripts/build.sh all "$(J)"

package:
	bash scripts/package.sh

clean:
	bash scripts/clean.sh

reset-work:
	bash scripts/reset-work.sh

reinit: reset-work
	bash scripts/init.sh "$(J)"
