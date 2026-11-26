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

mkdir -p "$probe_root/config/silere-shell" "$probe_root/runtime" "$probe_root/project" "$probe_root/bin" \
    "$probe_root/zoneinfo"
chmod 0700 "$probe_root/runtime"
printf '{"__version":1}\n' > "$probe_root/config/silere-shell/settings.json"
_probe_project "$ROOT" scripts/probe-nightlight.qml "$probe_root/project"
# the probe idles and wakes the session, which the real singleton takes from the compositor
rm "$probe_root/project/services"
cp -a "$ROOT/services" "$probe_root/project/services"
cp "$ROOT/scripts/fixtures/coordinator/Idle.qml" "$probe_root/project/services/Idle.qml"

# The service starts and stops the real unit and drives the real daemon, so every command it
# can reach is a stand-in here. The probe steers them through files it writes: unit-state
# (active or inactive), toggle-mode (ok, fail, hang, or slow for a start that answers late),
# slow-check, slow-get and slow-set, the seconds a check or a config read or write takes,
# get-mode and set-mode (ok, fail, or garbage for get), sunsetr.conf, the config as
# field=value lines holding only what the probe gives it, status-initial and status-feed, the
# state a follow prints on connecting and the lines it prints after, status-down, which makes
# a follow answer as if no daemon ran while it holds 1, and tz-zone and slow-tz for the zone lookup.
printf 'active\n' > "$probe_root/unit-state"
printf 'ok\n' > "$probe_root/toggle-mode"
printf '%s\n' transition_mode=geo night_temp=3300 sunset=19:00:00 sunrise=06:00:00 \
    latitude=41.9 longitude=-87.7 > "$probe_root/sunsetr.conf"
