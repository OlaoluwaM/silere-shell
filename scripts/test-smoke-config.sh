#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/scripts/lib/smoke-config.sh"

test_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-smoke-config.XXXXXX")"
trap 'rm -rf "$test_root"' EXIT INT TERM

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

probe_calls=0
probe_log=""
probe_env=""
_run_shell_probe() {
    probe_calls=$((probe_calls + 1))
    [ "$#" -eq 2 ] || return 1
    probe_log="$1"
    probe_env="$2"
}

source_home="$test_root/source home"
private_home="$test_root/private home"
external="$test_root/external"
mkdir -p "$source_home/silere-shell" "$external"
printf '{"barHeight":40}\n' > "$source_home/silere-shell/settings.json"
printf '["2026-09-16"]\n' > "$source_home/silere-shell/calendar-marks.json"
printf 'notification bytes\n' > "$source_home/silere-shell/notifications.json"
printf 'settings backup bytes\n' > "$source_home/silere-shell/settings.json.bak"
printf 'linked bytes\n' > "$external/linked.json"
ln -s "$external/linked.json" "$source_home/silere-shell/linked.json"

_silere_prepare_smoke_config "$source_home" "$private_home" \
    || fail "fixture configuration was not copied"
cmp "$source_home/silere-shell/settings.json" "$private_home/silere-shell/settings.json" \
    || fail "settings bytes changed during copy"
cmp "$source_home/silere-shell/calendar-marks.json" "$private_home/silere-shell/calendar-marks.json" \
    || fail "calendar marks bytes changed during copy"
cmp "$source_home/silere-shell/notifications.json" "$private_home/silere-shell/notifications.json" \
    || fail "notification state bytes changed during copy"
cmp "$source_home/silere-shell/settings.json.bak" "$private_home/silere-shell/settings.json.bak" \
    || fail "settings backup bytes changed during copy"
cmp "$external/linked.json" "$private_home/silere-shell/linked.json" \
    || fail "symlink target bytes were not copied"
find "$private_home/silere-shell" -type l -print -quit | grep -q . \
    && fail "private configuration retains a symlink"
printf 'private write\n' > "$private_home/silere-shell/linked.json"
cmp "$external/linked.json" "$private_home/silere-shell/linked.json" >/dev/null \
    && fail "private write reached the symlink source"

linked_home="$test_root/linked source"
linked_private="$test_root/linked private"
mkdir -p "$linked_home"
ln -s "$source_home/silere-shell" "$linked_home/silere-shell"
_silere_prepare_smoke_config "$linked_home" "$linked_private" \
    || fail "symlinked configuration directory was not copied"
[ ! -L "$linked_private/silere-shell" ] \
    || fail "private root retains the configuration directory symlink"

probe_private="$test_root/probe private"
_silere_run_smoke_probe "$source_home" "$probe_private" "$test_root/probe.log" \
    || fail "prepared configuration did not launch the probe"
[ "$SILERE_SMOKE_CONFIG_READY" -eq 1 ] \
    || fail "successful preparation did not mark the configuration ready"
[ "$probe_calls" -eq 1 ] \
    || fail "prepared configuration did not invoke the probe once"
[ "$probe_log" = "$test_root/probe.log" ] \
    || fail "probe did not receive its log path"
[ "$probe_env" = "XDG_CONFIG_HOME=$probe_private" ] \
    || fail "probe did not receive the private XDG configuration home"

missing_home="$test_root/missing source"
missing_private="$test_root/missing private"
_silere_prepare_smoke_config "$missing_home" "$missing_private" \
    || fail "missing configuration should create an empty private root"
[ -d "$missing_private/silere-shell" ] \
    || fail "missing configuration did not create the private root"
[ -z "$(find "$missing_private/silere-shell" -mindepth 1 -print -quit)" ] \
    || fail "missing configuration did not leave an empty private root"

invalid_home="$test_root/invalid source"
mkdir -p "$invalid_home"
printf 'not a directory\n' > "$invalid_home/silere-shell"
if _silere_prepare_smoke_config "$invalid_home" "$test_root/invalid private"; then
    fail "invalid source was accepted"
fi

blocked_private="$test_root/blocked private"
printf 'not a directory\n' > "$blocked_private"
if _silere_prepare_smoke_config "$source_home" "$blocked_private"; then
    fail "copy failure was accepted"
fi

broken_home="$test_root/broken source"
mkdir -p "$broken_home/silere-shell"
ln -s "$broken_home/missing.json" "$broken_home/silere-shell/broken.json"
probe_calls=0
if _silere_run_smoke_probe "$broken_home" "$test_root/broken private" "$test_root/broken.log"; then
    fail "broken symlink copy was accepted"
fi
[ "$SILERE_SMOKE_CONFIG_READY" -eq 0 ] \
    || fail "failed copy marked the configuration ready"
[ "$probe_calls" -eq 0 ] \
    || fail "failed copy invoked the probe"

_silere_cleanup_smoke_config "$private_home"
[ ! -e "$private_home" ] || fail "private configuration cleanup failed"

interrupted_private="$test_root/interrupted private"
if (
    smoke_home="$interrupted_private"
    _smoke_cleanup() { _silere_cleanup_smoke_config "$smoke_home"; }
    trap 'exit 130' INT TERM
    trap _smoke_cleanup EXIT
    mkdir -p "$smoke_home/silere-shell"
    kill -TERM "$BASHPID"
); then
    fail "interrupted smoke cleanup returned success"
fi
[ ! -e "$interrupted_private" ] || fail "interrupted smoke cleanup failed"

printf 'smoke configuration isolation passed\n'
