#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
# a disposable shell registers the notification server; on the desktop bus it could claim the
# live daemon's name should that daemon drop out mid-run. The launcher never returns
if [[ "${1:-}" != "--private-bus" ]]; then
    _probe_private_bus "$0" "$@"
fi
shift
_probe_require_qs

# the trap goes first: a failed mktemp below would otherwise leave the
# directories already made behind
probe_project=""
probe_root=""
log=""
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    [ -z "$probe_project" ] || rm -rf "$probe_project"
    [ -z "$probe_root" ] || rm -rf "$probe_root"
    [ -z "$log" ] || rm -f "$log"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

probe_project="$(mktemp -d "${TMPDIR:-/tmp}/silere-history-grouping-project.XXXXXX")"
probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-history-grouping.XXXXXX")"
log="$(mktemp "${TMPDIR:-/tmp}/silere-history-grouping.XXXXXX.log")"

# the probe loads no settings today; a private config keeps a later one that does off the
# user's own silere-shell directory
mkdir -p "$probe_root/config/silere-shell" "$probe_root/runtime"
chmod 0700 "$probe_root/runtime"
_probe_project "$ROOT" scripts/probe-history-grouping.qml "$probe_project"

SILERE_PROBE_ROOT="$probe_project" XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" \
    XDG_CACHE_HOME="$probe_root/config/cache" XDG_RUNTIME_DIR="$probe_root/runtime" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 \
    setsid qs -p "$probe_project/probe-history-grouping.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-HISTORY-DONE' 80 0.25 || true
if ! grep -q 'PROBE-HISTORY passed' "$log" || grep -q 'PROBE-FAIL' "$log" \
        || [[ -n "$(_probe_errors "$log")" ]]; then
    cat "$log" >&2
    echo "FAIL: history grouping probe" >&2
    exit 1
fi
grep -oE 'PROBE-HISTORY passed [0-9]+ checks' "$log" | tail -1
