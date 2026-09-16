#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

_probe_require_qs

log="$(mktemp "${TMPDIR:-/tmp}/silere-fullscreen-state.XXXXXX.log")"
project="$(mktemp -d "${TMPDIR:-/tmp}/silere-fullscreen-state-project.XXXXXX")"
mkdir -p "$project/services"
cp scripts/probe-fullscreen-state.qml "$project/"
cp services/FullscreenState.qml "$project/services/"
cp scripts/fixtures/fullscreen/Compositor.qml scripts/fixtures/fullscreen/ShellSettings.qml \
    scripts/fixtures/fullscreen/qmldir "$project/services/"
printf '%s\n' 'singleton FullscreenState 1.0 FullscreenState.qml' >> "$project/services/qmldir"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -f "$log"
    rm -rf "$project"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    qs -p "$project/probe-fullscreen-state.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-FULLSCREEN-STATE' 80 0.25 || true

if ! grep -q 'PROBE-FULLSCREEN-STATE passed' "$log" 2>/dev/null; then
    cat "$log" >&2
    echo "FAIL: fullscreen state probe did not pass" >&2
    exit 1
fi

if grep -q 'PROBE-FAIL' "$log"; then
    grep 'PROBE-FAIL' "$log" | sed 's/^.*PROBE-FAIL/  /' >&2
    exit 1
fi

errs="$(_probe_errors "$log")"
if [ -n "$errs" ]; then
    printf '%s\n' "$errs" | sed 's/^/  /' >&2
    exit 1
fi

grep -oE 'PROBE-FULLSCREEN-STATE passed [0-9]+ checks' "$log" | tail -1
