#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--private-bus" ]]; then
    exec dbus-run-session -- bash "$0" --private-bus
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-niri-focus.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$probe_root/project" "$probe_root/config" "$probe_root/runtime" "$probe_root/bin"
chmod 0700 "$probe_root/runtime"
_probe_project "$ROOT" scripts/probe-logic.qml "$probe_root/project"
install -m755 scripts/fixtures/niri-focus.sh "$probe_root/bin/niri"
touch "$probe_root/dispatch.log"
log="$probe_root/probe.log"

PATH="$probe_root/bin:$PATH" NIRI_SOCKET="$probe_root/runtime/mock-niri.sock" \
    HYPRLAND_INSTANCE_SIGNATURE="" XDG_CONFIG_HOME="$probe_root/config" \
    XDG_STATE_HOME="$probe_root/config" XDG_RUNTIME_DIR="$probe_root/runtime" \
    SILERE_NIRI_FOCUS_PROBE=1 SILERE_NIRI_FOCUS_LOG="$probe_root/dispatch.log" \
    QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 QT_FORCE_STDERR_LOGGING=1 \
    qs -p "$probe_root/project/probe-logic.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-NIRI-FOCUS' 80 0.25 || true
if ! grep -q 'PROBE-NIRI-FOCUS passed' "$log" || grep -q 'PROBE-FAIL' "$log" \
        || [[ -n "$(_probe_errors "$log")" ]]; then
    cat "$log" >&2
    echo "FAIL: mock Niri focus probe" >&2
    exit 1
fi
grep -oE 'PROBE-NIRI-FOCUS passed .*' "$log" | tail -1
