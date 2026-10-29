#!/bin/bash
# Download the ROCKNIX H700 release image and verify its SHA-256 checksum.
set -euo pipefail
source "$(dirname "$0")/config.sh"
source "$(dirname "$0")/lib/util.sh"

mkdir -p "$ROCKNIX_DL"

echo "Fetching checksum..."
curl -fsSL -o "$ROCKNIX_DL/$ROCKNIX_IMAGE.sha256" "$ROCKNIX_URL.sha256"
expected="$(awk '{print $1}' "$ROCKNIX_DL/$ROCKNIX_IMAGE.sha256")"

fetch "$ROCKNIX_URL" "$ROCKNIX_DL/$ROCKNIX_IMAGE" "$expected"
echo "OK: $ROCKNIX_IMAGE"
