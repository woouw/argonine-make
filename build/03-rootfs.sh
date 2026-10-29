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
apk add --root "$ROOTFS" --initdb --no-cache \
  alpine-base \
  kmod \
  iwd \
  e2fsprogs \
  tzdata \
  doas \
  $([ "$ENABLE_SSH" = "true" ] && echo openssh)

# --- ROCKNIX modules and firmware ---
echo "Installing kernel modules and firmware..."
mkdir -p "$ROOTFS/usr/lib/modules" "$ROOTFS/usr/lib/firmware"
rsync -a "$ROCKNIX_EX/modules/$KVER/" "$ROOTFS/usr/lib/modules/$KVER/"
rsync -a "$ROCKNIX_EX/firmware/" "$ROOTFS/usr/lib/firmware/"

echo "Running depmod..."
in_chroot "depmod -a $KVER"

# --- Hostname ---
echo "$HOSTNAME" > "$ROOTFS/etc/hostname"

# --- Timezone ---
in_chroot "ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime"
echo "$TIMEZONE" > "$ROOTFS/etc/timezone"

# --- Users ---
echo "root:$ROOT_PASSWORD" | in_chroot "chpasswd" 2>/dev/null || \
  in_chroot "echo root:$ROOT_PASSWORD | chpasswd"

in_chroot "adduser -D -s /bin/sh $DEFAULT_USER"
echo "$DEFAULT_USER:$DEFAULT_PASSWORD" | in_chroot "chpasswd"

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

# --- modules-load.d ---
install -Dm644 "$TOP/overlay/etc/modules-load.d/rg35xxh.conf" \
  "$ROOTFS/etc/modules-load.d/rg35xxh.conf"

# --- overlay ---
echo "Copying overlay..."
cp -a "$TOP/overlay/." "$ROOTFS/"

echo "Done: $ROOTFS"
