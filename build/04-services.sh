#!/bin/bash
# Wire up OpenRC services in the rootfs.
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/util.sh"

assert_rootfs

enable_service() {
  local svc="$1" runlevel="${2:-default}"
  ln -sf "/etc/init.d/$svc" "$ROOTFS/etc/runlevels/$runlevel/$svc"
}

# --- getty ---
# tty0 (the screen) and ttyS0 (serial, useful for debugging)
enable_service agetty.tty0 default
enable_service agetty.ttyS0 default

# Agetty needs per-tty symlinks for OpenRC; create the init.d entries
ln -sf agetty "$ROOTFS/etc/init.d/agetty.tty0"
ln -sf agetty "$ROOTFS/etc/init.d/agetty.ttyS0"

# Configure agetty for each tty
mkdir -p "$ROOTFS/etc/conf.d"
cat > "$ROOTFS/etc/conf.d/agetty.tty0" <<'EOF'
agetty_tty=tty0
agetty_options="-8 --noclear"
EOF

cat > "$ROOTFS/etc/conf.d/agetty.ttyS0" <<'EOF'
agetty_tty=ttyS0
agetty_baud_rate=115200
EOF

# --- iwd ---
enable_service iwd default

# --- SSH (optional) ---
if [ "$ENABLE_SSH" = "true" ]; then
  enable_service sshd default
fi

# --- modules (loads modules-load.d entries including joypad) ---
enable_service modules boot

# --- resize (first boot, self-deletes) ---
install -Dm755 "$TOP/overlay/etc/init.d/rg35xxh-resize" \
  "$ROOTFS/etc/init.d/rg35xxh-resize"
enable_service rg35xxh-resize boot

echo "Done: services configured"
