#!/usr/bin/env bash
set -euo pipefail

# A real sender must never reach the desktop's notification daemon.
if [[ "${1:-}" != "--private-bus" ]]; then
    exec dbus-run-session -- bash "$0" --private-bus
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-notification-reload.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$probe_root/config-home/silere-shell" "$probe_root/runtime" "$probe_root/project"
chmod 0700 "$probe_root/runtime"
_probe_project "$ROOT" scripts/probe-notification-reload.qml "$probe_root/project"

for retention in true false; do
    printf '{"__version":1,"notifHistoryLimit":100,"notifHistoryPersistent":%s}\n' \
        "$retention" > "$probe_root/config-home/silere-shell/settings.json"
    log="$probe_root/$retention.log"
    XDG_CONFIG_HOME="$probe_root/config-home" XDG_STATE_HOME="$probe_root/config-home" \
        XDG_RUNTIME_DIR="$probe_root/runtime" QT_FORCE_STDERR_LOGGING=1 \
        QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 \
        qs -p "$probe_root/project/probe-notification-reload.qml" --no-color >"$log" 2>&1 &
    probe_pid=$!
    _probe_wait "$log" "$probe_pid" 'PROBE-RELOAD-DONE' 80 0.25 || true
    if ! grep -q 'PROBE-RELOAD passed' "$log" || grep -q 'PROBE-FAIL' "$log" \
            || [[ -n "$(_probe_errors "$log")" ]]; then
        cat "$log" >&2
        echo "FAIL: notification reload probe (retention=$retention)" >&2
        exit 1
    fi
    grep -oE 'PROBE-RELOAD passed [0-9]+ checks' "$log" | tail -1
    _probe_stop "$probe_pid"
    probe_pid=""
done
