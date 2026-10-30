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
fetch "$ALPINE_URL" "$ALPINE_TAR" "$ALPINE_SHA256"

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
PKGS="alpine-base kmod iwd iwd-openrc openresolv dbus dbus-openrc dosfstools e2fsprogs e2fsprogs-extra findmnt parted tzdata doas eudev eudev-openrc udev-init-scripts-openrc"
[ "$ENABLE_SSH" = "true" ] && PKGS="$PKGS openssh"

# Some restricted host environments reject namespace operations used by APK
# package hooks. Keep the failure visible, then verify package payloads exist.
if ! apk --root "$ROOTFS" --arch "$ALPINE_ARCH" add --no-cache $PKGS; then
  echo "WARNING: apk reported package-hook errors. Requested package files will be checked, but hook setup may be incomplete." >&2
  for pkg in $PKGS; do
    apk --root "$ROOTFS" --arch "$ALPINE_ARCH" info -e "$pkg" >/dev/null 2>&1 ||
      die "required package '$pkg' was not installed"
  done
fi

# Check the actual payloads, not just APK's installed-package database.
# This catches partial installs where package hooks or file extraction failed.
in_chroot "command -v iwctl >/dev/null 2>&1 && command -v resolvconf >/dev/null 2>&1" ||
  die "iwd client (iwctl) or resolver helper (resolvconf) is missing"
[ -x "$ROOTFS/usr/libexec/iwd" ] || die "iwd daemon binary is missing"
[ -f "$ROOTFS/etc/init.d/iwd" ] || die "iwd OpenRC service is missing"
[ -f "$ROOTFS/etc/init.d/dbus" ] || die "D-Bus OpenRC service is missing"
[ -x "$ROOTFS/etc/init.d/udev" ] || die "eudev OpenRC service is missing"
[ -x "$ROOTFS/etc/init.d/udev-trigger" ] || die "eudev trigger service is missing"
[ -x "$ROOTFS/etc/init.d/udev-settle" ] || die "eudev settle service is missing"
[ -x "$ROOTFS/etc/init.d/udev-postmount" ] || die "eudev postmount service is missing"

# --- ROCKNIX modules and firmware ---
echo "Installing kernel modules and firmware..."
mkdir -p "$ROOTFS/lib/modules" "$ROOTFS/lib/firmware"
rsync -a "$ROCKNIX_EX/modules/$KVER/" "$ROOTFS/lib/modules/$KVER/"
rsync -a "$ROCKNIX_EX/firmware/" "$ROOTFS/lib/firmware/"

echo "Running depmod..."
in_chroot "depmod -a $KVER"

# --- Hostname ---
echo "$HOSTNAME" > "$ROOTFS/etc/hostname"

# --- Timezone ---
in_chroot "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
echo "$TIMEZONE" > "$ROOTFS/etc/timezone"

# --- Users ---
printf 'root:%s\n' "$ROOT_PASSWORD" | in_chroot "chpasswd"

in_chroot "adduser -D -s /bin/sh $DEFAULT_USER"
printf '%s:%s\n' "$DEFAULT_USER" "$DEFAULT_PASSWORD" | in_chroot "chpasswd"

# Device-node access for DRM/KMS and libinput.
for group in video render input; do
  in_chroot "addgroup -S $group 2>/dev/null || true"
  in_chroot "adduser $DEFAULT_USER $group"
done

if [ "$DEFAULT_USER_WHEEL" = "true" ]; then
  in_chroot "adduser $DEFAULT_USER wheel"
fi

# APK package hooks may fail on hosts that cannot create mount namespaces.
# Ensure the D-Bus service account and machine ID exist even in that case.
in_chroot "addgroup -S messagebus 2>/dev/null || true"
in_chroot "adduser -S -D -H -h /var/run/dbus -s /sbin/nologin -G messagebus messagebus 2>/dev/null || true"
in_chroot "mkdir -p /var/run/dbus /var/lib/dbus && dbus-uuidgen --ensure=/etc/machine-id"

# --- fstab ---
# Labels are used as a fallback; eudev provides device discovery and symlinks.
cat > "$ROOTFS/etc/fstab" <<EOF
LABEL=$ROOT_LABEL  /       ext4  defaults,noatime  0 1
LABEL=$BOOT_LABEL  /boot   vfat  defaults,noatime  0 2
EOF

# --- kernel modules to load at boot ---
# Alpine OpenRC's 'modules' service reads /etc/modules (not modules-load.d)
echo "rocknix-singleadc-joypad" >> "$ROOTFS/etc/modules"

# --- overlay ---
echo "Copying overlay..."
cp -a "$TOP/overlay/." "$ROOTFS/"

# doas rejects config files that are not owned by root or are writable
# by group/others. Enforce this after the overlay copy, which may preserve
# the host checkout's ownership and permissions.
chown 0:0 "$ROOTFS/etc/doas.conf"
chmod 0400 "$ROOTFS/etc/doas.conf"

echo "Done: $ROOTFS"
