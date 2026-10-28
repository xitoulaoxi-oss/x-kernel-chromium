#!/usr/bin/env bash
# Build the in-repo x-kernel tree and copy the kernel.bin into ../artifacts/.
#
# Run inside WSL2 Ubuntu (the kernel cannot be built completely on Windows).
#
#   bash build/build-kernel.sh
#   NAME=kernel-procfs.bin bash build/build-kernel.sh
#   CLEAN=yes bash build/build-kernel.sh
#
# Environment:
#   KERNEL      source tree           default: <repo>/kernel
#   OUT         artifact directory    default: <repo>/artifacts
#   NAME        output filename       default: kernel-procfs.bin
#   DEFCONFIG   kconfig defconfig     default: platforms/kplat-aarch64/qemu_defconfig
#   CLEAN=yes   run `make clean` first
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$HERE/.." && pwd)
KERNEL=${KERNEL:-$REPO/kernel}
OUT=${OUT:-$REPO/artifacts}
NAME=${NAME:-kernel-procfs.bin}
DEFCONFIG=${DEFCONFIG:-platforms/kplat-aarch64/qemu_defconfig}

if [ ! -f "$KERNEL/Cargo.toml" ]; then
  echo "not an x-kernel tree: $KERNEL (expected Cargo.toml)" >&2
  exit 2
fi
mkdir -p "$OUT"

echo "kernel : $KERNEL"
echo "output : $OUT/$NAME"
if git -C "$REPO" rev-parse --short HEAD >/dev/null 2>&1; then
  echo "repo   : $(git -C "$REPO" rev-parse --short HEAD)"
fi

cd "$KERNEL"
if [ "${CLEAN:-no}" = "yes" ]; then
  echo "== make clean =="
  make clean || true
fi

echo "== configure =="
cp "$DEFCONFIG" .config
make defconfig

echo "== build =="
make build

BIN=target/xkmake/kplat-aarch64/release/kernel.bin
if [ ! -f "$BIN" ]; then
  echo "build did not produce $BIN" >&2
  exit 1
fi

cp -f "$BIN" "$OUT/$NAME"
echo "== artifact =="
ls -l "$OUT/$NAME"
sha256sum "$OUT/$NAME"
