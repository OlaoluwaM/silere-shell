#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--private-bus" ]]; then
    exec dbus-run-session -- bash "$0" --private-bus
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-overlay-coordinator.XXXXXX")"
log="$probe_root/probe.log"
cfg="$probe_root/config"
runtime="$probe_root/runtime"
probe_project="$probe_root/project"
probe_pid=""

cleanup() {
    _probe_stop "$probe_pid"
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$cfg/silere-shell" "$runtime" "$probe_project"
chmod 0700 "$runtime"
python3 - "$cfg" <<'PY'
import json
from pathlib import Path
import sys

cfg = Path(sys.argv[1])
keybinds = cfg / 'keybinds.json'
keybinds.write_text(json.dumps([{'keys': 'Super+K', 'desc': 'Fixture', 'group': 'Probe'}]))
(cfg / 'silere-shell/settings.json').write_text(json.dumps({
    '__version': 1, 'keybindsFile': str(keybinds), 'wallpaperCommand': 'true',
}))
PY
cp -a "$ROOT/services" "$probe_project/services"
cp "$ROOT/scripts/fixtures/coordinator/Idle.qml" "$probe_project/services/Idle.qml"
cp "$ROOT/scripts/fixtures/coordinator/OverviewState.qml" "$probe_project/services/OverviewState.qml"
cp -a "$ROOT/scripts/fixtures/popup-state" "$probe_project/popup-fixtures"
cp "$ROOT/scripts/fixtures/popup-state/Media.qml" "$probe_project/services/Media.qml"
# Keep the real state and lifecycle; supply controllable tray membership.
sed -i 's@import Quickshell.Services.SystemTray@import "../popup-fixtures"@' \
    "$probe_project/services/TrayPopupState.qml"
cp "$ROOT/scripts/probe-overlay-coordinator.qml" "$probe_project/probe-overlay-coordinator.qml"
ln -s "$ROOT/config" "$probe_project/config"
ln -s "$ROOT/modules" "$probe_project/modules"

# Keep compositor selection independent of the host. The fixture session ID
# lets logout availability follow the controlled loginctl flag.
XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_RUNTIME_DIR="$runtime" \
    HYPRLAND_INSTANCE_SIGNATURE="" NIRI_SOCKET="" XDG_SESSION_ID=probe \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 \
    qs -p "$probe_project/probe-overlay-coordinator.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-OVERLAY-READY' 100 0.25 || true
if ! grep -q 'PROBE-OVERLAY-READY' "$log"; then
    cat "$log" >&2
    echo 'FAIL: popup states did not bootstrap cold IPC readiness' >&2
    exit 1
fi
ipc() {
    XDG_RUNTIME_DIR="$runtime" qs ipc -p "$probe_project/probe-overlay-coordinator.qml" call -- "$@"
}
fail() { cat "$log" >&2; echo "FAIL: $*" >&2; exit 1; }
expect_reply() {
    local label="$1" expected="$2" reply
    shift 2
    if ! reply="$(ipc "$@")"; then
        fail "$label: IPC call failed"
    fi
    # The expected value may be a glob, such as error:*.
    # shellcheck disable=SC2053
    if [[ "$reply" != $expected ]]; then
        fail "$label: expected $expected, got $reply"
    fi
}
ipc keybinds toggle
expect_reply 'cold keybinds IPC' ok popupProbe verify keybinds
ipc wallpapers toggle
expect_reply 'cold wallpapers IPC' ok popupProbe verify wallpapers
# Control availability independently of the tools installed on the test host.
ipc popupProbe powerTools false
for action in logout reboot poweroff; do
    expect_reply "$action unavailable" 'error: the requested power command is unavailable' power request "$action"
    expect_reply "$action unavailable stays closed" ok popupProbe verifyPower closed
done
ipc popupProbe powerTools true
for action in logout reboot poweroff; do
    expect_reply "$action accepted" ok power request "$action"
    expect_reply "$action armed" ok popupProbe verifyPower "$action"
    # An invalid request must not replace an already armed action.
    expect_reply "$action rejects invalid replacement" 'error:*' power request toString
    expect_reply "$action remains armed" ok popupProbe verifyPower "$action"
    ipc power close
    expect_reply "$action cancelled" ok popupProbe verifyPower closed
done
expect_reply 'initial action accepted' ok power request reboot
previous_deadline="$(ipc popupProbe powerDeadline)"
sleep 0.05
expect_reply 'replacement action accepted' ok power request poweroff
expect_reply 'replacement action armed' ok popupProbe verifyPower poweroff
expect_reply 'replacement restarts countdown' ok popupProbe verifyPowerRestart "$previous_deadline"
# Availability refusal must also preserve an existing countdown.
ipc popupProbe powerTools false
expect_reply 'unavailable replacement refused' 'error: the requested power command is unavailable' power request reboot
expect_reply 'refusal preserves armed action' ok popupProbe verifyPower poweroff
ipc popupProbe powerTools true
ipc power close
expect_reply 'replacement cancelled' ok popupProbe verifyPower closed
expect_reply 'unsupported action refused' 'error:*' power request hibernate
expect_reply 'unsupported action stays closed' ok popupProbe verifyPower closed
for environment in idle overview; do
    ipc popupProbe environment "$environment"
    expect_reply "$environment refuses countdown" 'error:*' power request reboot
    expect_reply "$environment stays closed" ok popupProbe verifyPower closed
done
ipc popupProbe environment normal
ipc popupProbe run

_probe_wait "$log" "$probe_pid" 'PROBE-OVERLAY-COORDINATOR' 100 0.25 || true

if ! grep -q 'PROBE-OVERLAY-COORDINATOR passed' "$log" 2>/dev/null; then
    cat "$log" >&2
    echo "FAIL: overlay coordinator probe did not pass" >&2
    exit 1
fi

failed=0
if grep -q 'PROBE-FAIL' "$log"; then
    grep 'PROBE-FAIL' "$log" | sed 's/^.*PROBE-FAIL/  /' | sort -u | head -20 >&2
    failed=1
fi
errs="$(_probe_errors "$log")"
if [ -n "$errs" ]; then
    printf '%s\n' "$errs" | sed 's/^/  /' >&2
    failed=1
fi
if [ "$failed" -ne 0 ]; then
    echo "FAIL: overlay coordinator probe logged a runtime error" >&2
    exit 1
fi

grep -oE 'PROBE-OVERLAY-COORDINATOR passed [0-9]+ checks' "$log" | tail -1
