#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-upstream-connectivity-paths.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$probe_root/config/silere-shell" "$probe_root/runtime" "$probe_root/project"
chmod 0700 "$probe_root/runtime"
printf '{"__version":1}\n' > "$probe_root/config/silere-shell/settings.json"
cp -a "$ROOT/services" "$ROOT/modules" "$probe_root/project/"
ln -s "$ROOT/config" "$probe_root/project/config"
cp "$ROOT/scripts/probe-upstream-connectivity-paths.qml" "$probe_root/project/"

# The copied services retain their production algorithms. These substitutions
# expose their live backend inputs and shorten the pair guard for the probe.
sed -i 's/readonly property bool toolAvailable: Networking.backend !== NetworkBackendType.None/property bool toolAvailable: true/' \
    "$probe_root/project/services/Network.qml"
sed -i 's/readonly property var _devices: Networking.devices.values || \[\]/property var _devices: []/' \
    "$probe_root/project/services/Network.qml"
sed -i 's/readonly property bool wifiEnabled: Networking.wifiEnabled/property bool wifiEnabled: true/' \
    "$probe_root/project/services/Network.qml"
sed -i '/readonly property bool wifiHardBlocked:/,/&& !Networking.wifiHardwareEnabled/c\    property bool wifiHardBlocked: false' \
    "$probe_root/project/services/Network.qml"
sed -i 's/readonly property var adapter: Bt.Bluetooth.defaultAdapter/property var adapter: null/' \
    "$probe_root/project/services/Bluetooth.qml"
sed -i 's/interval: 20000/interval: 40/' "$probe_root/project/services/Bluetooth.qml"
# The production row types are internal to their module; export them only in the
# disposable project so this probe can drive their real handlers.
sed -i -e 's/^internal WifiList /WifiList /' \
    -e 's/^internal BluetoothList /BluetoothList /' \
    "$probe_root/project/modules/menu/qmldir"

XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" \
    XDG_RUNTIME_DIR="$probe_root/runtime" QT_FORCE_STDERR_LOGGING=1 \
    QT_QPA_PLATFORM=offscreen \
    qs -p "$probe_root/project/probe-upstream-connectivity-paths.qml" --no-color >"$probe_root/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$probe_root/probe.log" "$probe_pid" 'PROBE-UPSTREAM-CONNECTIVITY-PATHS' 100 0.25 || true

errs="$(_probe_errors "$probe_root/probe.log")"
if ! grep -q 'PROBE-UPSTREAM-CONNECTIVITY-PATHS passed' "$probe_root/probe.log" \
        || grep -q 'PROBE-FAIL' "$probe_root/probe.log" || [ -n "$errs" ]; then
    cat "$probe_root/probe.log" >&2
    echo 'FAIL: connectivity service-path probe failed or logged a runtime error' >&2
    exit 1
fi
grep -oE 'PROBE-UPSTREAM-CONNECTIVITY-PATHS passed [0-9]+ checks' "$probe_root/probe.log" | tail -1
