#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

PROBE_SOURCE="scripts/probe-popup-lifecycle.qml"

_probe_require_qs

log="$(mktemp "${TMPDIR:-/tmp}/silere-popup-lifecycle.XXXXXX.log")"
cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-popup-lifecycle-cfg.XXXXXX")"
reduced_cfg="$(mktemp -d "${TMPDIR:-/tmp}/silere-popup-lifecycle-cfg.XXXXXX")"
runtime="$(mktemp -d "${TMPDIR:-/tmp}/silere-popup-lifecycle-runtime.XXXXXX")"
probe_project="$(mktemp -d "${TMPDIR:-/tmp}/silere-popup-lifecycle-project.XXXXXX")"
chmod 0700 "$runtime"
mkdir -p "$probe_project/modules/menu"
cp "$PROBE_SOURCE" "$probe_project/modules/menu/probe-popup-lifecycle-owner.qml"
cp "$ROOT/modules/menu/MenuPageLifecycle.qml" \
    "$probe_project/modules/menu/MenuPageLifecycle.qml"
printf '%s\n' 'internal MenuPageLifecycle 1.0 MenuPageLifecycle.qml' \
    > "$probe_project/modules/menu/qmldir"
ln -s "$ROOT/config" "$probe_project/config"
ln -s "$ROOT/services" "$probe_project/services"
printf '%s\n' \
    'import QtQuick' \
    'import Quickshell' \
    'import "modules/menu" as Menu' \
    'ShellRoot {' \
    '    id: root' \
    '    property var owner: null' \
    '    Component.onCompleted: {' \
    '        const component = Qt.createComponent("file://" + Quickshell.shellDir' \
    '            + "/modules/menu/probe-popup-lifecycle-owner.qml")' \
    '        if (component.status !== Component.Ready) {' \
    '            console.warn("PROBE-FAIL owner :: " + component.errorString())' \
    '            Qt.exit(1)' \
    '            return' \
    '        }' \
    '        root.owner = component.createObject(root)' \
    '    }' \
    '}' > "$probe_project/probe-popup-lifecycle.qml"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    rm -f "$log"
    rm -rf "$cfg" "$reduced_cfg" "$runtime" "$probe_project"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

mkdir -p "$cfg/silere-shell"
printf '{"__version":1}\n' > "$cfg/silere-shell/settings.json"
mkdir -p "$reduced_cfg/silere-shell"
printf '{"__version":1,"reduceMotion":true}\n' \
    > "$reduced_cfg/silere-shell/settings.json"

run_probe() { # $1 = label, $2 = config dir
    : > "$log"
    XDG_CONFIG_HOME="$2" XDG_STATE_HOME="$2" XDG_RUNTIME_DIR="$runtime" \
        QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
        qs -p "$probe_project/probe-popup-lifecycle.qml" --no-color >"$log" 2>&1 &
    probe_pid=$!

    _probe_wait "$log" "$probe_pid" 'PROBE-POPUP-LIFECYCLE' 80 0.25 || true

    if ! grep -q 'PROBE-POPUP-LIFECYCLE passed' "$log" 2>/dev/null; then
        cat "$log" >&2
        echo "FAIL: popup lifecycle probe did not pass ($1)" >&2
        exit 1
    fi

    local failed=0
    if grep -q 'PROBE-FAIL' "$log"; then
        grep 'PROBE-FAIL' "$log" | sed 's/^.*PROBE-FAIL/  /' | sort -u | head -20 >&2
        failed=1
    fi
    local errs
    errs="$(_probe_errors "$log")"
    if [ -n "$errs" ]; then
        printf '%s\n' "$errs" | sed 's/^/  /' >&2
        failed=1
    fi
    if [ "$failed" -ne 0 ]; then
        echo "FAIL: popup lifecycle probe logged a runtime error ($1)" >&2
        exit 1
    fi

    printf '  %-15s %s\n' "$1" \
        "$(grep -oE 'PROBE-POPUP-LIFECYCLE passed [0-9]+ checks' "$log" | tail -1)"
    _probe_stop "$probe_pid"
    probe_pid=""
}

run_probe "default" "$cfg"
run_probe "reduced-motion" "$reduced_cfg"
