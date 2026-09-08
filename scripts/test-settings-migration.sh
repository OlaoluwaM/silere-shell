#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source scripts/probe-lib.sh
_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/ssm.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    # Only this probe's private source snapshot and XDG fixtures live here.
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

fail() { cat "$log" >&2; echo "FAIL: $*" >&2; exit 1; }
ipc() { qs ipc -p "$project/probe-settings-migration.qml" call -- migrationProbe "$@"; }
wait_ready() {
    local i state
    for ((i=0; i<100; i++)); do
        state="$(ipc status 2>/dev/null || true)"
        if [[ "$state" == *'"ready":true'* ]]; then return 0; fi
        sleep 0.05
    done
    fail "settings did not become ready: $state"
}

for scenario in blocked locked current future replaced; do
    case_root="$probe_root/$scenario"
    project="$case_root/project"
    export XDG_CONFIG_HOME="$case_root/config-home" XDG_STATE_HOME="$case_root/state-home"
    export XDG_RUNTIME_DIR="$case_root/r" QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1
    directory="$XDG_CONFIG_HOME/silere-shell"
    settings="$directory/settings.json"
    backup="$directory/settings.v0.bak.json"
    log="$case_root/probe.log"
    mkdir -p "$project" "$directory" "$XDG_RUNTIME_DIR" "$XDG_STATE_HOME"
    chmod 0700 "$XDG_RUNTIME_DIR"
    cp -a config services "$project/"
    cp scripts/probe-settings-migration.qml "$project/"
    original="$case_root/original.json"
    case "$scenario" in
        blocked|locked)
            printf '{"barHeight":40,"someUnknownKey":"keep","barWidgetOrderLeft":"clock"}\n' > "$original"
            mkdir "$backup"
            if [[ "$scenario" == locked ]]; then
                sed -i -E '/property bool +barWidgetOrderLocked:/s/false/true/' "$project/config/GeneratedDefaults.qml"
            fi
            ;;
        current|replaced) printf '{"__version":1,"barHeight":40,"unknown":"keep"}\n' > "$original" ;;
        future) printf '{"__version":999,"barHeight":40,"unknown":"keep"}\n' > "$original" ;;
    esac
    cp "$original" "$settings"
    qs -p "$project/probe-settings-migration.qml" --no-color > "$log" 2>&1 &
    probe_pid=$!
    wait_ready
    sleep 0.8
    cmp -s "$original" "$settings" || fail "$scenario startup overwrote the original settings"
    if [[ "$scenario" == blocked || "$scenario" == locked ]]; then
        state="$(ipc status)"
        [[ "$state" == *'Could not back up settings'* && "$state" == *'"height":40'* ]] \
            || fail "backup failure was not surfaced with loaded settings"
        ipc edit
        sleep 0.8
        cmp -s "$original" "$settings" || fail "$scenario setting changes bypassed backup failure"
        printf '\n' >> "$project/probe-settings-migration.qml"
        _probe_wait "$log" "$probe_pid" 'Reloading configuration' 100 0.05 || fail "reload did not run"
        wait_ready
        sleep 0.8
        cmp -s "$original" "$settings" || fail "$scenario reload overwrote the original settings"
        mv "$backup" "$case_root/backup-blocker"
        ipc retry
        sleep 0.8
        python3 - "$original" "$backup" "$settings" "$scenario" <<'PY'
import json, pathlib, sys
original, backup, settings = map(pathlib.Path, sys.argv[1:4])
assert json.loads(backup.read_text()) == json.loads(original.read_text()), 'backup must preserve all legacy keys'
assert backup.stat().st_mode & 0o777 == 0o600, 'backup mode must be 0600'
value = json.loads(settings.read_text())
assert value['__version'] == 1 and value['barHeight'] == 40, 'successful retry must migrate original settings'
if sys.argv[4] == 'locked':
    assert not any(key in value for key in ('barWidgetOrderLeft', 'barWidgetOrderCenter', 'barWidgetOrderRight')), 'locked order overrides must be scrubbed'
PY
    fi
    if [[ "$scenario" == current || "$scenario" == future ]]; then
        [[ ! -e "$backup" ]] || fail "$scenario unexpectedly attempted legacy backup"
    fi
    if [[ "$scenario" == replaced ]]; then
        ipc edit
        sleep 0.8
        python3 - "$settings" <<'PYREPLACE'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
value = json.loads(path.read_text())
del value['__version']
value['externalLegacyKey'] = 'keep in backup'
path.write_text(json.dumps(value))
PYREPLACE
        sleep 0.8
        python3 - "$settings" "$backup" <<'PYVERIFY'
import json, pathlib, sys
settings, backup = map(pathlib.Path, sys.argv[1:])
assert json.loads(settings.read_text())['__version'] == 1, 'external legacy file must replace stale saved-text cache'
assert json.loads(backup.read_text())['externalLegacyKey'] == 'keep in backup'
PYVERIFY
    fi
    [[ -z "$(_probe_errors "$log")" ]] || fail "$scenario logged a runtime error"
    _probe_stop "$probe_pid"
    probe_pid=""
    echo "PROBE-SETTINGS-MIGRATION $scenario passed"
done
