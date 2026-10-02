#!/usr/bin/env bash
# The power rail's Log out on Hyprland. Usage: hypr-logout.sh <exit dispatcher text>
#
# hyprshutdown lets apps close before Hyprland exits, but it SIGTERMs every layer client,
# this shell among them. Launched from the shell it would sit in the shell's systemd unit
# and die with it, so it runs in a transient unit of its own instead. That unit also
# outlives the shell to report what hyprshutdown can't: it exits 0 whether the user
# cancelled or Hyprland ignored its exit request, and with the shell gone there is no
# notification server left to tell either way.
set -u

exit_text="${1:?usage: hypr-logout.sh <exit dispatcher text>}"

_restore_shell() {
    [ -n "$1" ] && systemctl --user start "$1"
}

_notify_failure() {
    command -v notify-send >/dev/null 2>&1 || return 0
    # the shell is the notification server, so the report waits for it to come back up
    for _ in $(seq 40); do
        busctl --user status org.freedesktop.Notifications >/dev/null 2>&1 && break
        sleep 0.25
    done
    notify-send --urgency=critical --app-name=silere-shell "Log out failed" "$1"
}

if [ "${2:-}" = "--watch" ]; then
    shell_unit="${3:-}"
    hyprshutdown --no-fork --top-label "Logging out..."
    rc=$?
    if [ "$rc" -eq 0 ]; then
        # a refused socket means the session already ended
        clients="$(hyprctl -j clients 2>/dev/null)" || exit 0
        # windows left over mean the user cancelled, so Hyprland was never asked to exit
        if [ "$(printf '%s' "$clients" | tr -d '[:space:]')" != "[]" ]; then
            _restore_shell "$shell_unit"
            exit 0
        fi
        for _ in $(seq 20); do
            hyprctl version >/dev/null 2>&1 || exit 0
            sleep 0.25
        done
        reason="Your apps closed, but Hyprland did not exit."
    else
        hyprctl version >/dev/null 2>&1 || exit 0
        reason="hyprshutdown stopped with status $rc. You are still logged in."
    fi
    _restore_shell "$shell_unit"
    _notify_failure "$reason"
    exit 0
fi

if command -v hyprshutdown >/dev/null 2>&1 && command -v systemd-run >/dev/null 2>&1; then
    # only a service can be started again; a shell run from a scope or a terminal has no unit to restore
    shell_unit="$(systemctl --user whoami 2>/dev/null)" || shell_unit=""
    case "$shell_unit" in *.service) ;; *) shell_unit="" ;; esac
    # a transient unit starts from the user manager's environment, which need not carry the session's
    exec systemd-run --user --collect --quiet --unit=silere-logout \
        -E PATH -E WAYLAND_DISPLAY -E HYPRLAND_INSTANCE_SIGNATURE -E XDG_RUNTIME_DIR \
        -- bash "$0" "$exit_text" --watch "$shell_unit"
fi
exec hyprctl dispatch "$exit_text"
