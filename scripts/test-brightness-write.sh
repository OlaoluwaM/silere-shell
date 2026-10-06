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

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-brightness-write.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$probe_root/config/silere-shell" "$probe_root/runtime" "$probe_root/project" "$probe_root/bin"
chmod 0700 "$probe_root/runtime"
printf '{"__version":1}\n' > "$probe_root/config/silere-shell/settings.json"
_probe_project "$ROOT" scripts/probe-brightness-write.qml "$probe_root/project"

# brightnessctl -d DEVICE set VALUE -q: each write is held until the probe releases its
# display, so the display switch provably precedes the stale result. The paths are written in
cat > "$probe_root/bin/brightnessctl" <<EOF2
#!/usr/bin/env bash
case "\${3:-}" in
    set)
        printf '%s\\n' "\$2" >> "$probe_root/set-calls"
        for _ in \$(seq 1 200); do
            [ -e "$probe_root/release-\$2" ] && break
            sleep 0.05
        done
        echo "Permission denied" >&2
        exit 1
        ;;
    *) exit 1 ;;
esac
EOF2
chmod +x "$probe_root/bin/brightnessctl"
# only the first display's write is held; the second reports as soon as it runs
touch "$probe_root/release-probe-b"

PATH="$probe_root/bin:$PATH" SILERE_BRIGHTNESS_PROBE_ROOT="$probe_root" \
    XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" XDG_CACHE_HOME="$probe_root/config/cache" \
    XDG_RUNTIME_DIR="$probe_root/runtime" QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    QT_NO_XDG_DESKTOP_PORTAL=1 setsid qs -p "$probe_root/project/probe-brightness-write.qml" --no-color >"$probe_root/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$probe_root/probe.log" "$probe_pid" 'PROBE-BRIGHTNESS-WRITE' 60 0.25 || true

errs="$(_probe_errors "$probe_root/probe.log")"
if ! grep -q 'PROBE-BRIGHTNESS-WRITE passed' "$probe_root/probe.log" \
        || grep -q 'PROBE-FAIL' "$probe_root/probe.log" || [ -n "$errs" ]; then
    cat "$probe_root/probe.log" >&2
    echo 'FAIL: brightness write probe failed or logged a runtime error' >&2
    exit 1
fi
# both writes must have reached the stand-in, or the checks above passed on nothing
if [ "$(cat "$probe_root/set-calls" 2>/dev/null)" != $'probe-a\nprobe-b' ]; then
    cat "$probe_root/probe.log" "$probe_root/set-calls" 2>/dev/null >&2
    echo 'FAIL: the stand-in brightnessctl did not see one write per display' >&2
    exit 1
fi
echo "PROBE-BRIGHTNESS-WRITE passed"
