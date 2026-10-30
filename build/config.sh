# Shared build configuration — sourced by every build script.
TOP="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
WORK="${WORK:-$TOP/work}"

# --- ROCKNIX hardware layer ---
ROCKNIX_VERSION="20261001"
RAM_TYPE="${RAM_TYPE:-DDR4}"          # DDR4 (default) or DDR3
ROCKNIX_IMAGE="ROCKNIX-H700.aarch64-${ROCKNIX_VERSION}-${RAM_TYPE}.img.gz"
ROCKNIX_URL="https://github.com/ROCKNIX/distribution/releases/download/${ROCKNIX_VERSION}/${ROCKNIX_IMAGE}"
ROCKNIX_DL="$WORK/download"
ROCKNIX_EX="$WORK/rocknix"
KVER="7.2.0"

# --- Alpine ---
ALPINE_VERSION="3.24.3"
ALPINE_ARCH="aarch64"
ALPINE_URL="https://dl-cdn.alpinelinux.org/alpine/v${ALPINE_VERSION%.*}/releases/${ALPINE_ARCH}/alpine-minirootfs-${ALPINE_VERSION}-${ALPINE_ARCH}.tar.gz"
ALPINE_SHA256="4d3f80afaebd447c5591a63a73bde380a149fe8b2d85488cafabb2ff97551f50"

# --- Panel ---
# Which screen panel does this unit have?
# regular = sun50i-h700-anbernic-rg35xx-h.dtb
# rev6    = sun50i-h700-anbernic-rg35xx-h-rev6-panel.dtb
# Check with: sudo gpioget --bias=pull-up --chip /dev/gpiochip1 134
#   "active" = regular, "inactive" = rev6
PANEL="${PANEL:-regular}"

# --- System identity ---
HOSTNAME="${HOSTNAME:-rg35xxh}"
TIMEZONE="${TIMEZONE:-UTC}"

# --- Users ---
ROOT_PASSWORD="${ROOT_PASSWORD:-root}"
DEFAULT_USER="${DEFAULT_USER:-alpine}"
DEFAULT_PASSWORD="${DEFAULT_PASSWORD:-alpine}"
DEFAULT_USER_WHEEL="${DEFAULT_USER_WHEEL:-true}"

# --- Features ---
ENABLE_SSH="${ENABLE_SSH:-true}"

# --- Image layout ---
DISK_ID="0x52473335"
BOOT_START_MIB=16
BOOT_SIZE_MIB=256
BOOT_LABEL="RG35XXHBOOT"
ROOT_LABEL="rg35xxh-root"
PARTUUID_ROOT="$(printf '%08x' "$DISK_ID")-02"

# --- Derived ---
ROOTFS="$WORK/rootfs"

case "$PANEL" in
  regular) DTB="sun50i-h700-anbernic-rg35xx-h.dtb" ;;
  rev6)    DTB="sun50i-h700-anbernic-rg35xx-h-rev6-panel.dtb" ;;
  *) echo "config.sh: PANEL must be 'regular' or 'rev6', got '$PANEL'" >&2; exit 1 ;;
esac
