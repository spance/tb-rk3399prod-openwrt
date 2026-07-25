.PHONY: check init uboot openwrt all package clean reset reinit

MAKE_JOBS = $(or $(patsubst -j%,%,$(filter -j%,$(MAKEFLAGS))),$(shell nproc))

check:
	bash scripts/check.sh

init:
	bash scripts/init.sh "$(MAKE_JOBS)"

uboot:
	bash scripts/build.sh uboot

openwrt:
	bash scripts/build.sh openwrt "$(MAKE_JOBS)"

all:
	bash scripts/build.sh all "$(MAKE_JOBS)"

package:
	bash scripts/package.sh

clean:
	bash scripts/clean.sh

reset:
	bash scripts/reset.sh

reinit: reset
	bash scripts/init.sh "$(MAKE_JOBS)"
