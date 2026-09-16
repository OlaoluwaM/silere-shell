#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--private-bus" ]]; then
    exec dbus-run-session -- bash "$0" --private-bus
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-notification-disk.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$probe_root/config-home/silere-shell" "$probe_root/runtime" "$probe_root/project"
chmod 0700 "$probe_root/runtime"
cp "$ROOT/scripts/probe-notification-disk.qml" "$probe_root/project/"
cp -a "$ROOT/services" "$probe_root/project/"
ln -s "$ROOT/config" "$probe_root/project/config"
ln -s "$ROOT/modules" "$probe_root/project/modules"
# Hold the real file-load callback in these cases so deletes can precede the
# first merge without depending on machine-specific disk timing.
python3 - "$probe_root/project/services/Notifications.qml" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
source = path.read_text()
needle = '            root._diskReadable = true\n'
assert source.count(needle) == 1, 'notification load seam changed'
source = source.replace(needle, needle +
    '            if (String(Quickshell.env("SILERE_NOTIFICATION_DISK_PHASE")).startsWith("delayed-")) return\n')
path.write_text(source)
PY

settings() {
    printf '{"__version":1,"notifHistoryLimit":%s,"notifHistoryPersistent":%s}\n' "$1" "$2" \
        > "$probe_root/config-home/silere-shell/settings.json"
}

run_phase() {
    local phase="$1"
    local log="$probe_root/$phase.log"
    SILERE_NOTIFICATION_DISK_PHASE="$phase" \
        XDG_CONFIG_HOME="$probe_root/config-home" XDG_STATE_HOME="$probe_root/state-home" \
        XDG_RUNTIME_DIR="$probe_root/runtime" QT_FORCE_STDERR_LOGGING=1 \
        QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 \
        qs -p "$probe_root/project/probe-notification-disk.qml" --no-color >"$log" 2>&1 &
    probe_pid=$!
    _probe_wait "$log" "$probe_pid" 'PROBE-DISK-DONE' 100 0.1 || true
    if ! grep -q "PROBE-DISK $phase passed" "$log" || grep -q 'PROBE-FAIL' "$log" \
            || [[ -n "$(_probe_errors "$log")" ]]; then
        cat "$log" >&2
        echo "FAIL: notification disk probe ($phase)" >&2
        exit 1
    fi
    grep -oE "PROBE-DISK $phase passed [0-9]+ checks" "$log" | tail -1
    _probe_stop "$probe_pid"
    probe_pid=""
}

settings 100 true
run_phase seed

history="$probe_root/config-home/silere-shell/notifications.json"
[[ -f "$history" ]] || { echo "FAIL: seed did not create notifications.json" >&2; exit 1; }
[[ "$(stat -c %a "$history")" == "600" ]] \
    || { echo "FAIL: notifications.json permissions are not 600" >&2; exit 1; }

settings 5 true
run_phase restore

settings 5 false
run_phase off
grep -q '"history":\[\]' "$history" \
    || { echo "FAIL: persistence-off did not queue an empty disk history" >&2; exit 1; }

settings 5 true
run_phase late
run_phase settings-order
run_phase clear-reload
grep -q '"history":\[\]' "$history" \
    || { echo "FAIL: reload restored cleared disk history" >&2; exit 1; }
run_phase live-markers

for phase in delayed-row delayed-run delayed-clear; do
    printf '{"__version":1,"history":[{"id":11,"summary":"old one","time":1100},{"id":12,"summary":"old two","time":1200},{"id":13,"summary":"old three","time":1300}]}\n' > "$history"
    run_phase "$phase"
    python3 - "$history" "$phase" <<'PY'
import json
import sys

with open(sys.argv[1]) as source:
    ids = sorted(row['id'] for row in json.load(source)['history'])
expected = [] if sys.argv[2] == 'delayed-clear' else [11, 12, 13, 90]
assert ids == expected, f'{sys.argv[2]} persisted {ids}, expected {expected}'
PY
done

printf '{"__version":2,"unknown":{"preserve":true},"history":[{"id":1,"summary":"future","time":1001,"unknown":"keep"}],"seen":{"1":true},"times":{"1":1001}}\n' > "$history"
cp "$history" "$history.expected"
settings 5 true
run_phase future
cmp -s "$history" "$history.expected" \
    || { echo "FAIL: future notifications.json was overwritten" >&2; exit 1; }
settings 5 false
run_phase future-off
cmp -s "$history" "$history.expected" \
    || { echo "FAIL: persistence-off overwrote future notifications.json" >&2; exit 1; }
settings 5 true

printf '{not json\n' > "$history"
cp "$history" "$history.expected"
run_phase guard
cmp -s "$history" "$history.expected" \
    || { echo "FAIL: malformed notifications.json was overwritten" >&2; exit 1; }

calendar="$probe_root/config-home/silere-shell/calendar-marks.json"
printf '{"__version":2,"marks":["2026-1-1"]}' > "$calendar"
cp "$calendar" "$calendar.expected"
run_phase calendar
cmp -s "$calendar" "$calendar.expected" \
    || { echo "FAIL: future calendar-marks.json was overwritten" >&2; exit 1; }

printf '{"__version":1,"history":[],"seen":{},"times":{}}\n' > "$history"
settings 5 true
run_phase retry
[[ "$(stat -c %a "$history")" == "600" ]] \
    || { echo "FAIL: retry did not restore notifications.json permissions" >&2; exit 1; }
