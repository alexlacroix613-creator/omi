#!/usr/bin/env bash
# Build/update the one permanent local app identity. Keeping this name and
# bundle ID stable preserves macOS privacy grants across releases.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MACOS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$MACOS_DIR"

export OMI_APP_NAME="Omi Companion"
export OMI_SKIP_AUTH_SEED=1
export OMI_SKIP_SETTINGS_SEED=1
export OMI_SKIP_STALE_BUNDLE_SCAN=1

exec ./run.sh "$@"
