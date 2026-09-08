#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--private-bus" ]]; then
    exec dbus-run-session -- bash "$0" --private-bus
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

_probe_require_qs

case "${WAYLAND_DISPLAY:-}" in
    /*) wayland_socket="$WAYLAND_DISPLAY" ;;
    "") echo "SKIP: a Wayland compositor is required for the bar hint surface" >&2; exit 0 ;;
    *) wayland_socket="${XDG_RUNTIME_DIR:-}/$WAYLAND_DISPLAY" ;;
esac
if [ ! -S "$wayland_socket" ]; then
    echo "SKIP: Wayland socket is unavailable: $wayland_socket" >&2
    exit 0
fi

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-bar-hint.XXXXXX")"
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

mkdir -p "$cfg/silere-shell" "$runtime" "$probe_project/services"
chmod 0700 "$runtime"
printf '{"__version":1}\n' > "$cfg/silere-shell/settings.json"

cp "$ROOT/scripts/probe-bar-hint-idle.qml" "$probe_project/probe-bar-hint-idle.qml"
cp -a "$ROOT/services/." "$probe_project/services/"
ln -s "$ROOT/config" "$probe_project/config"
ln -s "$ROOT/modules" "$probe_project/modules"

# The private project replaces only the idle source. Production keeps the real
# compositor-backed singleton, while the probe can drive each transition without
# blanking the maintainer's display or adding a test seam to the shipped component.
cat > "$probe_project/services/Idle.qml" <<'EOF'
pragma Singleton

import QtQuick
import Quickshell

Singleton {
    property bool isIdle: false
    readonly property bool isQuiet: isIdle
}
EOF

XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_RUNTIME_DIR="$runtime" \
    WAYLAND_DISPLAY="$wayland_socket" QT_FORCE_STDERR_LOGGING=1 \
    QT_QPA_PLATFORM=wayland QT_NO_XDG_DESKTOP_PORTAL=1 \
    qs -p "$probe_project/probe-bar-hint-idle.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-BAR-HINT-IDLE' 80 0.25 || true

if ! grep -q 'PROBE-BAR-HINT-IDLE passed' "$log" 2>/dev/null; then
    cat "$log" >&2
    echo "FAIL: bar hint idle probe did not pass" >&2
    exit 1
fi

failed=0
if grep -q 'PROBE-FAIL' "$log"; then
    grep 'PROBE-FAIL' "$log" | sed 's/^.*PROBE-FAIL/  /' | sort -u >&2
    failed=1
fi
errs="$(_probe_errors "$log")"
if [ -n "$errs" ]; then
    printf '%s\n' "$errs" | sed 's/^/  /' >&2
    failed=1
fi
if [ "$failed" -ne 0 ]; then
    echo "FAIL: bar hint idle probe logged a runtime error" >&2
    exit 1
fi

grep -oE 'PROBE-BAR-HINT-IDLE passed [0-9]+ checks' "$log" | tail -1
