#!/usr/bin/env bash
set -euo pipefail

if [ "${1:-}" != "--private-bus" ]; then
    exec dbus-run-session -- bash "$0" --private-bus
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
_probe_require_qs

probe_project="$(mktemp -d "${TMPDIR:-/tmp}/silere-history-grouping-project.XXXXXX")"
runtime="$(mktemp -d "${TMPDIR:-/tmp}/silere-history-grouping-runtime.XXXXXX")"
log="$(mktemp "${TMPDIR:-/tmp}/silere-history-grouping.XXXXXX.log")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -rf "$probe_project" "$runtime"
    rm -f "$log"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

chmod 0700 "$runtime"
_probe_project "$ROOT" scripts/probe-history-grouping.qml "$probe_project"

SILERE_PROBE_ROOT="$probe_project" XDG_RUNTIME_DIR="$runtime" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 \
    qs -p "$probe_project/probe-history-grouping.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-HISTORY-DONE' 80 0.25 || true
if ! grep -q 'PROBE-HISTORY passed' "$log" || grep -q 'PROBE-FAIL' "$log" \
        || [[ -n "$(_probe_errors "$log")" ]]; then
    cat "$log" >&2
    echo "FAIL: history grouping probe" >&2
    exit 1
fi
grep -oE 'PROBE-HISTORY passed [0-9]+ checks' "$log" | tail -1
