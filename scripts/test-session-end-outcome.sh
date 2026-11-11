#!/usr/bin/env bash
# hypr-session-end.sh reads hyprshutdown's verbose log to tell a finished run from a
# cancelled one, and only a finished run goes on to end the session. That script logs out,
# reboots or powers off, so this never runs or sources it: it lifts out the text of the
# three log-parsing functions, refuses that text if it calls anything that acts on the
# session, and evaluates only that text against fixture logs.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Only for proving this test catches a parser change: point it at an edited copy of the
# script outside the repository, never at a script that should run.
SCRIPT="${SILERE_SESSION_END_PARSER_SOURCE:-$ROOT/scripts/hypr-session-end.sh}"
FIXTURES="$ROOT/scripts/fixtures/session-end"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

[ -f "$SCRIPT" ] || fail "session end outcome: $SCRIPT is missing"

# One block per function, from its opener in column one to the first closing brace in
# column one. A body that grew another opener has run past its own end into code that
# is not the parser, so it is refused before anything evaluates it.
parser=""
for fn in _outcome _line _logged; do
    body="$(sed -n "/^${fn}() {\$/,/^}\$/p" "$SCRIPT")"
    [ -n "$body" ] || fail "session end outcome: no '${fn}() {' at the start of a line in $SCRIPT"
    [ "$(printf '%s\n' "$body" | tail -n 1)" = "}" ] \
        || fail "session end outcome: ${fn}() has no closing brace in column one in $SCRIPT"
    [ "$(printf '%s\n' "$body" | grep -cE '^[A-Za-z_][A-Za-z0-9_]*\(\)')" -eq 1 ] \
        || fail "session end outcome: the text lifted for ${fn}() holds another function"
    parser="$parser$body"$'\n'
done

# What the script's main flow runs to end, restore or report on the session, and the
# helpers that wrap those calls. None of it belongs in a log parser.
forbidden='hyprshutdown|systemd-run|systemctl|loginctl|hyprctl|shutdown|reboot|poweroff|notify-send|busctl|exec|eval|source|_end_session|_hyprland_up|_restore_session|_running_session_units|_notify_failure|"\$@"|\$\*'
if acting="$(printf '%s' "$parser" | grep -nwE "$forbidden")"; then
    printf '%s\n' "$acting" >&2
    fail "session end outcome: the parser text calls something that acts on the session; not evaluating it"
fi

# The parser needs grep and tail; a PATH holding only those keeps any other command it
# might name from resolving at all.
bin="$(mktemp -d "${TMPDIR:-/tmp}/silere-session-end-outcome.XXXXXX")"
trap 'rm -rf "$bin"' EXIT
for tool in grep tail; do
    ln -s "$(command -v "$tool")" "$bin/$tool"
done

outcome_of() { # $1 = log
    # the script runs under set -u alone; under -e a grep that finds no count would end
    # the parser before it could answer
    ( set +e +o pipefail; PATH="$bin"; eval "$parser"; _outcome "$1" )
}

# fixture, expected outcome, provenance. "real" lines were logged by hyprshutdown on this
# machine, with the app names and pids replaced by neutral ones; "constructed" lines follow
# the script's own patterns in the real lines' format, so they guard the parser against
# regressions, not against hyprshutdown rewording a line.
cases=(
    "finished.log finished real: a reboot whose last check counted no apps"
    "cancelled.log cancelled constructed: the last check still counted apps; plain levels without colour codes"
    "force-killed.log finished constructed: a kill after the checks, which wins over the count"
    "cannot-kill.log finished constructed: a force quit that found the app already gone"
    "no-apps.log finished constructed: nothing to close, ended before the first check"
    "quit-before-check.log unknown constructed: apps asked to quit, ended before the first check"
    "empty.log unknown constructed: hyprshutdown wrote nothing"
    "forged-status.log cancelled constructed: app classes that read as a finished count and a kill"
)
checked=0
for entry in "${cases[@]}"; do
    read -r fixture expected _ <<< "$entry"
    [ -f "$FIXTURES/$fixture" ] || fail "session end outcome: fixture $fixture is missing"
    actual="$(outcome_of "$FIXTURES/$fixture")"
    [ "$actual" = "$expected" ] \
        || fail "session end outcome: $fixture read as '$actual', expected '$expected'"
    checked=$((checked + 1))
done
printf 'session end outcome: %d hyprshutdown logs parsed as expected\n' "$checked"
