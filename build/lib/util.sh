# Shared utilities — sourced by build scripts after config.sh.

die() { echo "error: $*" >&2; exit 1; }

assert_rootfs() {
  [ -d "$ROOTFS/etc" ] || die "rootfs not found at $ROOTFS — run 03-rootfs.sh first"
}

assert_rocknix() {
  [ -d "$ROCKNIX_EX/modules/$KVER" ] || die "ROCKNIX hardware layer not found — run 02-extract-rocknix.sh first"
}

in_chroot() {
  # Run the target AArch64 shell explicitly through QEMU. This avoids
  # requiring host binfmt_misc registration for cross-architecture chroots.
  chroot "$ROOTFS" /usr/bin/qemu-aarch64-static /bin/sh -c "$1"
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
