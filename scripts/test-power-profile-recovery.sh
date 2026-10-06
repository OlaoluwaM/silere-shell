#!/usr/bin/env bash
set -euo pipefail

# a disposable shell registers the notification server; on the desktop bus it could claim the
# live daemon's name should that daemon drop out mid-run
if [[ "${1:-}" != "--private-bus" ]]; then
    exec dbus-run-session -- bash "$0" --private-bus "$@"
fi
shift

if [ "$#" -eq 0 ]; then
    bash "$0" --private-bus failure
    bash "$0" --private-bus empty-success
    exit 0
fi
case "$1" in
    failure) initial_status=1 ;;
    empty-success) initial_status=0 ;;
    *) echo 'expected failure or empty-success' >&2; exit 2 ;;
esac

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-power-recovery.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    # Generated probe data must also clean up when the trash directory is unusable.
    if command -v rip >/dev/null 2>&1 && rip -f "$probe_root" >/dev/null 2>&1; then
        return
    fi
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$probe_root/config/silere-shell" "$probe_root/runtime" "$probe_root/project" "$probe_root/bin"
chmod 0700 "$probe_root/runtime"
printf '{"__version":1}\n' > "$probe_root/config/silere-shell/settings.json"
_probe_project "$ROOT" scripts/probe-power-profile-recovery.qml "$probe_root/project"

cat > "$probe_root/bin/powerprofilesctl" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    list)
        if [ ! -f "$SILERE_POWER_PROBE_CALLS" ]; then
            printf 'list\n' > "$SILERE_POWER_PROBE_CALLS"
            # asusctl can return success with no profiles while asusd is unavailable.
            exit "$SILERE_POWER_PROBE_INITIAL_STATUS"
        fi
        printf 'list\n' >> "$SILERE_POWER_PROBE_CALLS"
        printf 'power-saver:\n* balanced:\nperformance:\n'
        ;;
    get) printf 'balanced\n' ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$probe_root/bin/powerprofilesctl"

PATH="$probe_root/bin:$PATH" SILERE_POWER_PROBE_CALLS="$probe_root/list-calls" \
    SILERE_POWER_PROBE_INITIAL_STATUS="$initial_status" \
    XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" XDG_CACHE_HOME="$probe_root/config/cache" \
    XDG_RUNTIME_DIR="$probe_root/runtime" QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    QT_NO_XDG_DESKTOP_PORTAL=1 setsid qs -p "$probe_root/project/probe-power-profile-recovery.qml" --no-color >"$probe_root/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$probe_root/probe.log" "$probe_pid" 'PROBE-POWER-RECOVERY' 40 0.25 || true

errs="$(_probe_errors "$probe_root/probe.log")"
if ! grep -q 'PROBE-POWER-RECOVERY passed' "$probe_root/probe.log" \
        || grep -q 'PROBE-FAIL' "$probe_root/probe.log" || [ -n "$errs" ]; then
    cat "$probe_root/probe.log" >&2
    echo 'FAIL: power profile recovery probe failed or logged a runtime error' >&2
    exit 1
fi
if [ "$(wc -l < "$probe_root/list-calls")" -ne 2 ]; then
    echo 'FAIL: a populated profile list was fetched again' >&2
    exit 1
fi
echo "PROBE-POWER-RECOVERY $1 passed"
