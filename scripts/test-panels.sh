#!/usr/bin/env bash
set -euo pipefail

# A real sender must never reach the desktop's notification daemon.
if [[ "${1:-}" != "--private-bus" ]]; then
    exec dbus-run-session -- bash "$0" --private-bus "$@"
fi
shift

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

trap 'exit 130' INT TERM

PROBE="scripts/probe-panels.qml"

_probe_require_qs

# A PanelWindow needs a real layer-shell backend, so unlike the other probes this
# one cannot fall back to the offscreen platform plugin. Skip rather than fail:
# the same container that runs test-surfaces.sh has no compositor.
if [ -z "${WAYLAND_DISPLAY:-}" ]; then
    echo "SKIP: no Wayland display; layer-shell surfaces cannot be built" >&2
    exit 0
fi
case "$WAYLAND_DISPLAY" in
    /*) wayland_socket="$WAYLAND_DISPLAY" ;;
    *) wayland_socket="${XDG_RUNTIME_DIR:-}/$WAYLAND_DISPLAY" ;;
esac
if [ ! -S "$wayland_socket" ]; then
    echo "SKIP: Wayland socket is unavailable: $wayland_socket" >&2
    exit 0
fi

# Every surface requiring a targetScreen, so a new one is covered without editing
# this list.
if [ "$#" -gt 0 ]; then
    list="$(printf '%s\n' "$@")"
else
    list="$(grep -rlE '^ {0,4}required property ShellScreen targetScreen' \
        --include='*.qml' modules | sort -u)"
fi
count="$(printf '%s\n' "$list" | grep -c . || true)"
if [ "$count" -eq 0 ]; then
    echo "FAIL: no panel surfaces to probe" >&2
    exit 1
fi

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-panels.XXXXXX")"
log="$probe_root/probe.log"
probe_cfg="$probe_root/config-home"
probe_project="$probe_root/project"
probe_pid=""
cleanup() {
    _probe_stop "${probe_pid:-}"
    rm -rf "$probe_root"
}
trap cleanup EXIT

# An empty config dir is the default state, and it keeps the probe off the live
# settings.json — these surfaces write through the same singletons the shell does.
mkdir -p "$probe_cfg/silere-shell" "$probe_project"
# Quickshell treats its entry file's directory as the project root. Keep the source
# tree beside this disposable entry point so local config, services, and modules
# imports resolve as they do from shell.qml.
_probe_project "$ROOT" "$PROBE" "$probe_project"

# XDG_RUNTIME_DIR is deliberately inherited: it is where the Wayland socket lives.
# Force the Wayland platform so an inherited offscreen setting cannot turn this into
# the headless surface check. Never pkill: a name match would take down the user's shell.
XDG_CONFIG_HOME="$probe_cfg" XDG_STATE_HOME="$probe_cfg" \
    SILERE_PROBE_ROOT="$ROOT" SILERE_PROBE_LIST="$list" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=wayland QT_NO_XDG_DESKTOP_PORTAL=1 \
    qs -p "$probe_project/${PROBE##*/}" --no-color >"$log" 2>&1 &
probe_pid=$!
_probe_wait "$log" "$probe_pid" 'PROBE-PANELS' 120 0.5 || true

if grep -q 'PROBE-PANELS: no screen' "$log" 2>/dev/null; then
    echo "SKIP: compositor exposed no screen to the probe" >&2
    exit 0
fi
if ! grep -q 'PROBE-PANELS built' "$log" 2>/dev/null; then
    cat "$log" >&2
    echo "FAIL: panel probe did not finish" >&2
    exit 1
fi

failed=0
if ! grep -q "PROBE-PANELS built $count/$count" "$log"; then
    echo "FAIL: panel probe did not build all $count surfaces" >&2
    failed=1
fi
if grep -q 'PROBE-FAIL' "$log"; then
    grep 'PROBE-FAIL' "$log" | sed 's/^.*PROBE-FAIL/  /' >&2
    failed=1
fi
errs="$(_probe_errors "$log")"
if [ -n "$errs" ]; then
    printf '%s\n' "$errs" | sed 's/^/  /' >&2
    failed=1
fi
if [ "$failed" -ne 0 ]; then
    echo "FAIL: a layer-shell surface failed to build cleanly" >&2
    exit 1
fi

printf 'panel probe passed (%s)\n' \
    "$(grep -oE 'PROBE-PANELS built [0-9]+/[0-9]+' "$log" | tail -1 | sed 's/PROBE-PANELS built //')"
