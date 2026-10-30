# Shared utilities — sourced by build scripts after config.sh.

die() { echo "error: $*" >&2; exit 1; }

assert_rootfs() {
  [ -d "$ROOTFS/etc" ] || die "rootfs not found at $ROOTFS — run 03-rootfs.sh first"
}

assert_rocknix() {
  [ -d "$ROCKNIX_EX/modules/$KVER" ] || die "ROCKNIX hardware layer not found — run 02-extract-rocknix.sh first"
}

in_chroot() {
  # Run the target BusyBox shell directly through host QEMU. Do not chroot
  # first: without binfmt_misc, the kernel cannot launch AArch64 child binaries.
  local qemu="${QEMU_AARCH64:-$(command -v qemu-aarch64-static 2>/dev/null || command -v qemu-aarch64 2>/dev/null)}"
  "$qemu" -L "$ROOTFS" "$ROOTFS/bin/busybox" sh -c "$1"
}

in_chroot_exec() {
  # Run a standalone AArch64 executable from the target rootfs via host QEMU.
  local binary="$1"
  shift
  local qemu="${QEMU_AARCH64:-$(command -v qemu-aarch64-static 2>/dev/null || command -v qemu-aarch64 2>/dev/null)}"
  "$qemu" -L "$ROOTFS" "$ROOTFS$binary" "$@"
}

fetch() {
  # fetch <url> <dest> [sha256]
  local url="$1" dest="$2" expected="${3:-}"
  if [ ! -f "$dest" ]; then
    echo "Downloading $(basename "$dest")..."
    curl -fL --retry 3 -o "$dest.part" "$url"
    mv "$dest.part" "$dest"
  fi
  if [ -n "$expected" ]; then
    actual="$(sha256sum "$dest" | awk '{print $1}')"
    [ "$actual" = "$expected" ] || die "checksum mismatch for $dest\n  expected: $expected\n  got:      $actual"
  fi
}
