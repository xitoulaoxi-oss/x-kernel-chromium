#!/usr/bin/env bash
# Build the in-repo x-kernel tree and copy the kernel.bin into ../artifacts/.
#
# Run inside WSL2 Ubuntu (the kernel cannot be built completely on Windows).
#
#   bash build/build-kernel.sh
#   OUT_NAME=kernel-procfs.bin bash build/build-kernel.sh
#   CLEAN=yes bash build/build-kernel.sh
#
# Environment:
#   KERNEL      source tree           default: <repo>/kernel
#   OUT         artifact directory    default: <repo>/artifacts
#   OUT_NAME    output filename       default: kernel-procfs.bin
#   BUILD_DIR   cargo/kconfig output  default: <KERNEL>/target;
#                                     if the repo path has spaces: /tmp/xk-build-<uid>
#   DEFCONFIG   kconfig defconfig     default: platforms/kplat-aarch64/qemu_defconfig
#   CLEAN=yes   run make clean first
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd -- "$HERE/.." && pwd)
KERNEL=${KERNEL:-$REPO/kernel}
OUT=${OUT:-$REPO/artifacts}
OUT_NAME=${OUT_NAME:-kernel-procfs.bin}
DEFCONFIG=${DEFCONFIG:-platforms/kplat-aarch64/qemu_defconfig}

# x-kernel's Makefile expands TARGET_DIR/XCONFIG_TARGET_DIR without quotes.
# A repository path containing a space would split --target-dir and make cargo
# run from the wrong manifest.  Move the build directory somewhere safe.
if [ -z "${BUILD_DIR:-}" ]; then
  case "$KERNEL $OUT" in
    *" "*) BUILD_DIR="/tmp/xk-build-$(id -u)" ;;
    *) BUILD_DIR="$KERNEL/target" ;;
  esac
fi
case "$BUILD_DIR" in
  *" "*) echo "BUILD_DIR must not contain spaces: $BUILD_DIR" >&2; exit 2 ;;
esac

if [ ! -f "$KERNEL/Cargo.toml" ]; then
  echo "not an x-kernel tree: $KERNEL (expected Cargo.toml)" >&2
  exit 2
fi
mkdir -p "$OUT" "$BUILD_DIR"

echo "kernel : $KERNEL"
echo "build  : $BUILD_DIR"
echo "output : $OUT/$OUT_NAME"
if git -C "$REPO" rev-parse --short HEAD >/dev/null 2>&1; then
  echo "repo   : $(git -C "$REPO" rev-parse --short HEAD)"
fi

cd "$KERNEL"
if [ "${CLEAN:-no}" = "yes" ]; then
  echo "== make clean =="
  make clean TARGET_DIR="$BUILD_DIR" || true
fi

echo "== configure =="
cp "$DEFCONFIG" .config
make defconfig TARGET_DIR="$BUILD_DIR"

echo "== build =="
make build TARGET_DIR="$BUILD_DIR"

BIN="$BUILD_DIR/xkmake/kplat-aarch64/release/kernel.bin"
if [ ! -f "$BIN" ]; then
  echo "build did not produce $BIN" >&2
  exit 1
fi

cp -f "$BIN" "$OUT/$OUT_NAME"
echo "== artifact =="
ls -l "$OUT/$OUT_NAME"
sha256sum "$OUT/$OUT_NAME"
