# Shared utilities — sourced by build scripts after config.sh.

die() { echo "error: $*" >&2; exit 1; }

assert_rootfs() {
  [ -d "$ROOTFS/etc" ] || die "rootfs not found at $ROOTFS — run 03-rootfs.sh first"
}

assert_rocknix() {
  [ -d "$ROCKNIX_EX/modules/$KVER" ] || die "ROCKNIX hardware layer not found — run 02-extract-rocknix.sh first"
}

# Run an AArch64 command with the target rootfs as its filesystem root.
# PRoot redirects absolute paths; QEMU alone (-L) only sets the ELF library prefix.
in_chroot() {
  local command="$1"
  local proot="${PROOT:-$(command -v proot 2>/dev/null || true)}"
  local qemu="${QEMU_AARCH64:-$(command -v qemu-aarch64-static 2>/dev/null || command -v qemu-aarch64 2>/dev/null || true)}"
  [ -n "$proot" ] || die "proot not found — install it with: apk add proot"
  [ -n "$qemu" ] || die "QEMU AArch64 user emulator not found — install it with: apk add qemu-aarch64"
  local resolv_bind=()
  [ -f /etc/resolv.conf ] && resolv_bind=(-b /etc/resolv.conf:/etc/resolv.conf)
  "$proot" -q "$qemu" -r "$ROOTFS" -w / "${resolv_bind[@]}" /bin/sh -c "$command"
}

in_chroot_exec() {
  local binary="$1"
  shift
  local proot="${PROOT:-$(command -v proot 2>/dev/null || true)}"
  local qemu="${QEMU_AARCH64:-$(command -v qemu-aarch64-static 2>/dev/null || command -v qemu-aarch64 2>/dev/null || true)}"
  [ -n "$proot" ] || die "proot not found — install it with: apk add proot"
  [ -n "$qemu" ] || die "QEMU AArch64 user emulator not found — install it with: apk add qemu-aarch64"
  local resolv_bind=()
  [ -f /etc/resolv.conf ] && resolv_bind=(-b /etc/resolv.conf:/etc/resolv.conf)
  "$proot" -q "$qemu" -r "$ROOTFS" -w / "${resolv_bind[@]}" "$binary" "$@"
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
