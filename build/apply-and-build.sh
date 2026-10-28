#!/usr/bin/env bash
# Rebuild the kernel from the official baseline, using this repository's patch.
#
# Usage:  bash apply-and-build.sh /path/to/clean/x-kernel-checkout
#
# The checkout must be at the baseline commit (d3a6ec9).  Everything the build
# needs beyond the patch is upstream: the patch touches 42 files.
set -euo pipefail

if [ $# -lt 1 ]; then
  echo "usage: apply-and-build.sh <clean x-kernel checkout at d3a6ec9>"
  exit 2
fi
SRC=$1
HERE=$(cd -- "$(dirname -- "$0")" && pwd)
PATCH=$HERE/../patches/x-kernel-solution.patch

cd "$SRC"
echo "== baseline =="
git log --oneline -1

echo "== patch check =="
git apply --check "$PATCH"
echo "   patch applies cleanly"

git apply "$PATCH"
echo "== patched; building =="

# The project builds through its own Makefile/Kconfig flow.  A bare cargo check is
# not a valid check here: the allocator features come from a Kconfig-generated
# snapshot that only the project's build produces.
cp platforms/kplat-aarch64/qemu_defconfig .config
make defconfig
make build

BIN=target/xkmake/kplat-aarch64/release/kernel.bin
echo "== artifact =="
ls -l "$BIN"
sha256sum "$BIN"
echo
echo "Compare with ../artifacts/SHA256SUMS.txt:"
echo "  kernel-procfs.bin  8,544,026 B  5261ceb3c11249a75ebe0f3477d5af28ae604cf62e6576ace5d09079442c8459"
