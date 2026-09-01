#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

trap 'exit 130' INT TERM

# test-surfaces.sh builds every section under a handful of fixed settings files;
# check.sh loads default-off options once at startup. Neither ever changes a
# setting while a surface is alive, so a binding that only breaks on the change
# itself — a cleared model, a stale cached index, a divide by a now-zero size —
# passes both. This drives the whole schema against surfaces that already exist.
PROBE_SOURCE="$ROOT/scripts/probe-mutate.qml"

_probe_require_qs

list="$(
    find modules/menu/settings -name 'Settings*Section.qml'
    _probe_standalone modules/menu
    _probe_standalone modules/menu/controls
)"
list="$(printf '%s\n' "$list" | sort -u)"
count="$(printf '%s\n' "$list" | grep -c . || true)"
if [ "$count" -eq 0 ]; then
    echo "FAIL: no surfaces to sweep" >&2
    exit 1
fi

log="$(mktemp "${TMPDIR:-/tmp}/silere-mutate.XXXXXX.log")"
cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-mutate-cfg.XXXXXX")"
runtime="$(mktemp -d "${TMPDIR:-/tmp}/silere-mutate-runtime.XXXXXX")"
probe_project="$(mktemp -d "${TMPDIR:-/tmp}/silere-mutate-project.XXXXXX")"
chmod 0700 "$runtime"
_probe_project "$ROOT" "$PROBE_SOURCE" "$probe_project"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -f "$log"
    rm -rf "$cfg" "$runtime" "$probe_project"
}
trap cleanup EXIT

mkdir -p "$cfg/silere-shell"
printf '{"__version":1}\n' > "$cfg/silere-shell/settings.json"

printf 'sweeping the settings schema against %s live surfaces\n' "$count"
XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_RUNTIME_DIR="$runtime" \
    SILERE_PROBE_ROOT="$ROOT" SILERE_PROBE_LIST="$list" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    qs -p "$probe_project/probe-mutate.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-MUTATE' 400 0.5 || true

if ! grep -q 'PROBE-MUTATE' "$log" 2>/dev/null; then
    cat "$log" >&2
    echo "FAIL: mutation sweep did not finish" >&2
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
    echo "FAIL: a live settings change broke a surface" >&2
    exit 1
fi

grep -oE 'PROBE-MUTATE swept .*' "$log" | tail -1 | sed 's/^/  /'
echo "mutation sweep passed"
