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

# --- early sysfs mount ---
# GitHub-created overlay files may not retain executable mode; enforce it here.
chmod 755 "$ROOTFS/etc/init.d/rg35xxh-sysfs"
# sysfs is needed by filesystem/device discovery during boot.
enable_service rg35xxh-sysfs sysinit

# --- getty ---
# OpenRC needs an init.d symlink before a runlevel symlink can point at it
ln -sf agetty "$ROOTFS/etc/init.d/agetty.tty0"
ln -sf agetty "$ROOTFS/etc/init.d/agetty.ttyS0"
enable_service agetty.tty0 default
enable_service agetty.ttyS0 default

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

# --- D-Bus (required by iwd) ---
enable_service dbus default

# --- iwd ---
enable_service iwd default

# --- SSH (optional) ---
if [ "$ENABLE_SSH" = "true" ]; then
  enable_service sshd default
fi

# --- modules (loads /etc/modules entries including joypad) ---
enable_service modules boot

# --- resize (first boot, self-deletes; already in rootfs via overlay copy in 03) ---
enable_service rg35xxh-resize boot

echo "Done: services configured"
