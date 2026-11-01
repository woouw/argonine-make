#!/bin/bash
# Cross-compile pinpad and pinpad-set for aarch64 and install into rootfs.
# Requires: aarch64-linux-musl-gcc (from musl-cross or Alpine's cross-* packages)
# On Alpine host: apk add musl-cross
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/util.sh"

assert_rootfs

SRC="$TOP/src/pinpad"
OUT="$WORK/pinpad-build"
rm -rf "$OUT"; mkdir -p "$OUT"

# Find cross compiler
CC=""
for candidate in aarch64-linux-musl-gcc aarch64-alpine-linux-musl-gcc aarch64-linux-gnu-gcc; do
  if command -v "$candidate" >/dev/null 2>&1; then
    CC="$candidate"
    break
  fi
done

if [ -z "$CC" ]; then
  echo "WARNING: no aarch64 cross compiler found — skipping pinpad build."
  echo "  Install one with: apk add aarch64-linux-musl-cross"
  echo "  Or build on-device: apk add build-base libxcrypt-dev && make -C /usr/local/src/pinpad install"
  # Copy source to rootfs so it can be built on-device
  mkdir -p "$ROOTFS/usr/local/src/pinpad"
  cp "$SRC"/*.c "$SRC"/*.h "$SRC/Makefile" "$ROOTFS/usr/local/src/pinpad/"
  exit 0
fi

echo "Cross-compiling pinpad with $CC..."
make -C "$SRC" CC="$CC" \
  CFLAGS="-O2 -Wall -Wextra -std=c11 -static" \
  LDFLAGS="-lcrypt" \
  -B --no-print-directory \
  VPATH="$SRC" \
  pinpad pinpad-set 2>&1 | sed 's/^/  /'

# make puts binaries in the source dir since VPATH doesn't redirect output
# build in OUT instead
cp "$SRC"/*.c "$SRC"/*.h "$SRC/Makefile" "$OUT/"
make -C "$OUT" CC="$CC" \
  CFLAGS="-O2 -Wall -Wextra -std=c11 -static" \
  LDFLAGS="-lcrypt" \
  --no-print-directory

install -Dm755 "$OUT/pinpad"     "$ROOTFS/usr/local/bin/pinpad"
install -Dm755 "$OUT/pinpad-set" "$ROOTFS/usr/local/bin/pinpad-set"

# Also drop source into rootfs for on-device hacking
mkdir -p "$ROOTFS/usr/local/src/pinpad"
cp "$SRC"/*.c "$SRC"/*.h "$SRC/Makefile" "$ROOTFS/usr/local/src/pinpad/"

echo "Done: pinpad and pinpad-set installed to rootfs"
