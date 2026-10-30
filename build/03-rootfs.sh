#!/bin/bash
# Build the Alpine root filesystem:
#   - fetch and extract Alpine minirootfs
#   - configure apk repos, install packages
#   - install ROCKNIX modules and firmware
#   - configure system (hostname, timezone, users, fstab)
#   - copy overlay
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/util.sh"

assert_rocknix

# --- PRoot + QEMU user emulator (needed to run AArch64 userspace on x86_64) ---
PROOT="$(command -v proot 2>/dev/null || true)"
if [ -z "$PROOT" ]; then
  die "PRoot not found — install it with: apk add proot"
fi

QEMU_AARCH64="$(command -v qemu-aarch64-static 2>/dev/null || command -v qemu-aarch64 2>/dev/null || true)"
if [ -z "$QEMU_AARCH64" ]; then
  die "QEMU AArch64 user emulator not found — install it with: apk add qemu-aarch64"
fi

# --- Alpine minirootfs ---
mkdir -p "$ROCKNIX_DL"
ALPINE_TAR="$ROCKNIX_DL/alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
fetch "$ALPINE_URL" "$ALPINE_TAR"   # no checksum pinned yet; add ALPINE_SHA256 to config.sh

rm -rf "$ROOTFS"
mkdir -p "$ROOTFS"
echo "Extracting Alpine minirootfs..."
tar xf "$ALPINE_TAR" -C "$ROOTFS"

# --- APK repos ---
cat > "$ROOTFS/etc/apk/repositories" <<EOF
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/main
https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/community
EOF

# --- Install packages ---
echo "Installing packages..."
PKGS="alpine-base kmod iwd e2fsprogs parted tzdata doas"
[ "$ENABLE_SSH" = "true" ] && PKGS="$PKGS openssh"
# Some host/container environments reject the mount-namespace unshare used by
# APK hooks. APK can still lay down package files; keep this warning visible.
if ! apk add --root "$ROOTFS" --no-cache $PKGS; then
  echo "warning: apk reported package-hook errors; checking requested packages..." >&2
  for pkg in $PKGS; do
    apk --root "$ROOTFS" info -e "$pkg" >/dev/null 2>&1 ||
      die "required package '$pkg' was not installed"
  done
fi

# --- ROCKNIX modules and firmware ---
echo "Installing kernel modules and firmware..."
mkdir -p "$ROOTFS/usr/lib/modules" "$ROOTFS/usr/lib/firmware"
rsync -a "$ROCKNIX_EX/modules/$KVER/" "$ROOTFS/usr/lib/modules/$KVER/"
rsync -a "$ROCKNIX_EX/firmware/" "$ROOTFS/usr/lib/firmware/"

echo "Running depmod..."
in_chroot_exec /sbin/depmod -a "$KVER"

# --- Hostname ---
echo "$HOSTNAME" > "$ROOTFS/etc/hostname"

# --- Timezone ---
in_chroot "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
echo "$TIMEZONE" > "$ROOTFS/etc/timezone"

# --- Users ---
printf 'root:%s\n' "$ROOT_PASSWORD" | in_chroot "chpasswd"

in_chroot "adduser -D -s /bin/sh $DEFAULT_USER"
printf '%s:%s\n' "$DEFAULT_USER" "$DEFAULT_PASSWORD" | in_chroot "chpasswd"

if [ "$DEFAULT_USER_WHEEL" = "true" ]; then
  in_chroot "adduser $DEFAULT_USER wheel"
fi

# --- doas ---
install -m644 "$TOP/overlay/etc/doas.conf" "$ROOTFS/etc/doas.conf"

# --- fstab ---
PARTUUID_BOOT="$(printf '%08x' "$DISK_ID")-01"
cat > "$ROOTFS/etc/fstab" <<EOF
PARTUUID=$PARTUUID_ROOT  /       ext4  defaults,noatime  0 1
PARTUUID=$PARTUUID_BOOT  /boot   vfat  defaults,noatime  0 2
EOF

# --- kernel modules to load at boot ---
# Alpine OpenRC's 'modules' service reads /etc/modules (not modules-load.d)
echo "rocknix-singleadc-joypad" >> "$ROOTFS/etc/modules"

# --- overlay ---
echo "Copying overlay..."
cp -a "$TOP/overlay/." "$ROOTFS/"

echo "Done: $ROOTFS"
