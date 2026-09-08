#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-config-recovery.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    # This exact mktemp-owned tree contains only this probe's private XDG fixture.
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

config_home="$probe_root/config-home"
runtime="$probe_root/runtime"
state_home="$probe_root/state-home"
project="$probe_root/project"
log="$probe_root/probe.log"
settings_dir="$config_home/silere-shell"
first_dir="$config_home/silere-shell.first"
payload_file="$settings_dir/settings.json"
first_payload='{"payload":"first"}'
second_payload='{"payload":"second"}'

mkdir -p "$config_home" "$runtime" "$state_home" "$project"
chmod 0700 "$runtime"
printf 'blocking regular file\n' > "$settings_dir"
_probe_project "$ROOT" scripts/probe-config-recovery.qml "$project"

XDG_CONFIG_HOME="$config_home" XDG_STATE_HOME="$state_home" \
    XDG_RUNTIME_DIR="$runtime" QT_FORCE_STDERR_LOGGING=1 \
    QT_QPA_PLATFORM=offscreen QT_NO_XDG_DESKTOP_PORTAL=1 \
    qs -p "$project/probe-config-recovery.qml" --no-color >"$log" 2>&1 &
probe_pid=$!

_probe_wait "$log" "$probe_pid" 'PROBE-CONFIG-BLOCKED' 100 0.05 || true
if ! grep -q 'PROBE-CONFIG-BLOCKED' "$log"; then
    cat "$log" >&2
    echo "FAIL: blocked configuration path was not observed" >&2
    exit 1
fi
if [ -e "$payload_file" ]; then
    echo "FAIL: queued payload appeared before the blocker was removed" >&2
    exit 1
fi

mv "$settings_dir" "$probe_root/startup-blocker"
_probe_wait "$log" "$probe_pid" 'PROBE-CONFIG-FIRST-SAVED' 160 0.1 || true
if ! grep -q 'PROBE-CONFIG-FIRST-SAVED' "$log"; then
    cat "$log" >&2
    echo "FAIL: startup-blocked write did not recover" >&2
    exit 1
fi

expected_first="$probe_root/expected-first"
printf '%s\n' "$first_payload" > "$expected_first"
if ! cmp -s "$expected_first" "$payload_file"; then
    echo "FAIL: first recovered file does not contain the exact payload" >&2
    exit 1
fi

wait_for_modes() {
    local directory="$1"
    local file="$2"
    local ticks=0
    while [ "$ticks" -lt 100 ]; do
        if [ "$(stat -c '%a' "$directory" 2>/dev/null || true)" = "700" ] \
                && [ "$(stat -c '%a' "$file" 2>/dev/null || true)" = "600" ]; then
            return 0
        fi
        sleep 0.05
        ticks=$((ticks + 1))
    done
    return 1
}

if ! wait_for_modes "$settings_dir" "$payload_file"; then
    printf 'FAIL: recovered directory/file permissions are %s/%s, expected 700/600\n' \
        "$(stat -c '%a' "$settings_dir" 2>/dev/null || echo missing)" \
        "$(stat -c '%a' "$payload_file" 2>/dev/null || echo missing)" >&2
    exit 1
fi

mv "$settings_dir" "$first_dir"
printf 'blocking replacement file\n' > "$settings_dir"
ipc_out="$(
    XDG_CONFIG_HOME="$config_home" XDG_STATE_HOME="$state_home" \
        XDG_RUNTIME_DIR="$runtime" QT_QPA_PLATFORM=offscreen \
        qs ipc -p "$project/probe-config-recovery.qml" \
        call configRecovery writeSecond 2>&1
)" || {
    printf '%s\n' "$ipc_out" >&2
    echo "FAIL: could not request the second probe write" >&2
    exit 1
}

_probe_wait "$log" "$probe_pid" 'PROBE-CONFIG-SECOND-WRITE-FAILED' 100 0.05 || true
if ! grep -q 'PROBE-CONFIG-SECOND-WRITE-FAILED' "$log"; then
    cat "$log" >&2
    echo "FAIL: replacement write did not fail against the blocking path" >&2
    exit 1
fi
mv "$settings_dir" "$probe_root/write-blocker"

_probe_wait "$log" "$probe_pid" 'PROBE-CONFIG-RECOVERY-DONE' 200 0.1 || true
if ! grep -q 'PROBE-CONFIG-SECOND-WRITE-FAILED' "$log" \
        || ! grep -q 'PROBE-CONFIG-SECOND-SAVED' "$log" \
        || ! grep -q 'PROBE-CONFIG-RECOVERY passed' "$log"; then
    cat "$log" >&2
    printf '  recovered-path: directory=%s file=%s mode=%s/%s\n' \
        "$([ -d "$settings_dir" ] && echo present || echo missing)" \
        "$([ -f "$payload_file" ] && echo present || echo missing)" \
        "$(stat -c '%a' "$settings_dir" 2>/dev/null || echo missing)" \
        "$(stat -c '%a' "$payload_file" 2>/dev/null || echo missing)" >&2
    echo "FAIL: post-write directory recovery did not complete" >&2
    exit 1
fi

expected_second="$probe_root/expected-second"
# PersistedFile alternates trailing whitespace so FileView retries the same text.
printf '%s\n\n' "$second_payload" > "$expected_second"
if ! cmp -s "$expected_second" "$payload_file"; then
    echo "FAIL: second recovered file does not contain the exact retry payload" >&2
    exit 1
fi
if ! cmp -s "$expected_first" "$first_dir/settings.json"; then
    echo "FAIL: recovery changed the stale file in the moved directory" >&2
    exit 1
fi
if ! wait_for_modes "$settings_dir" "$payload_file"; then
    printf 'FAIL: recreated directory/file permissions are %s/%s, expected 700/600\n' \
        "$(stat -c '%a' "$settings_dir" 2>/dev/null || echo missing)" \
        "$(stat -c '%a' "$payload_file" 2>/dev/null || echo missing)" >&2
    exit 1
fi

errs="$(_probe_errors "$log")"
if grep -q 'PROBE-FAIL' "$log" || [ -n "$errs" ]; then
    cat "$log" >&2
    [ -z "$errs" ] || printf '%s\n' "$errs" >&2
    echo "FAIL: configuration recovery probe logged an error" >&2
    exit 1
fi

grep -oE 'PROBE-CONFIG-RECOVERY passed [0-9]+ checks' "$log" | tail -1
