#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
out=$1
mkdir -p "$out"
gcc -O2 -Wall -Wextra "$root/tests/tcp_epoll_probe.c" -o "$out/tcp-epoll-linux"
aarch64-linux-gnu-gcc -static -O2 -Wall -Wextra "$root/tests/tcp_epoll_probe.c" -o "$out/tcp-epoll-aarch64"
"$out/tcp-epoll-linux" in
"$out/tcp-epoll-linux" inout
sha256sum "$out/tcp-epoll-aarch64"
