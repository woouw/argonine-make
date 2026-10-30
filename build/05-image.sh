#!/bin/bash
# Assemble the flashable SD card image.
# No loop devices: FAT built with mtools, ext4 with mkfs.ext4 -d.
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/util.sh"

assert_rootfs
assert_rocknix

OUT="$WORK/out"; mkdir -p "$OUT"
P="$WORK/image-parts"; rm -rf "$P"; mkdir -p "$P/boot/extlinux"

# --- rootfix.cpio (adds missing /root dir to ROCKNIX's built-in initramfs) ---
RF="$P/rootfix"; mkdir -m 0700 -p "$RF/root"
(cd "$RF" && echo root | cpio -o -H newc -R 0:0 --quiet) > "$P/boot/rootfix.cpio"

# --- extlinux.conf ---
cat > "$P/boot/extlinux/extlinux.conf" <<EOF
LABEL rg35xxh
  LINUX /KERNEL
  INITRD /rootfix.cpio
  FDT /dtb.img
  APPEND root=PARTUUID=$PARTUUID_ROOT rootwait rootfstype=ext4 ro rdinit=/nonexistent console=ttyS0,115200 console=tty0 loglevel=4
EOF

# --- boot files ---
cp "$ROCKNIX_EX/boot/KERNEL" "$P/boot/KERNEL"
cp "$ROCKNIX_EX/boot/device_trees/$DTB" "$P/boot/dtb.img"
cp "$TOP/boot-files/panel.txt" "$P/boot/panel.txt"

# --- sizes ---
ROOT_USED_MIB=$(du -smx "$ROOTFS" | cut -f1)
ROOT_SIZE_MIB=$(( (ROOT_USED_MIB * 125 / 100 + 256 + 63) / 64 * 64 ))
TOTAL_MIB=$(( BOOT_START_MIB + BOOT_SIZE_MIB + ROOT_SIZE_MIB + 1 ))
echo "rootfs ${ROOT_USED_MIB} MiB → root partition ${ROOT_SIZE_MIB} MiB, image ${TOTAL_MIB} MiB"

VER="$(date +%Y%m%d)"
IMG="$OUT/rg35xxh-alpine-${PANEL}-${VER}.img"

# --- FAT boot partition ---
mkfs.vfat -F 32 -n "$BOOT_LABEL" -C "$P/boot.vfat" $(( BOOT_SIZE_MIB * 1024 )) >/dev/null
# mcopy each item explicitly to avoid glob picking up boot.vfat itself
MTOOLS_SKIP_CHECK=1 mcopy -i "$P/boot.vfat" "$P/boot/KERNEL" "$P/boot/dtb.img" \
  "$P/boot/rootfix.cpio" "$P/boot/panel.txt" ::/
MTOOLS_SKIP_CHECK=1 mcopy -s -i "$P/boot.vfat" "$P/boot/extlinux" ::/

# --- ext4 root partition ---
mkfs.ext4 -q -F -L "$ROOT_LABEL" -d "$ROOTFS" -E root_owner=0:0 "$P/root.ext4" "${ROOT_SIZE_MIB}M"
e2fsck -fn "$P/root.ext4" >/dev/null

# --- assemble ---
truncate -s "${TOTAL_MIB}M" "$IMG.part"
sfdisk -q "$IMG.part" <<EOF
label: dos
label-id: $DISK_ID
start=$(( BOOT_START_MIB * 2048 )), size=$(( BOOT_SIZE_MIB * 2048 )), type=c, bootable
start=$(( (BOOT_START_MIB + BOOT_SIZE_MIB) * 2048 )), size=$(( ROOT_SIZE_MIB * 2048 )), type=83
EOF

dd if="$ROCKNIX_EX/bootloader/u-boot-sunxi-with-spl.bin" of="$IMG.part" bs=1024 seek=8 conv=notrunc status=none
dd if="$P/boot.vfat" of="$IMG.part" bs=1M seek="$BOOT_START_MIB" conv=notrunc status=none
dd if="$P/root.ext4" of="$IMG.part" bs=1M seek=$(( BOOT_START_MIB + BOOT_SIZE_MIB )) conv=notrunc status=none
mv "$IMG.part" "$IMG"
rm -rf "$P"

echo "Compressing..."
xz -T0 -6 -k -f "$IMG"
( cd "$OUT" && sha256sum "$(basename "$IMG").xz" > "$(basename "$IMG").xz.sha256" )
echo "Done: $IMG.xz"
ls -lh "$OUT"
