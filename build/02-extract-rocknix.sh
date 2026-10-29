#!/bin/bash
# Extract the hardware layer from the ROCKNIX image:
#   boot/        KERNEL, device_trees/
#   bootloader/  u-boot-sunxi-with-spl.bin, bl31.bin
#   modules/     lib/modules/<kver>
#   firmware/    lib/firmware
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/util.sh"

IMG_GZ="$ROCKNIX_DL/$ROCKNIX_IMAGE"
[ -f "$IMG_GZ" ] || die "ROCKNIX image not found — run 01-fetch-rocknix.sh first"

TMP="$WORK/tmp-extract"
rm -rf "$ROCKNIX_EX" "$TMP"
mkdir -p "$ROCKNIX_EX"/{boot,bootloader,modules,firmware} "$TMP"

echo "Decompressing image..."
gunzip -c "$IMG_GZ" > "$TMP/rocknix.img"

# Find FAT boot partition offset from the partition table
P1_START=$(sfdisk -d "$TMP/rocknix.img" | awk -F'[=,]' '/img1/{gsub(/ /,"",$2); print $2}')
FAT="$TMP/rocknix.img@@$((P1_START * 512))"
export MTOOLS_SKIP_CHECK=1

echo "Copying boot files..."
mcopy -s -n -i "$FAT" ::/KERNEL ::/device_trees "$ROCKNIX_EX/boot/"
mcopy -n -i "$FAT" ::/SYSTEM "$TMP/SYSTEM"

echo "Extracting SYSTEM squashfs..."
unsquashfs -q -n -d "$TMP/sys" "$TMP/SYSTEM" \
  usr/share/bootloader \
  "usr/lib/kernel-overlays/base/lib" >/dev/null

cp "$TMP/sys/usr/share/bootloader/H700_${RAM_TYPE}_u-boot-sunxi-with-spl.bin" \
   "$ROCKNIX_EX/bootloader/u-boot-sunxi-with-spl.bin"
cp "$TMP/sys/usr/share/bootloader/bl31.bin" "$ROCKNIX_EX/bootloader/" 2>/dev/null || true
cp -a "$TMP/sys/usr/lib/kernel-overlays/base/lib/modules/." "$ROCKNIX_EX/modules/"
cp -a "$TMP/sys/usr/lib/kernel-overlays/base/lib/firmware/." "$ROCKNIX_EX/firmware/"

KVER_FOUND=$(ls "$ROCKNIX_EX/modules")
[ "$KVER_FOUND" = "$KVER" ] || echo "warning: expected kernel $KVER but found $KVER_FOUND"

rm -rf "$TMP"
echo "Done: $ROCKNIX_EX (kernel $KVER_FOUND)"
