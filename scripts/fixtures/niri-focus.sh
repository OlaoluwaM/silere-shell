#!/usr/bin/env bash
set -euo pipefail

# Record argv boundaries without contacting any compositor.
printf '%s\n' "$(printf '<%s>' "$@")" >> "${SILERE_NIRI_FOCUS_LOG:?}"
