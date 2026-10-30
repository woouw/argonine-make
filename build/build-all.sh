#!/bin/bash
# Run all build steps in order.
# Re-run individual scripts to resume from a failed step.
#
# Local overrides: copy local.env.example to local.env and edit it.
# local.env is gitignored — safe to put passwords and personal settings there.
set -euo pipefail
cd "$(dirname "$0")"

# Load local overrides if present (must be before config.sh is sourced)
LOCAL_ENV="$(dirname "$0")/../local.env"
if [ -f "$LOCAL_ENV" ]; then
  # shellcheck disable=SC1090
  set -a; source "$LOCAL_ENV"; set +a
  echo "Loaded local.env"
fi

bash 01-fetch-rocknix.sh
bash 02-extract-rocknix.sh
bash 03-rootfs.sh
bash 04-services.sh
bash 05-image.sh
