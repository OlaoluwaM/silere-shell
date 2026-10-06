#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
# a disposable shell registers the notification server; on the desktop bus it could claim the
# live daemon's name should that daemon drop out mid-run. The launcher never returns
if [[ "${1:-}" != "--private-bus" ]]; then
    _probe_private_bus "$0" "$@"
fi
shift
_probe_require_qs

log="$(mktemp "${TMPDIR:-/tmp}/silere-recent-geometry.XXXXXX.log")"
cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-recent-geometry-cfg.XXXXXX")"
runtime="$(mktemp -d "${TMPDIR:-/tmp}/silere-recent-geometry-runtime.XXXXXX")"
probe_project="$(mktemp -d "${TMPDIR:-/tmp}/silere-recent-geometry-project.XXXXXX")"
chmod 0700 "$runtime"
_probe_project "$ROOT" scripts/probe-recent-geometry.qml "$probe_project"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -f "$log"
    rm -rf "$cfg" "$runtime" "$probe_project"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

# the probe seeds notification history, which the service also writes to disk
mkdir -p "$cfg/silere-shell"
printf '{"__version":1}\n' > "$cfg/silere-shell/settings.json"

XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_CACHE_HOME="$cfg/cache" XDG_RUNTIME_DIR="$runtime" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 \
    setsid qs -p "$probe_project/probe-recent-geometry.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-RECENT-DONE' 80 0.25 || true
if ! grep -q 'PROBE-RECENT-GEOMETRY passed' "$log" || grep -q 'PROBE-FAIL' "$log" \
        || [[ -n "$(_probe_errors "$log")" ]]; then
    cat "$log" >&2
    echo "FAIL: recent page geometry probe" >&2
    exit 1
fi
grep -oE 'PROBE-RECENT-GEOMETRY passed [0-9]+ checks' "$log" | tail -1
