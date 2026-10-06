#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

command -v setsid >/dev/null 2>&1 || { printf 'SKIP: setsid unavailable; probe stop not tested\n'; exit 0; }
command -v pgrep >/dev/null 2>&1 || { printf 'SKIP: pgrep unavailable; probe stop not tested\n'; exit 0; }
command -v timeout >/dev/null 2>&1 || { printf 'SKIP: timeout unavailable; probe stop not tested\n'; exit 0; }
# busybox pgrep has no -g; 0 is the current group in procps
pgrep -g 0 >/dev/null 2>&1 || { printf 'SKIP: pgrep cannot list a process group; probe stop not tested\n'; exit 0; }

# kill -0 succeeds on a zombie, so a stopped leader its shell has not reaped yet would
# read as alive; the process is live only while /proc stat says it is not one
_pid_running() { # $1 = pid
    local line
    IFS= read -r line 2>/dev/null < "/proc/$1/stat" || return 1
    line=${line##*) }
    [ "${line%% *}" != Z ]
}

_group_live() { # $1 = pgid
    local p
    for p in $(pgrep -g "$1" 2>/dev/null || true); do
        _pid_running "$p" && return 0
    done
    return 1
}

# signals land asynchronously, so give a stopped process a moment to go before judging
_wait_gone() { # $1 = pid or -pgid
    local i
    for ((i = 0; i < 40; i++)); do
        if [ "${1#-}" = "$1" ]; then
            _pid_running "$1" || return 0
        else
            _group_live "${1#-}" || return 0
        fi
        sleep 0.05
    done
    return 1
}
# the probes below take a moment to reach the state a case needs; a fixed sleep would let
# a loaded host run the stop before the group exists, the helper forks or the trap is set
_wait_for() { # $@ = condition
    local i
    for ((i = 0; i < 100; i++)); do
        "$@" && return 0
        sleep 0.05
    done
    return 1
}
_group_size() { # $1 = pgid, $2 = count
    [ "$(pgrep -g "$1" 2>/dev/null | wc -l)" -ge "$2" ]
}
_comm_is() { # $1 = pid, $2 = comm
    local comm
    IFS= read -r comm 2>/dev/null < "/proc/$1/comm" || return 1
    [ "$comm" = "$2" ]
}
export -f _pid_running _group_live _wait_gone _wait_for _group_size _comm_is

# Each case runs in a shell of its own that starts the probe and stops it, the way a
# runner's cleanup trap does: wait only blocks on a pid the calling shell owns, so a stop
# that wedges there is only reproducible from the owner. timeout bounds the wedge and runs
# the case in its own process group, so a stop that signals group 0 takes out the case,
# not this suite. A case's stderr is bash's job chatter about killed probes unless it fails.
# Whatever a case started goes when it exits, since a probe left behind after a failure
# holds the suite's output open and a TERM-ignoring one would outlive timeout's own kill
_owned_case() { # $1 = label, $2 = script
    local err rc=0
    err="$(mktemp "${TMPDIR:-/tmp}/silere-probe-stop.XXXXXX")"
    timeout 10 bash -c "set -eu; source '$ROOT/scripts/probe-lib.sh'
        started=''
        trap 'for s in \$started; do kill -KILL -- \"-\$s\" \"\$s\" 2>/dev/null || true; done' EXIT
        $2" 2>"$err" || rc=$?
    if [ "$rc" -eq 124 ]; then
        cat "$err" >&2
        rm -f "$err"
        fail "$1: _probe_stop did not return within ten seconds"
    elif [ "$rc" -ne 0 ]; then
        cat "$err" >&2
        rm -f "$err"
        fail "$1 (exit $rc)"
    fi
    rm -f "$err"
}

_owned_case "a probe's helper dies with the group" '
    setsid bash -c "sleep 30 & wait" & p=$!
    started="$started $p"
    _wait_for _group_size "$p" 2 || { echo "group probe and its helper did not start"; exit 1; }
    _probe_stop "$p"
    _wait_gone "-$p" || { echo "a probe helper outlived the group stop"; exit 1; }
'

_owned_case "a reaped leader's helper still goes" '
    setsid bash -c "sleep 30 & disown" & p=$!
    started="$started $p"
    wait "$p" || true
    _wait_for _group_live "$p" || { echo "orphaned helper did not start"; exit 1; }
    _probe_stop "$p"
    _wait_gone "-$p" || { echo "a reaped leader helper outlived the stop"; exit 1; }
'

_owned_case "a stop without ps ends a TERM-ignoring probe" '
    setsid bash -c "trap \"\" TERM; exec sleep 30" & p=$!
    started="$started $p"
    _wait_for _comm_is "$p" sleep || { echo "TERM-ignoring probe did not start"; exit 1; }
    ps() { return 1; }
    _probe_stop "$p"
    unset -f ps
    _wait_gone "$p" || { echo "a TERM-ignoring probe survived a stop without ps"; exit 1; }
'

# without ps the parent and group come from /proc; a single-pid fallback would pass the
# case above by killing the leader alone, so these two tell the fallbacks apart
_owned_case "a stop without ps still leaves a foreign pid alone" '
    f="$(bash -c "setsid sleep 30 >/dev/null 2>&1 & echo \$!")"
    started="$started $f"
    _wait_for _comm_is "$f" sleep || { echo "foreign process did not start"; exit 1; }
    ps() { return 1; }
    _probe_stop "$f"
    unset -f ps
    sleep 0.2
    _pid_running "$f" || { echo "a stop without ps signalled a pid that is not this shell'"'"'s child"; exit 1; }
'

_owned_case "a stop without ps still ends the whole group" '
    setsid bash -c "sleep 30 & wait" & p=$!
    started="$started $p"
    _wait_for _group_size "$p" 2 || { echo "group probe and its helper did not start"; exit 1; }
    ps() { return 1; }
    _probe_stop "$p"
    unset -f ps
    _wait_gone "-$p" || { echo "a probe helper outlived a group stop without ps"; exit 1; }
'

_owned_case "a pid this shell did not start is left alone" '
    f="$(bash -c "setsid sleep 30 >/dev/null 2>&1 & echo \$!")"
    started="$started $f"
    _wait_for _comm_is "$f" sleep || { echo "foreign process did not start"; exit 1; }
    _probe_stop "$f"
    sleep 0.2
    _pid_running "$f" || { echo "a pid that is not this shell'"'"'s child was signalled"; exit 1; }
'

_owned_case "a plain child is stopped without its group" '
    sleep 30 & by=$!
    sleep 30 & p=$!
    started="$started $by $p"
    _probe_stop "$p"
    _wait_gone "$p" || { echo "a plain child survived its stop"; exit 1; }
    _pid_running "$by" || { echo "stopping a plain child signalled its whole group"; exit 1; }
'

# negated, 0 is the group and 1 every process; none of these may reach kill
_owned_case "malformed pids never reach kill" '
    sleep 30 & by=$!
    started="$started $by"
    for bad in "" 0 01 1 abc " 7" "7 "; do _probe_stop "$bad"; done
    sleep 0.2
    _pid_running "$by" || { echo "a malformed pid reached the group kill"; exit 1; }
'

# a TERM aimed at the launcher must reach the runner on its private bus, whose cleanup stops the
# probe; dbus-run-session itself would die and leave both running
if command -v dbus-run-session >/dev/null 2>&1; then
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/silere-probe-launcher.XXXXXX")"
    cat > "$scratch/runner.sh" <<EOF
#!/usr/bin/env bash
set -euo pipefail
source '$ROOT/scripts/probe-lib.sh'
if [[ "\${1:-}" != "--private-bus" ]]; then
    _probe_private_bus "\$0" "\$@"
fi
shift
probe_pid=""
cleanup() { _probe_stop "\$probe_pid"; }
trap cleanup EXIT
trap 'exit 130' INT TERM
setsid sleep 30 &
probe_pid=\$!
echo "\$probe_pid" > '$scratch/probe-pid'
wait "\$probe_pid"
EOF
    bash "$scratch/runner.sh" 2>/dev/null &
    launcher=$!
    _wait_for test -s "$scratch/probe-pid" || fail "the launched runner did not start its probe"
    p="$(cat "$scratch/probe-pid")"
    kill -TERM "$launcher"
    status=0
    _wait_gone "$p" || status=1
    kill -KILL -- "-$p" "$p" 2>/dev/null || true
    for ((i = 0; i < 100; i++)); do
        kill -0 "$launcher" 2>/dev/null || break
        sleep 0.05
    done
    if kill -0 "$launcher" 2>/dev/null; then
        kill -KILL "$launcher" 2>/dev/null || true
        rm -rf "$scratch"
        fail "the launcher did not exit after forwarding a TERM"
    fi
    launcher_status=0
    wait "$launcher" || launcher_status=$?
    rm -rf "$scratch"
    [ "$status" -eq 0 ] || fail "a TERM to the launcher left the probe running"
    [ "$launcher_status" -ne 0 ] || fail "the launcher reported success for a cancelled run"
fi

printf 'probe stop passed\n'
