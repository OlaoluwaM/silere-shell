#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
PROBE_SOURCE="scripts/probe-upstream-services.qml"

_probe_require_qs

log="$(mktemp "${TMPDIR:-/tmp}/silere-upstream-services.XXXXXX.log")"
cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-upstream-services-cfg.XXXXXX")"
runtime="$(mktemp -d "${TMPDIR:-/tmp}/silere-upstream-services-runtime.XXXXXX")"
project="$(mktemp -d "${TMPDIR:-/tmp}/silere-upstream-services-project.XXXXXX")"
chmod 0700 "$runtime"
_probe_project "$ROOT" "$PROBE_SOURCE" "$project"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -f "$log"
    rm -rf "$cfg" "$runtime" "$project"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$cfg/silere-shell"
printf '{"__version":1}\n' > "$cfg/silere-shell/settings.json"

XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_RUNTIME_DIR="$runtime" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    qs -p "$project/probe-upstream-services.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-UPSTREAM-SERVICES' 80 0.25 || true

if ! grep -q 'PROBE-UPSTREAM-SERVICES passed' "$log" 2>/dev/null; then
    cat "$log" >&2
    echo "FAIL: upstream service regression probe did not pass" >&2
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

grep -oE 'PROBE-UPSTREAM-SERVICES passed [0-9]+ checks' "$log" | tail -1
