#!/usr/bin/env bash
set -euo pipefail

export PATH=${TB_HOST_PATH:-/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin}

fail() { echo "ERROR: $*" >&2; exit 1; }

print_debian_hint() {
	cat >&2 <<'EOF'
Debian/Ubuntu 可执行：
  sudo apt-get update
  sudo apt-get install -y build-essential flex bison gawk gcc-multilib \
    libc6-dev libc6-dev-i386 gettext git libncurses-dev libssl-dev \
    libelf-dev pkg-config python3 python3-setuptools rsync swig unzip \
    zlib1g-dev file wget xz-utils bc device-tree-compiler bzip2 cpio \
    e2fsprogs
EOF
}

[ "$(uname -s)" = Linux ] || fail "this project must be built on Linux"
[ "$(uname -m)" = x86_64 ] || fail "the supported build host is Linux x86_64"

missing=()
for command in git make gcc g++ python3 bc bison flex swig openssl dtc \
	gawk gettext perl rsync unzip file wget tar xz bzip2 gzip cpio \
	sha256sum readlink realpath stat nproc find xargs patch diff cmp \
	pkg-config which getopt grep sed awk od tr wc install truncate touch mke2fs e2fsck debugfs; do
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

if ! gcc -m32 "$probe_dir/libc.c" -o "$probe_dir/libc32" \
	>"$probe_dir/libc32.log" 2>&1; then
	failures+=("32-bit compiler/libc support (gcc-multilib/libc6-dev-i386)")
fi

printf '%s\n' '#include <ncurses.h>' \
	'int main(void) { initscr(); endwin(); return 0; }' > "$probe_dir/ncurses.c"
if ! gcc "$probe_dir/ncurses.c" -lncursesw -o "$probe_dir/ncurses" \
	>"$probe_dir/ncurses.log" 2>&1 && \
	! gcc "$probe_dir/ncurses.c" -lncurses -o "$probe_dir/ncurses" \
	>>"$probe_dir/ncurses.log" 2>&1; then
	failures+=("ncurses headers/library (libncurses-dev)")
fi

printf '%s\n' '#include <openssl/ssl.h>' \
	'int main(void) { SSL_CTX *c = SSL_CTX_new(TLS_method()); SSL_CTX_free(c); return 0; }' \
	> "$probe_dir/openssl.c"
if ! gcc "$probe_dir/openssl.c" -lssl -lcrypto -o "$probe_dir/openssl" \
	>"$probe_dir/openssl.log" 2>&1; then
	failures+=("OpenSSL headers/libraries (libssl-dev)")
fi

printf '%s\n' '#include <zlib.h>' \
	'int main(void) { return zlibVersion() == 0; }' > "$probe_dir/zlib.c"
if ! gcc "$probe_dir/zlib.c" -lz -o "$probe_dir/zlib" \
	>"$probe_dir/zlib.log" 2>&1; then
	failures+=("zlib headers/library (zlib1g-dev)")
fi

printf '%s\n' '#include <libelf.h>' \
	'int main(void) { return elf_version(EV_CURRENT) == EV_NONE; }' \
	> "$probe_dir/libelf.c"
if ! gcc "$probe_dir/libelf.c" -lelf -o "$probe_dir/libelf" \
	>"$probe_dir/libelf.log" 2>&1; then
	failures+=("ELF development headers/library (libelf-dev)")
fi

if ! python3 -c 'import setuptools' >"$probe_dir/python.log" 2>&1; then
	failures+=("Python setuptools module (python3-setuptools)")
fi

if ! perl -MFindBin -MFile::Copy -MFile::Compare -MThread::Queue -e 1 \
	>"$probe_dir/perl.log" 2>&1; then
	failures+=("required Perl core modules")
fi

if ! swig -version >"$probe_dir/swig.log" 2>&1; then
	failures+=("working SWIG executable (swig)")
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
