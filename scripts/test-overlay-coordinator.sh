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
printf '{"__version":1}\n' > "$cfg/silere-shell/settings.json"
cp -a "$ROOT/services" "$probe_project/services"
cp "$ROOT/scripts/fixtures/coordinator/Idle.qml" "$probe_project/services/Idle.qml"
cp "$ROOT/scripts/fixtures/coordinator/OverviewState.qml" "$probe_project/services/OverviewState.qml"
cp "$ROOT/scripts/probe-overlay-coordinator.qml" "$probe_project/probe-overlay-coordinator.qml"
ln -s "$ROOT/config" "$probe_project/config"
ln -s "$ROOT/modules" "$probe_project/modules"

XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_RUNTIME_DIR="$runtime" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 \
    qs -p "$probe_project/probe-overlay-coordinator.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

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