cat > "$probe_root/bin/systemctl" <<EOF2
#!/usr/bin/env bash
state="$probe_root/unit-state"
case "\$*" in
    "--user is-active --quiet sunsetr.service")
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
    "--user start sunsetr.service"|"--user stop sunsetr.service")
        printf '%s\\n' "\$2" >> "$probe_root/systemctl-calls"
        # a start that hangs past the service's deadline is cut off there
        [ "\$(cat "$probe_root/toggle-mode")" = hang ] && exec sleep 7
        # one that answers late, but inside the deadline
        [ "\$(cat "$probe_root/toggle-mode")" = slow ] && sleep 2.5
        if [ "\$(cat "$probe_root/toggle-mode")" = fail ]; then
            echo "Job for sunsetr.service failed: probe" >&2
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
# sunsetr status --json --follow prints status-initial, then each line added to status-feed,
# until status-exit appears; while status-down holds 1 it prints the real tool's two plain lines and
# exits at once. get answers the way the real one does: `get all --json` prints every field
# sunsetr.conf holds as one JSON object of strings, coordinates rounded to one decimal, and
# named fields fail when one is absent. It reads the file before its delay and records any
# call made while a set runs. set records its arguments, any call that starts while another
# is still running, and its arguments again once it has answered
cat > "$probe_root/bin/sunsetr" <<EOF2
#!/usr/bin/env bash
r="$probe_root"
case "\${1:-}" in
    status)
        if [ "\$*" != "status --json --follow" ]; then
            printf '%s\\n' "\$*" >> "\$r/sunsetr-other"
            exit 1
        fi
        printf 'run\\n' >> "\$r/status-runs"
        if [ "\$(cat "\$r/status-down" 2>/dev/null || true)" = 1 ]; then
            echo '[ERROR] No sunsetr process is running'
            echo 'Start sunsetr first, then run this command again'
            exit 0
        fi
        [ -e "\$r/status-initial" ] && cat "\$r/status-initial"
        seen=0
        [ -e "\$r/status-feed" ] && seen="\$(wc -l < "\$r/status-feed")"
        while :; do
            if [ -e "\$r/status-exit" ]; then
                rm -f "\$r/status-exit"
                exit 0
            fi
            total=0
            [ -e "\$r/status-feed" ] && total="\$(wc -l < "\$r/status-feed")"
            if [ "\$total" -gt "\$seen" ]; then
                sed -n "\$((seen + 1)),\${total}p" "\$r/status-feed"
                seen="\$total"
            fi
            sleep 0.05
        done
        ;;
    get)
        shift
        printf '%s\\n' "\$*" >> "\$r/get-calls"
        [ -d "\$r/set-lock" ] && printf '%s\\n' "\$*" >> "\$r/get-during-set"
        conf="\$(cat "\$r/sunsetr.conf")"
        [ -e "\$r/slow-get" ] && sleep "\$(cat "\$r/slow-get")"
        mode="\$(cat "\$r/get-mode" 2>/dev/null || true)"
        if [ "\$mode" = fail ]; then
            echo '[ERROR] probe'
            exit 1
        fi
        if [ "\$mode" = garbage ]; then
            echo 'sunsetr probe: not json'
            exit 0
        fi
        fields=()
        for f in "\$@"; do
            case "\$f" in --json|-j) ;; *) fields+=("\$f") ;; esac
        done
        if [ "\${fields[*]}" = all ]; then
            mapfile -t fields < <(printf '%s\\n' "\$conf" | cut -d= -f1 | sort)
        fi
        out='{'
        sep=''
        for f in "\${fields[@]}"; do
            if ! printf '%s\\n' "\$conf" | grep -q "^\$f="; then
                printf '{"error":"Unknown field: %s","type":"ConfigError"}\\n' "\$f"
                exit 1
            fi
            v="\$(printf '%s\\n' "\$conf" | grep -m1 "^\$f=" | cut -d= -f2-)"
            case "\$f" in latitude|longitude) v="\$(printf '%.1f' "\$v")" ;; esac
            out="\$out\$sep\"\$f\":\"\$v\""
            sep=','
        done
        printf '%s}\\n' "\$out"
        ;;
    set)
        shift
        mkdir "\$r/set-lock" 2>/dev/null || printf '%s\\n' "\$*" >> "\$r/set-overlap"
        printf '%s\\n' "\$*" >> "\$r/set-calls"
        delay=0.1
        [ -e "\$r/slow-set" ] && delay="\$(cat "\$r/slow-set")"
        sleep "\$delay"
        if [ "\$(cat "\$r/set-mode" 2>/dev/null || true)" = fail ]; then
            rmdir "\$r/set-lock" 2>/dev/null || true
            echo '[ERROR] probe'
            exit 1
        fi
        for kv in "\$@"; do
            grep -v "^\${kv%%=*}=" "\$r/sunsetr.conf" > "\$r/sunsetr.conf.new" || true
            printf '%s\\n' "\$kv" >> "\$r/sunsetr.conf.new"
            mv "\$r/sunsetr.conf.new" "\$r/sunsetr.conf"
        done
        rmdir "\$r/set-lock" 2>/dev/null || true
        printf '%s\\n' "\$*" >> "\$r/set-done"
        ;;
    *)
        printf '%s\\n' "\$*" >> "\$r/sunsetr-other"
        exit 1
        ;;
esac
EOF2
# sunsetr owns the display's colour, and a push from the shell would fight its fades, so
# any call to hyprctl fails the run
cat > "$probe_root/bin/hyprctl" <<EOF2
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$probe_root/hyprctl-calls"
exit 1
EOF2
# the location lookup reads the zone from timedatectl and its coordinates from TZDIR, so a
# timezone switch writes the same place on every machine. The zone is read before the delay,
# so a slow lookup answers for the zone it started on
printf 'Europe/Riga\n' > "$probe_root/tz-zone"
cat > "$probe_root/bin/timedatectl" <<EOF2
#!/usr/bin/env bash
[ "\$*" = "show -p Timezone --value" ] || exit 1
zone="\$(cat "$probe_root/tz-zone")"
[ -e "$probe_root/slow-tz" ] && sleep "\$(cat "$probe_root/slow-tz")"
printf '%s\\n' "\$zone"
EOF2
printf 'LV\t+5657+02406\tEurope/Riga\nUS\t+415100-0873900\tAmerica/Chicago\n' > "$probe_root/zoneinfo/zone1970.tab"
chmod +x "$probe_root/bin/systemctl" "$probe_root/bin/sunsetr" "$probe_root/bin/hyprctl" \
    "$probe_root/bin/timedatectl"

