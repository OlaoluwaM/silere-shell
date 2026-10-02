#!/usr/bin/env bash
# The power rail's Log out, Reboot and Power off on Hyprland.
# Usage: hypr-session-end.sh <logout|reboot|poweroff> <exit dispatcher text> [command...]
# The command is what Reboot or Power off runs once apps have closed, and what runs in
# hyprshutdown's place when it is missing; Log out ends the session with the exit dispatcher.
#
# hyprshutdown lets apps close first, but it SIGTERMs every layer client, this shell among
# them. Launched from the shell it would sit in the shell's systemd unit and die with it,
# so it runs in a transient unit of its own. It runs with --no-exit, and this script ends
# the session once the apps are gone, which keeps Hyprland up to report a failure. With the
# shell gone there is no notification server, so the unit also restarts the shell before
# reporting anything.
set -u

usage="usage: hypr-session-end.sh <logout|reboot|poweroff> <exit dispatcher text> [command...]"

shell_unit=""
watch=false
if [ "${1:-}" = "--watch" ]; then
    watch=true
    shell_unit="${2:-}"
    shift 2
fi

action="${1:?$usage}"
exit_text="${2:?$usage}"
shift 2

case "$action" in
    logout)   label="Logging out...";  fail_title="Log out failed" ;;
    reboot)   label="Rebooting...";    fail_title="Reboot failed" ;;
    poweroff) label="Powering off..."; fail_title="Shut down failed" ;;
    *) printf 'hypr-session-end: unknown action %s\n' "$action" >&2; exit 2 ;;
esac

if [ "$action" != "logout" ] && [ "$#" -eq 0 ]; then
    printf 'hypr-session-end: %s needs a command\n' "$action" >&2
    exit 2
fi

_end_session() {
    if [ "$action" = "logout" ]; then
        hyprctl dispatch "$exit_text"
    else
        "$@"
    fi
}

_hyprland_up() {
    hyprctl version >/dev/null 2>&1
}

# with nothing to close, hyprshutdown exits before its first check and logs no count, so
# the desktop has to show it: no window, no layer client and no process Hyprland started,
# Xwayland aside
_apps_gone() {
    local clients layers hl_pid child
    command -v pgrep >/dev/null 2>&1 || return 1
    clients="$(hyprctl -j clients 2>/dev/null)" || return 1
    [ "$(printf '%s' "$clients" | tr -d '[:space:]')" = "[]" ] || return 1
    layers="$(hyprctl -j layers 2>/dev/null)" || return 1
    if printf '%s' "$layers" | grep -q '"namespace"'; then return 1; fi
    hl_pid="$(hyprctl -j instances 2>/dev/null | tr -d '[:space:]' \
        | grep -o "\"instance\":\"${HYPRLAND_INSTANCE_SIGNATURE:-}\"[^}]*" \
        | grep -o '"pid":[0-9]*' | cut -d: -f2)"
    [ -n "$hl_pid" ] || return 1
    for child in $(pgrep -P "$hl_pid"); do
        [ "$(cat "/proc/$child/comm" 2>/dev/null)" = "Xwayland" ] || return 1
    done
    return 0
}

# hyprshutdown exits 0 whether the apps closed, the user forced them or the user cancelled,
# and a cancel can't be read off the desktop afterwards: apps it already asked to close may
# still finish closing. Its own log can tell: a force quit logs each kill, and each 150 ms
# check logs how many apps it still waits on, so a finished run ends on 0 and a cancelled
# one doesn't. A log that says neither is reported, not guessed at.
_outcome() {
    local last
    if grep -q -e 'CApp::kill: killing' -e "Can't kill" "$1"; then echo finished; return; fi
    last="$(grep -o 'Updated state: apps size [0-9]*' "$1" | tail -n 1 | grep -o '[0-9]*$')"
    if [ "$last" = "0" ]; then echo finished
    elif [ -n "$last" ]; then echo cancelled
    elif grep -q 'Parsed [0-9]* apps from socket' "$1" && _apps_gone; then echo finished
    else echo unknown
    fi
}

_restore_shell() {
    [ -n "$shell_unit" ] && systemctl --user start "$shell_unit"
}

_notify_failure() {
    command -v notify-send >/dev/null 2>&1 || return 0
    # the shell is the notification server, so the report waits for it to come back up
    for _ in $(seq 40); do
        busctl --user status org.freedesktop.Notifications >/dev/null 2>&1 && break
        sleep 0.25
    done
    notify-send --urgency=critical --app-name=silere-shell "$fail_title" "$1"
}

if $watch; then
    log="$(mktemp -p "${XDG_RUNTIME_DIR:-/tmp}" silere-session-end.XXXXXX)"
    hyprshutdown --no-fork --no-exit --verbose --top-label "$label" >"$log" 2>&1
    rc=$?
    outcome="$(_outcome "$log")"
    # into the unit's journal, where an outcome can be checked afterwards
    cat "$log"
    rm -f "$log"
    # something else already ended the session
    _hyprland_up || exit 0
    if [ "$rc" -ne 0 ]; then
        _restore_shell
        _notify_failure "hyprshutdown stopped with status $rc."
        exit 0
    fi
    case "$outcome" in
        cancelled)
            _restore_shell
            exit 0
            ;;
        unknown)
            _restore_shell
            _notify_failure "Couldn't tell whether hyprshutdown finished, so nothing else was done."
            exit 0
            ;;
    esac
    _end_session "$@"
    erc=$?
    if [ "$action" = "logout" ]; then
        for _ in $(seq 20); do
            _hyprland_up || exit 0
            sleep 0.25
        done
        reason="Your apps closed, but Hyprland did not exit."
    else
        [ "$erc" -eq 0 ] && exit 0
        reason="Your apps closed, but $* failed with status $erc."
    fi
    _restore_shell
    _notify_failure "$reason"
    exit 0
fi

if command -v hyprshutdown >/dev/null 2>&1 && command -v systemd-run >/dev/null 2>&1; then
    # only a service can be started again; a shell run from a scope or a terminal has no unit to restore
    shell_unit="$(systemctl --user whoami 2>/dev/null)" || shell_unit=""
    case "$shell_unit" in *.service) ;; *) shell_unit="" ;; esac
    # a transient unit starts from the user manager's environment, which need not carry the session's
    exec systemd-run --user --collect --quiet --unit=silere-session-end \
        -E PATH -E WAYLAND_DISPLAY -E HYPRLAND_INSTANCE_SIGNATURE -E XDG_RUNTIME_DIR \
        -- bash "$0" --watch "$shell_unit" "$action" "$exit_text" "$@"
fi
if [ "$action" = "logout" ]; then exec hyprctl dispatch "$exit_text"; fi
exec "$@"
