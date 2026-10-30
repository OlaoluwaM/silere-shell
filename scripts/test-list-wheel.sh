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

log="$(mktemp "${TMPDIR:-/tmp}/silere-list-wheel.XXXXXX.log")"
cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-list-wheel-cfg.XXXXXX")"
runtime="$(mktemp -d "${TMPDIR:-/tmp}/silere-list-wheel-runtime.XXXXXX")"
probe_project="$(mktemp -d "${TMPDIR:-/tmp}/silere-list-wheel-project.XXXXXX")"
chmod 0700 "$runtime"
_probe_project "$ROOT" scripts/probe-list-wheel.qml "$probe_project"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -f "$log"
    rm -rf "$cfg" "$runtime" "$probe_project"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$cfg/silere-shell"
printf '{"__version":1}\n' > "$cfg/silere-shell/settings.json"

XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_CACHE_HOME="$cfg/cache" XDG_RUNTIME_DIR="$runtime" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 \
    setsid qs -p "$probe_project/probe-list-wheel.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-LIST-WHEEL-DONE' 80 0.25 || true
if ! grep -q 'PROBE-LIST-WHEEL passed' "$log" || grep -q 'PROBE-FAIL' "$log" \
        || [[ -n "$(_probe_errors "$log")" ]]; then
    cat "$log" >&2
    echo "FAIL: nested list wheel probe" >&2
    exit 1
fi
grep -oE 'PROBE-LIST-WHEEL passed [0-9]+ checks' "$log" | tail -1