# the probe moves the stand-in sunsetr aside to make the tool scan lose it, so a PATH
# directory holding the host's own is replaced by links to everything else in it
probe_path="$probe_root/bin"
shadows=0
IFS=: read -ra path_dirs <<< "$PATH"
for dir in "${path_dirs[@]}"; do
    if [ -n "$dir" ] && [ -e "$dir/sunsetr" ]; then
        shadows=$((shadows + 1))
        mkdir "$probe_root/path-$shadows"
        for f in "$dir"/*; do
            [ "${f##*/}" = sunsetr ] || ln -s "$f" "$probe_root/path-$shadows/"
        done
        dir="$probe_root/path-$shadows"
    fi
    probe_path="$probe_path:$dir"
done

PATH="$probe_path" SILERE_NIGHTLIGHT_PROBE_ROOT="$probe_root" TZDIR="$probe_root/zoneinfo" \
    XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" XDG_CACHE_HOME="$probe_root/config/cache" \
    XDG_RUNTIME_DIR="$probe_root/runtime" HYPRLAND_INSTANCE_SIGNATURE="" NIRI_SOCKET="" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    QT_NO_XDG_DESKTOP_PORTAL=1 setsid qs -p "$probe_root/project/probe-nightlight.qml" --no-color >"$probe_root/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$probe_root/probe.log" "$probe_pid" 'PROBE-NIGHTLIGHT' 480 0.25 || true

errs="$(_probe_errors "$probe_root/probe.log")"
# a status line that throws in its handler shows only as the engine's own error line, which
# names the file as @services/NightLight.qml[line:column]
thrown="$(grep -E 'NightLight\.qml.*Error' "$probe_root/probe.log" || true)"
if ! grep -q 'PROBE-NIGHTLIGHT passed' "$probe_root/probe.log" \
        || grep -q 'PROBE-FAIL' "$probe_root/probe.log" || [ -n "$errs" ] || [ -n "$thrown" ]; then
    cat "$probe_root/probe.log" >&2
    echo 'FAIL: night light probe failed or logged a runtime error' >&2
    exit 1
fi
# the probe reads these logs too; a second reading here keeps a probe that skipped its
# steps from passing on nothing
calls="$(cat "$probe_root/systemctl-calls" 2>/dev/null || true)"
if ! grep -qx 'is-active' <<< "$calls" || ! grep -qx 'stop' <<< "$calls" \
        || [ "$(grep -cx 'start' <<< "$calls")" -ne 9 ] || [ "$(grep -cx 'stop' <<< "$calls")" -ne 7 ]; then
    printf '%s\n' "$calls" >&2
    echo 'FAIL: the stand-in systemctl did not see the checks, the seven stops and the nine starts' >&2
    exit 1
fi
if [ "$(grep -cx 'is-active 3.2' "$probe_root/systemctl-done" 2>/dev/null || true)" != 2 ]; then
    cat "$probe_root/systemctl-done" >&2 2>/dev/null || true
    echo 'FAIL: the stand-in systemctl did not answer both slow checks' >&2
    exit 1
fi
if [ -e "$probe_root/systemctl-other" ] || [ -e "$probe_root/sunsetr-other" ] || [ -e "$probe_root/hyprctl-calls" ]; then
    cat "$probe_root/systemctl-other" "$probe_root/sunsetr-other" "$probe_root/hyprctl-calls" 2>/dev/null >&2
    echo 'FAIL: a stand-in saw a call the probe does not expect' >&2
    exit 1
fi
if [ -e "$probe_root/set-overlap" ] || ! grep -qx 'night_temp=3200 sunset=18:30:00' "$probe_root/set-calls" \
        || grep -qx 'night_temp=3100' "$probe_root/set-calls" \
        || [ "$(grep -cE '^latitude=' "$probe_root/set-calls")" != 2 ] \
        || grep -qxE 'night_temp=4500|sunrise=05:00:00' "$probe_root/set-calls" \
        || [ -e "$probe_root/get-during-set" ] || grep -vqx 'all --json' "$probe_root/get-calls" \
        || [ "$(grep -x -A1 'night_temp=4200' "$probe_root/set-done" | paste -sd,)" \
            != 'night_temp=4200,night_temp=4300' ]; then
    cat "$probe_root/set-calls" "$probe_root/set-done" "$probe_root/set-overlap" \
        "$probe_root/get-calls" "$probe_root/get-during-set" 2>/dev/null >&2
    echo 'FAIL: the stand-in sunsetr saw overlapping, missing or unexpected writes, or a read other than get all' >&2
    exit 1
fi
grep -oE 'PROBE-NIGHTLIGHT passed [0-9]+ checks' "$probe_root/probe.log" | tail -1
