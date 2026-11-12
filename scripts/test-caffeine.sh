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
# directory already made behind
probe_root=""
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    [ -z "$probe_root" ] || rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-caffeine.XXXXXX")"
mkdir -p "$probe_root/config/silere-shell" "$probe_root/runtime" "$probe_root/project" "$probe_root/bin"
chmod 0700 "$probe_root/runtime"
# the checked-in defaults name no unit, which leaves caffeine unavailable
printf '{"__version":1,"caffeineUnit":"hypr-shell-caffeine.service"}\n' \
    > "$probe_root/config/silere-shell/settings.json"
_probe_project "$ROOT" scripts/probe-caffeine.qml "$probe_root/project"
# the probe holds the session idle to keep the drift and inhibitor polls out of its call
# counts, which the real singleton would take from the compositor. With a run on the drift
# poll stays up, but its first tick is a minute out and no step holds a run that long
rm "$probe_root/project/services"
cp -a "$ROOT/services" "$probe_root/project/services"
cp "$ROOT/scripts/fixtures/coordinator/Idle.qml" "$probe_root/project/services/Idle.qml"

# The service starts and stops the real unit and reads the real inhibitor list, so every
# command it can reach is a stand-in here. The probe steers them through files it writes:
# unit-state (active or inactive), toggle-mode (ok or fail), inhibitors (the list
# systemd-inhibit prints), and slow-check and slow-inhibit, the seconds each read takes.
printf 'inactive\n' > "$probe_root/unit-state"
printf 'ok\n' > "$probe_root/toggle-mode"
: > "$probe_root/inhibitors"
cat > "$probe_root/bin/systemctl" <<EOF2
#!/usr/bin/env bash
state="$probe_root/unit-state"
case "\$*" in
    "--user is-active --quiet hypr-shell-caffeine.service")
        printf 'is-active\\n' >> "$probe_root/systemctl-calls"
        # read before the delay, so a slow check answers for the state it started on
        current="\$(cat "\$state")"
        delay=0
        [ -e "$probe_root/slow-check" ] && delay="\$(cat "$probe_root/slow-check")"
        # the deadline's TERM can reach the sleep before this shell, which would then
        # carry on; a real systemctl dies with it, so a cut-off check never gets here
        sleep "\$delay" || exit 143
        printf 'is-active %s\\n' "\$delay" >> "$probe_root/systemctl-done"
        [ "\$current" = active ]
        ;;
    "--user start hypr-shell-caffeine.service"|"--user stop hypr-shell-caffeine.service")
        printf '%s\\n' "\$2" >> "$probe_root/systemctl-calls"
        if [ "\$(cat "$probe_root/toggle-mode")" = fail ]; then
            echo "Job for hypr-shell-caffeine.service failed: probe" >&2
            exit 1
        fi
        if [ "\$2" = start ]; then printf 'active\\n' > "\$state"; else printf 'inactive\\n' > "\$state"; fi
        ;;
    # no preset is timed here, so there is never a stop timer to clear or list
    "--user stop hypr-shell-caffeine-stop.timer")
        exit 5
        ;;
    "--user list-timers hypr-shell-caffeine-stop.timer --no-legend")
        ;;
    *)
        printf '%s\\n' "\$*" >> "$probe_root/systemctl-other"
        exit 1
        ;;
esac
EOF2
cat > "$probe_root/bin/systemd-inhibit" <<EOF2
#!/usr/bin/env bash
if [ "\$*" != "--list --no-legend --mode=block" ]; then
    printf '%s\\n' "\$*" >> "$probe_root/inhibit-other"
    exit 1
fi
# read before the delay, so a slow read answers for the list it started on
list="\$(cat "$probe_root/inhibitors")"
delay=0
[ -e "$probe_root/slow-inhibit" ] && delay="\$(cat "$probe_root/slow-inhibit")"
# as the systemctl stand-in: a read cut off at its deadline stops here
sleep "\$delay" || exit 143
printf 'list %s\\n' "\$delay" >> "$probe_root/inhibit-done"
[ -z "\$list" ] || printf '%s\\n' "\$list"
EOF2
# a timed preset is never picked, so a scheduled stop is never asked for
cat > "$probe_root/bin/systemd-run" <<EOF2
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$probe_root/systemd-run-calls"
exit 1
EOF2
# stands in for the system bus: one changed-inhibitor line each time the probe rewrites
# bus-signal, and nothing otherwise. It ends with the run's directory, so a watcher the
# probe's exit left behind cannot outlive the cleanup
cat > "$probe_root/bin/dbus-monitor" <<EOF2
#!/usr/bin/env bash
last=""
while [ -d "$probe_root" ]; do
    current="\$(cat "$probe_root/bus-signal" 2>/dev/null || true)"
    if [ "\$current" != "\$last" ]; then
        last="\$current"
        printf '         string "BlockInhibited"\\n'
    fi
    sleep 0.1
done
EOF2
chmod +x "$probe_root/bin/systemctl" "$probe_root/bin/systemd-inhibit" \
    "$probe_root/bin/systemd-run" "$probe_root/bin/dbus-monitor"

PATH="$probe_root/bin:$PATH" SILERE_CAFFEINE_PROBE_ROOT="$probe_root" \
    XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" XDG_CACHE_HOME="$probe_root/config/cache" \
    XDG_RUNTIME_DIR="$probe_root/runtime" HYPRLAND_INSTANCE_SIGNATURE="" NIRI_SOCKET="" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    QT_NO_XDG_DESKTOP_PORTAL=1 setsid qs -p "$probe_root/project/probe-caffeine.qml" --no-color >"$probe_root/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$probe_root/probe.log" "$probe_pid" 'PROBE-CAFFEINE' 320 0.25 || true

errs="$(_probe_errors "$probe_root/probe.log")"
if ! grep -q 'PROBE-CAFFEINE passed' "$probe_root/probe.log" \
        || grep -q 'PROBE-FAIL' "$probe_root/probe.log" || [ -n "$errs" ]; then
    cat "$probe_root/probe.log" >&2
    echo 'FAIL: caffeine probe failed or logged a runtime error' >&2
    exit 1
fi
# the probe reads these logs too; a second reading here keeps a probe that skipped its
# steps from passing on nothing
if [ "$(grep -cx 'is-active 3.2' "$probe_root/systemctl-done" 2>/dev/null || true)" != 2 ] \
        || [ "$(grep -cx 'list 3.2' "$probe_root/inhibit-done" 2>/dev/null || true)" != 2 ]; then
    cat "$probe_root/systemctl-done" "$probe_root/inhibit-done" >&2 2>/dev/null || true
    echo 'FAIL: the stand-ins did not answer both slow checks and both slow inhibitor reads' >&2
    exit 1
fi
for stray in systemctl-other inhibit-other systemd-run-calls; do
    if [ -e "$probe_root/$stray" ]; then
        cat "$probe_root/$stray" >&2
        echo "FAIL: a stand-in saw a call the probe does not expect ($stray)" >&2
        exit 1
    fi
done
grep -oE 'PROBE-CAFFEINE passed [0-9]+ checks' "$probe_root/probe.log" | tail -1
