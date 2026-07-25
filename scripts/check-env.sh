#!/usr/bin/env bash
set -euo pipefail

export PATH=${TB_HOST_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}

fail() { echo "ERROR: $*" >&2; exit 1; }

print_debian_hint() {
	cat >&2 <<'EOF'
Debian/Ubuntu 可执行：
  sudo apt-get update
  sudo apt-get install -y bc bison build-essential bzip2 ca-certificates \
    device-tree-compiler e2fsprogs file flex gawk gettext git \
    libncurses-dev perl python3 python3-setuptools rsync unzip wget \
    xz-utils zlib1g-dev
EOF
}

[ "$(uname -s)" = Linux ] || fail "this project must be built on Linux"
[ "$(uname -m)" = x86_64 ] || fail "the supported build host is Linux x86_64"

missing=()
for command in git make gcc g++ python3 bc bison flex dtc gawk gettext \
	perl rsync unzip file wget tar xz bzip2 gzip \
	sha256sum readlink realpath stat nproc find xargs patch diff cmp \
	which getopt grep sed awk od tr wc install truncate touch \
	mke2fs e2fsck debugfs; do
	command -v "$command" >/dev/null 2>&1 || missing+=("$command")
done

if [ "${#missing[@]}" -ne 0 ]; then
	echo "ERROR: missing host tools: ${missing[*]}" >&2
	print_debian_hint
	exit 1
fi

probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/tb-rk3399prod-env.XXXXXX")
trap 'rm -rf -- "$probe_dir"' EXIT
failures=()

printf '%s\n' '#include <stdio.h>' 'int main(void) { puts("ok"); return 0; }' \
	> "$probe_dir/libc.c"
if ! gcc "$probe_dir/libc.c" -o "$probe_dir/libc" \
	>"$probe_dir/libc.log" 2>&1; then
	failures+=("C compiler or native libc development headers (build-essential/libc6-dev)")
fi

printf '%s\n' '#include <iostream>' 'int main() { std::cout << "ok"; return 0; }' \
	> "$probe_dir/libstdcxx.cc"
if ! g++ "$probe_dir/libstdcxx.cc" -o "$probe_dir/libstdcxx" \
	>"$probe_dir/libstdcxx.log" 2>&1; then
	failures+=("C++ compiler or libstdc++ development files (g++)")
fi

printf '%s\n' '#include <ncurses.h>' \
	'int main(void) { initscr(); endwin(); return 0; }' > "$probe_dir/ncurses.c"
if ! gcc "$probe_dir/ncurses.c" -lncursesw -o "$probe_dir/ncurses" \
	>"$probe_dir/ncurses.log" 2>&1 && \
	! gcc "$probe_dir/ncurses.c" -lncurses -o "$probe_dir/ncurses" \
	>>"$probe_dir/ncurses.log" 2>&1; then
	failures+=("ncurses headers/library (libncurses-dev)")
fi

printf '%s\n' '#include <zlib.h>' \
	'int main(void) { return zlibVersion() == 0; }' > "$probe_dir/zlib.c"
if ! gcc "$probe_dir/zlib.c" -lz -o "$probe_dir/zlib" \
	>"$probe_dir/zlib.log" 2>&1; then
	failures+=("zlib headers/library (zlib1g-dev)")
fi

if ! python3 -c 'import setuptools' >"$probe_dir/python.log" 2>&1; then
	failures+=("Python setuptools module (python3-setuptools)")
fi

if ! perl -MData::Dumper -MFindBin -MFile::Copy -MFile::Compare \
	-MIPC::Cmd -MThread::Queue -e 1 \
	>"$probe_dir/perl.log" 2>&1; then
	failures+=("required Perl core modules")
fi

if ! dtc -v >"$probe_dir/dtc.log" 2>&1; then
	failures+=("working device-tree compiler (device-tree-compiler)")
fi

if [ "${#failures[@]}" -ne 0 ]; then
	echo "ERROR: host development dependency checks failed:" >&2
	printf '  - %s\n' "${failures[@]}" >&2
	print_debian_hint
	exit 1
fi

echo "Host environment check passed: Linux x86_64, tools, compilers and development libraries"
