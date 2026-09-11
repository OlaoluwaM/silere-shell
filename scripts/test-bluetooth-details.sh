#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--private-bus" ]]; then
    exec dbus-run-session -- bash "$0" --private-bus
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-bluetooth-details.XXXXXX")"
probe_project="$probe_root/project"
log="$probe_root/probe.log"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    # Generated probe data must also clean up when the trash directory is unusable.
    if command -v rip >/dev/null 2>&1 && rip -f "$probe_root" >/dev/null 2>&1; then
        return
    fi
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$probe_project" "$probe_root/config/silere-shell" "$probe_root/runtime"
chmod 0700 "$probe_root/runtime"
printf '{"__version":1}\n' > "$probe_root/config/silere-shell/settings.json"
cp -a "$ROOT/services" "$ROOT/modules" "$probe_project/"
cp "$ROOT/scripts/fixtures/bluetooth/Bluetooth.qml" "$probe_project/services/Bluetooth.qml"
# Expose the internal type only inside this disposable test module.
sed -i 's/^internal BluetoothList BluetoothList.qml$/BluetoothList 1.0 BluetoothList.qml/' \
    "$probe_project/modules/menu/qmldir"
ln -s "$ROOT/config" "$probe_project/config"
cp "$ROOT/scripts/probe-bluetooth-details.qml" "$probe_project/probe-bluetooth-details.qml"

XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" \
    XDG_CACHE_HOME="$probe_root/cache" XDG_RUNTIME_DIR="$probe_root/runtime" \
    HYPRLAND_INSTANCE_SIGNATURE="" NIRI_SOCKET="" QT_NO_XDG_DESKTOP_PORTAL=1 \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    qs -p "$probe_project/probe-bluetooth-details.qml" --no-color >"$log" 2>&1 &
probe_pid=$!
_probe_wait "$log" "$probe_pid" 'PROBE-BLUETOOTH-DETAILS' 80 0.25 || true

errs="$(_probe_errors "$log")"
if ! grep -q 'PROBE-BLUETOOTH-DETAILS passed' "$log" \
        || grep -q 'PROBE-FAIL' "$log" || [ -n "$errs" ]; then
    cat "$log" >&2
    echo 'FAIL: Bluetooth details probe failed or logged a runtime error' >&2
    exit 1
fi
grep -oE 'PROBE-BLUETOOTH-DETAILS passed [0-9]+ checks' "$log" | tail -1
