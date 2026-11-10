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

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-nightlight.XXXXXX")"
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
_probe_project "$ROOT" scripts/probe-nightlight.qml "$probe_root/project"

# The service starts and stops the real unit and pushes to the real display, so every
# command it can reach is a stand-in here. The probe steers them through files it writes:
# unit-state (active or inactive), toggle-mode (ok, fail or hang), and slow-check and
# slow-push, the seconds a check or a push takes.
printf 'active\n' > "$probe_root/unit-state"
printf 'ok\n' > "$probe_root/toggle-mode"
cat > "$probe_root/bin/systemctl" <<EOF2
#!/usr/bin/env bash
state="$probe_root/unit-state"
case "\$*" in
    "--user is-active --quiet hyprsunset.service")
        printf 'is-active\\n' >> "$probe_root/systemctl-calls"
        # read before the delay, so a slow check answers for the state it started on
        current="\$(cat "\$state")"
        delay=0
        [ -e "$probe_root/slow-check" ] && delay="\$(cat "$probe_root/slow-check")"
        sleep "\$delay"
        # a check cut off at its deadline never gets here
        printf 'is-active %s\\n' "\$delay" >> "$probe_root/systemctl-done"
        [ "\$current" = active ]
        ;;
    "--user start hyprsunset.service"|"--user stop hyprsunset.service")
        printf '%s\\n' "\$2" >> "$probe_root/systemctl-calls"
        # a start that hangs past the service's deadline is cut off there
        [ "\$(cat "$probe_root/toggle-mode")" = hang ] && exec sleep 7
        if [ "\$(cat "$probe_root/toggle-mode")" = fail ]; then
            echo "Job for hyprsunset.service failed: probe" >&2
            exit 1
        fi
        if [ "\$2" = start ]; then printf 'active\\n' > "\$state"; else printf 'inactive\\n' > "\$state"; fi
        ;;
    *)
        printf '%s\\n' "\$*" >> "$probe_root/systemctl-other"
        exit 1
        ;;
esac
EOF2
# hyprctl hyprsunset ...: logs its arguments, takes a fifth of a second the way a socket
# round trip can unless slow-push names longer, records any call that starts while another
# is still running, and logs its arguments again once it has answered
cat > "$probe_root/bin/hyprctl" <<EOF2
#!/usr/bin/env bash
if [ "\${1:-}" != hyprsunset ]; then
    printf '%s\\n' "\$*" >> "$probe_root/hyprctl-other"
    exit 1
fi
mkdir "$probe_root/hyprctl-lock" 2>/dev/null || printf '%s\\n' "\$*" >> "$probe_root/hyprctl-overlap"
printf '%s\\n' "\${*:2}" >> "$probe_root/hyprctl-calls"
if [ -e "$probe_root/slow-push" ]; then sleep "\$(cat "$probe_root/slow-push")"; else sleep 0.2; fi
rmdir "$probe_root/hyprctl-lock" 2>/dev/null || true
printf '%s\\n' "\${*:2}" >> "$probe_root/hyprctl-done"
echo ok
EOF2
printf '#!/usr/bin/env bash\nexit 0\n' > "$probe_root/bin/hyprsunset"
chmod +x "$probe_root/bin/systemctl" "$probe_root/bin/hyprctl" "$probe_root/bin/hyprsunset"

# the probe moves the stand-in hyprsunset aside to make the tool scan lose it, so a PATH
# directory holding the host's own is replaced by links to everything else in it
probe_path="$probe_root/bin"
shadows=0
IFS=: read -ra path_dirs <<< "$PATH"
for dir in "${path_dirs[@]}"; do
    if [ -n "$dir" ] && [ -e "$dir/hyprsunset" ]; then
        shadows=$((shadows + 1))
        mkdir "$probe_root/path-$shadows"
        for f in "$dir"/*; do
            [ "${f##*/}" = hyprsunset ] || ln -s "$f" "$probe_root/path-$shadows/"
        done
        dir="$probe_root/path-$shadows"
    fi
    probe_path="$probe_path:$dir"
done

PATH="$probe_path" SILERE_NIGHTLIGHT_PROBE_ROOT="$probe_root" \
    XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" XDG_CACHE_HOME="$probe_root/config/cache" \
    XDG_RUNTIME_DIR="$probe_root/runtime" HYPRLAND_INSTANCE_SIGNATURE="" NIRI_SOCKET="" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    QT_NO_XDG_DESKTOP_PORTAL=1 setsid qs -p "$probe_root/project/probe-nightlight.qml" --no-color >"$probe_root/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$probe_root/probe.log" "$probe_pid" 'PROBE-NIGHTLIGHT' 400 0.25 || true

errs="$(_probe_errors "$probe_root/probe.log")"
if ! grep -q 'PROBE-NIGHTLIGHT passed' "$probe_root/probe.log" \
        || grep -q 'PROBE-FAIL' "$probe_root/probe.log" || [ -n "$errs" ]; then
    cat "$probe_root/probe.log" >&2
    echo 'FAIL: night light probe failed or logged a runtime error' >&2
    exit 1
fi
# the probe reads these logs too; a second reading here keeps a probe that skipped its
# steps from passing on nothing
calls="$(cat "$probe_root/systemctl-calls" 2>/dev/null || true)"
if ! grep -qx 'is-active' <<< "$calls" || ! grep -qx 'stop' <<< "$calls" \
        || [ "$(grep -cx 'start' <<< "$calls")" -ne 7 ] || [ "$(grep -cx 'stop' <<< "$calls")" -ne 7 ]; then
    printf '%s\n' "$calls" >&2
    echo 'FAIL: the stand-in systemctl did not see the checks, the seven stops and the seven starts' >&2
    exit 1
fi
if [ "$(grep -cx 'is-active 3.2' "$probe_root/systemctl-done" 2>/dev/null || true)" != 2 ]; then
    cat "$probe_root/systemctl-done" >&2 2>/dev/null || true
    echo 'FAIL: the stand-in systemctl did not answer both slow checks' >&2
    exit 1
fi
if [ -e "$probe_root/systemctl-other" ]; then
    cat "$probe_root/systemctl-other" >&2
    echo 'FAIL: the stand-in systemctl saw a call the probe does not expect' >&2
    exit 1
fi
if [ -e "$probe_root/hyprctl-overlap" ] || ! grep -qx 'temperature 3700' "$probe_root/hyprctl-calls" \
        || grep -qxE 'temperature (4500|4600|4700)' "$probe_root/hyprctl-calls" \
        || [ "$(grep -x -A1 'temperature 4200' "$probe_root/hyprctl-calls" | paste -sd,)" \
            != 'temperature 4200,temperature 4300' ] \
        || [ "$(grep -x -A1 'temperature 4200' "$probe_root/hyprctl-done" | paste -sd,)" \
            != 'temperature 4200,temperature 4300' ] \
        || [ -e "$probe_root/hyprctl-other" ]; then
    cat "$probe_root/hyprctl-calls" "$probe_root/hyprctl-done" "$probe_root/hyprctl-overlap" \
        "$probe_root/hyprctl-other" 2>/dev/null >&2
    echo 'FAIL: the stand-in hyprctl saw overlapping, missing or unexpected pushes' >&2
    exit 1
fi
grep -oE 'PROBE-NIGHTLIGHT passed [0-9]+ checks' "$probe_root/probe.log" | tail -1
