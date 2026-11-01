#!/bin/bash
# Run all build steps in order.
# Re-run individual scripts to resume from a failed step.
#
# Local overrides: copy local.env.example to local.env and edit it.
# local.env is gitignored — safe to put passwords and personal settings there.
set -euo pipefail
cd "$(dirname "$0")"

bash 01-fetch-rocknix.sh
bash 02-extract-rocknix.sh
bash 03-rootfs.sh
bash 04-services.sh
bash 06-pinpad.sh
bash 05-image.sh
