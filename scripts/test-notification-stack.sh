#!/usr/bin/env bash
set -euo pipefail

if [[ "${1:-}" != "--private-bus" ]]; then
    exec dbus-run-session -- bash "$0" --private-bus
fi

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
_probe_require_qs

case "${WAYLAND_DISPLAY:-}" in
    /*) wayland_socket="$WAYLAND_DISPLAY" ;;
    "") echo "SKIP: a Wayland compositor is required for notification stack motion" >&2; exit 0 ;;
    *) wayland_socket="${XDG_RUNTIME_DIR:-}/$WAYLAND_DISPLAY" ;;
esac
[ -S "$wayland_socket" ] || {
    echo "SKIP: Wayland socket is unavailable" >&2
    exit 0
}

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-notification-stack.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    if [ "${SILERE_PROBE_KEEP:-0}" = 1 ]; then
        echo "kept notification stack probe: $probe_root" >&2
        return
    fi
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

prepare_project() { # $1 = idle state, $2 = transition implementation, $3 = height action
    local idle_state="$1" implementation="$2" action="$3"
    project="$probe_root/project-$idle_state-$implementation-$action"
    mkdir -p "$project"
    cp "$ROOT/scripts/probe-notification-stack.qml" "$project/probe-notification-stack.qml"
    cp -a "$ROOT/config" "$ROOT/modules" "$ROOT/services" "$project/"
    PROJECT="$project" IMPLEMENTATION="$implementation" ACTION="$action" python3 - <<'PY'
from pathlib import Path
import os

path = Path(os.environ["PROJECT"]) / "modules/notifications/NotificationPopups.qml"
source = path.read_text()

def replace_once(anchor, replacement):
    global source
    if source.count(anchor) != 1:
        raise SystemExit(f"FAIL: expected one probe anchor, found {source.count(anchor)}")
    source = source.replace(anchor, replacement)

if os.environ["IMPLEMENTATION"] in ("child-behavior", "column-move"):
    proxy = '''                            // Column owns layout y directly. Keep an explicitly controlled visual
                            // position so height relayouts can stop movement without restarting it.
                            property real visualY: 0
                            readonly property bool _visualMoveAllowed: _posReady && shouldLoad && visible
                                && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
                                && !win._stackHeightAnimating

                            function _snapVisualY(): void {
                                _visualMove.stop()
                                visualY = y
                            }

                            onYChanged: {
                                if (_visualMoveAllowed) _visualMove.restart()
                                else _snapVisualY()
                            }
                            on_VisualMoveAllowedChanged: if (!_visualMoveAllowed) _snapVisualY()

                            NumberAnimation {
                                id: _visualMove
                                target: _slot
                                property: "visualY"
                                to: _slot.y
                                duration: Motion.normal
                                easing.type: Easing.OutCubic
                            }
'''
    if source.count(proxy) != 1:
        raise SystemExit(f"FAIL: expected one visual proxy, found {source.count(proxy)}")
    source = source.replace(proxy, "                            property real visualY: y\n")
    transform = "                            transform: Translate { y: _slot.visualY - _slot.y }\n"
    if source.count(transform) != 1:
        raise SystemExit(f"FAIL: expected one visual transform, found {source.count(transform)}")
    source = source.replace(transform, "")

if os.environ["IMPLEMENTATION"] == "column-move":
    column_anchor = "                    spacing: 0\n"
    replace_once(column_anchor, column_anchor + '''                    move: Transition {
                        NumberAnimation {
                            properties: "y"
                            duration: Motion.normal
                            easing.type: Easing.OutCubic
                        }
                    }
''')

slot_anchor = ("                            x: win._alignedX(parent.width, width)\n\n"
               if os.environ["IMPLEMENTATION"] in ("child-behavior", "column-move")
               else "                            transform: Translate { y: _slot.visualY - _slot.y }\n")
position_property = "y" if os.environ["IMPLEMENTATION"] in ("child-behavior", "column-move") else "visualY"
probe_hook = (f"                            on{position_property[0].upper() + position_property[1:]}Changed: console.warn(\"STACK-PROBE y t=\" + Date.now() + \" id=\" + modelData.id + \" y=\" + {position_property} + \" index=\" + index + \" gap=\" + _gap + \" stack=\" + win._stackHeightAnimating)\n"
              "                            onHeightChanged: console.warn(\"STACK-PROBE h t=\" + Date.now() + \" id=\" + modelData.id + \" h=\" + height)\n\n")
if os.environ["IMPLEMENTATION"] == "child-behavior":
    probe_hook = ("                            MotionBehavior on y {\n"
                  "                                NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }\n"
                  "                            }\n\n" + probe_hook)
replace_once(slot_anchor, slot_anchor + probe_hook)
complete_anchor = "                                if (shouldLoad) timeoutStartedAt = Notifications.updateTimeFor(modelData.id)\n"
replace_once(complete_anchor, complete_anchor
             + "                                console.warn(\"STACK-PROBE complete id=\" + modelData.id + \" visible=\" + shouldLoad + \" y=\" + y)\n")
visible_anchor = "                            onShouldLoadChanged: {\n"
replace_once(visible_anchor, visible_anchor
             + "                                console.warn(\"STACK-PROBE visible t=\" + Date.now() + \" id=\" + modelData.id + \" value=\" + shouldLoad + \" y=\" + y)\n")
stack_anchor = "    function _noteLeaving(): void {\n"
replace_once(stack_anchor, "    on_StackHeightAnimatingChanged: console.warn(\"STACK-PROBE stack-motion t=\" + Date.now() + \" active=\" + _stackHeightAnimating + \" visible=\" + _visibleCards)\n\n" + stack_anchor)
if os.environ["ACTION"] == "showall":
    replace_once(stack_anchor, "    on_ShowAllChanged: console.warn(\"STACK-PROBE showall-state t=\" + Date.now() + \" value=\" + _showAll + \" count=\" + stack.count)\n\n" + stack_anchor)
    repeater_anchor = "                    Repeater {\n"
    replace_once(repeater_anchor, "                    Timer {\n                        interval: 250\n                        running: stack.count === 3\n                        onTriggered: { win.revealAll(); console.warn(\"STACK-PROBE showall t=\" + Date.now()) }\n                    }\n\n" + repeater_anchor)
leaving_anchor = "                                    onLeaving: win._noteLeaving()\n"
replace_once(leaving_anchor,
             "                                    onLeaving: { win._noteLeaving(); console.warn(\"STACK-PROBE leaving t=\" + Date.now() + \" id=\" + _slot.modelData.id + \" index=\" + _slot.index + \" gap=\" + _slot._gap) }\n")

card_path = Path(os.environ["PROJECT"]) / "modules/notifications/NotificationCard.qml"
card_source = card_path.read_text()
card_anchor = "    function _completeDismiss(): void {\n"
if card_source.count(card_anchor) != 1:
    raise SystemExit(f"FAIL: expected one card probe anchor, found {card_source.count(card_anchor)}")
card_source = card_source.replace(card_anchor,
    "    onLayoutAnimatingChanged: console.warn(\"STACK-PROBE card-motion t=\" + Date.now() + \" id=\" + notifId + \" active=\" + layoutAnimating + \" collapse=\" + _collapseAnim.running)\n\n" + card_anchor)
if os.environ["ACTION"] == "expand":
    column_anchor = "                    spacing: 0\n"
    replace_once(column_anchor, column_anchor
                 + "                    Timer { interval: 2500; running: true; onTriggered: { console.warn(\"STACK-PROBE expand t=\" + Date.now()); stack.itemAt(0).cardItem.probeExpand() } }\n")
    expand_anchor = "    function _resetBodyExpansion(): void {\n"
    if card_source.count(expand_anchor) != 1:
        raise SystemExit(f"FAIL: expected one card probe anchor, found {card_source.count(expand_anchor)}")
    card_source = card_source.replace(expand_anchor,
        "    function probeExpand(): void { _body.expanded = true }\n" + expand_anchor)
card_path.write_text(card_source)
path.write_text(source)
PY
    cat >"$project/services/Idle.qml" <<EOF
pragma Singleton
import QtQuick
QtObject { property bool isIdle: $idle_state; readonly property bool isQuiet: isIdle }
EOF
}

run_mode() { # $1 = label, $2 = reduce motion, $3 = idle state, $4 = implementation, $5 = action
    local label="$1" reduce="$2" idle="$3" implementation="$4" action="${5:-none}" log cfg first_id second_id third_id
    prepare_project "$idle" "$implementation" "$action"
    cfg="$probe_root/config-$label"
    mkdir -p "$cfg/silere-shell" "$probe_root/runtime-$label"
    chmod 0700 "$probe_root/runtime-$label"
    printf '{"__version":1,"notifMaxVisible":2,"reduceMotion":%s}\n' "$reduce" \
        >"$cfg/silere-shell/settings.json"
    log="$probe_root/$label.log"
    XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_RUNTIME_DIR="$probe_root/runtime-$label" \
        WAYLAND_DISPLAY="$wayland_socket" QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=wayland \
        QT_NO_XDG_DESKTOP_PORTAL=1 qs -p "$project/probe-notification-stack.qml" --no-color >"$log" 2>&1 &
    probe_pid=$!
    for _ in $(seq 1 40); do
        gdbus introspect --session --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications >/dev/null 2>&1 && break
        sleep .25
    done
    gdbus introspect --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications >/dev/null
    first_id=$(notify-send --print-id --expire-time=0 First)
    sleep 1
    second_id=$(notify-send --print-id --expire-time=0 Second)
    sleep 1
    third_id=$(notify-send --print-id --expire-time=0 Third)
    sleep 1
    first_id="${first_id#* }"
    second_id="${second_id#* }"
    third_id="${third_id#* }"
    if [ "$action" = showall ]; then
        sleep .5
    fi
    gdbus call --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.CloseNotification "$first_id" >/dev/null
    sleep 1
    _probe_stop "$probe_pid"
    probe_pid=""
    if grep -q 'PROBE-FAIL' "$log" || [ -n "$(_probe_errors "$log")" ]; then
        cat "$log" >&2
        echo "FAIL: notification stack probe runtime error ($label)" >&2
        exit 1
    fi
    LOG="$log" LABEL="$label" FIRST="$first_id" SECOND="$second_id" THIRD="$third_id" \
        IMPLEMENTATION="$implementation" python3 - <<'PY'
import os
import re

lines = open(os.environ["LOG"]).read().splitlines()
event = re.compile(r"STACK-PROBE y t=\d+ id=(\d+) y=([-0-9.eE]+)")
second = os.environ["SECOND"]
third = os.environ["THIRD"]

def values(ident, start, end):
    return [float(match.group(2)) for line in lines[start:end]
            if (match := event.search(line)) and match.group(1) == ident]

reveal_markers = [index for index, line in enumerate(lines)
                  if re.search(rf"STACK-PROBE visible t=\d+ id={third} value=true ", line)]
if len(reveal_markers) != 1:
    raise SystemExit(f"FAIL: expected one retained-slot reveal: {reveal_markers}")
reveal_at = reveal_markers[0]
initial = values(second, 0, reveal_at)
if len(initial) != 1 or initial[0] <= 0:
    raise SystemExit(f"FAIL: initial slot did not settle in one step: {initial}")
start = initial[0]
moved = values(second, reveal_at, len(lines))
if not moved or abs(moved[-1]) > 0.1:
    raise SystemExit(f"FAIL: displaced slot did not settle at zero: {moved}")
intermediate = [value for value in moved if 0.1 < value < start - 0.1]
revealed = values(third, reveal_at, len(lines))
if os.environ["LABEL"] == "showall-shrink":
    if not revealed:
        raise SystemExit("FAIL: retained slot did not report movement after show-all")
    third_end = revealed[-1]
    third_intermediate = [value for value in revealed if third_end + 0.1 < value < revealed[0] - 0.1]
    second_heights = [float(match.group(1)) for line in lines
                      if (match := re.search(rf"STACK-PROBE h t=\d+ id={second} h=([-0-9.eE]+)", line))]
    if (revealed[0] <= third_end + 0.1 or third_end <= 0 or len(third_intermediate) < 3
            or not second_heights or abs(third_end - second_heights[-1]) > 0.1):
        raise SystemExit(f"FAIL: retained slot did not animate with the stack: {revealed}")
else:
    if values(third, 0, reveal_at):
        raise SystemExit("FAIL: hidden slot moved before it was revealed")
    if len(revealed) != 1 or revealed[0] <= 0:
        raise SystemExit(f"FAIL: retained hidden slot did not reveal in one final placement: {revealed}")

label = os.environ["LABEL"]
implementation = os.environ["IMPLEMENTATION"]
if implementation == "child-behavior":
    if intermediate:
        raise SystemExit(f"FAIL: child Behavior unexpectedly animated: {len(intermediate)} samples")
    print("notification stack child-behavior red demonstrated")
elif label in ("normal", "showall-shrink"):
    if len(intermediate) < 3:
        raise SystemExit(f"FAIL: displaced slot did not animate: {len(intermediate)} samples")
    print(f"notification stack {label} passed ({len(intermediate)} intermediate samples)")
elif intermediate:
    raise SystemExit(f"FAIL: motion ran with {label} enabled: {len(intermediate)} samples")
else:
    print(f"notification stack {label} passed (0 intermediate samples)")
if label == "showall-shrink":
    marker = next((index for index, line in enumerate(lines) if "STACK-PROBE showall t=" in line), None)
    if marker is None:
        raise SystemExit("FAIL: show-all hook did not run")
    flicker = [line for line in lines[marker + 1:]
               if re.search(rf"STACK-PROBE visible t=\d+ id={third} value=false", line)]
    if flicker:
        raise SystemExit(f"FAIL: retained slot unloaded after show-all: {flicker}")
    states = [match.group(1) for line in lines
              if (match := re.search(r"STACK-PROBE showall-state t=\d+ value=(true|false) count=\d+", line))]
    if states[:1] != ["true"] or states[-1:] != ["false"]:
        raise SystemExit(f"FAIL: show-all did not reset after reindex: {states}")
    print("notification stack show-all shrink passed")
PY
}

run_height_mode() { # $1 = label, $2 = timeout or expand, $3 = implementation
    local label="$1" action="$2" implementation="${3:-move}" log cfg first_id second_id third_id max_visible
    third_id=""
    prepare_project false "$implementation" "$action"
    cfg="$probe_root/config-$label"
    mkdir -p "$cfg/silere-shell" "$probe_root/runtime-$label"
    chmod 0700 "$probe_root/runtime-$label"
    max_visible=0
    [ "$action" = timeout ] && max_visible=2
    printf '{"__version":1,"notifMaxVisible":%s,"reduceMotion":false}\n' "$max_visible" >"$cfg/silere-shell/settings.json"
    log="$probe_root/$label.log"
    XDG_CONFIG_HOME="$cfg" XDG_STATE_HOME="$cfg" XDG_RUNTIME_DIR="$probe_root/runtime-$label" \
        WAYLAND_DISPLAY="$wayland_socket" QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=wayland \
        QT_NO_XDG_DESKTOP_PORTAL=1 qs -p "$project/probe-notification-stack.qml" --no-color >"$log" 2>&1 &
    probe_pid=$!
    for _ in $(seq 1 40); do
        gdbus introspect --session --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications >/dev/null 2>&1 && break
        sleep .25
    done
    gdbus introspect --session --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications >/dev/null
    if [ "$action" = timeout ]; then
        first_id=$(notify-send --print-id --expire-time=1200 First)
        sleep .4
        second_id=$(notify-send --print-id --expire-time=0 Second)
        sleep .4
        third_id=$(notify-send --print-id --expire-time=0 Third)
        sleep 2.5
    else
        first_id=$(notify-send --print-id --expire-time=0 First "$(printf 'long body line %s\n' {1..10})")
        sleep .6
        second_id=$(notify-send --print-id --expire-time=0 Second)
        sleep 3.5
    fi
    _probe_stop "$probe_pid"
    probe_pid=""
    if grep -q 'PROBE-FAIL' "$log" || [ -n "$(_probe_errors "$log")" ]; then
        cat "$log" >&2
        echo "FAIL: notification stack height probe runtime error ($label)" >&2
        return 1
    fi
    LOG="$log" ACTION="$action" FIRST="${first_id#* }" SECOND="${second_id#* }" THIRD="${third_id#* }" python3 - <<'PY'
import os
import re

events = []
expand_at = None
for line in open(os.environ["LOG"]):
    match = re.search(r"STACK-PROBE ([yh]) t=(\d+) id=(\d+) [yh]=([-0-9.eE]+)", line)
    if match:
        events.append((match.group(1), int(match.group(2)), match.group(3), float(match.group(4))))
    match = re.search(r"STACK-PROBE expand t=(\d+)", line)
    if match:
        expand_at = int(match.group(1))
first, second = os.environ["FIRST"], os.environ["SECOND"]
third = os.environ["THIRD"]
action = os.environ["ACTION"]
first_heights = [(time, value) for kind, time, ident, value in events if kind == "h" and ident == first]
second_y = [(time, value) for kind, time, ident, value in events if kind == "y" and ident == second]
if action == "timeout":
    peak_index = max(range(len(first_heights)), key=lambda index: first_heights[index][1])
    height_window = first_heights[peak_index + 1:]
else:
    if expand_at is None:
        raise SystemExit("FAIL: expansion action did not run")
    height_window = [(time, value) for time, value in first_heights if time >= expand_at]
if len(height_window) < 3:
    raise SystemExit(f"FAIL: {action} did not animate card height")
start, end = height_window[0][0], height_window[-1][0]
frame_lag = 20

def tracks_height(time, value):
    # QML can emit the lower slot's y before the next height signal in the
    # same frame, so compare against every nearby upper-height sample.
    return any(abs(height_time - time) <= frame_lag and abs(height - value) <= 1
               for height_time, height in height_window)

lockstep = []
for time, value in second_y:
    if time < start or time > end + frame_lag:
        continue
    if tracks_height(time, value):
        lockstep.append((time, value))
if len(lockstep) < 3:
    raise SystemExit(f"FAIL: {action} lower card stalled during height animation ({len(lockstep)} lockstep samples)")
material_heights = [height_window[0]]
for sample in height_window[1:]:
    if abs(sample[1] - material_heights[-1][1]) > 0.1:
        material_heights.append(sample)
uncovered = [sample for sample in material_heights
             if not any(abs(time - sample[0]) <= frame_lag and abs(value - sample[1]) <= 1
                        for time, value in second_y)]
if uncovered:
    raise SystemExit(f"FAIL: {action} lower card missed height frames: {uncovered[:3]}")
if lockstep[0][0] > start + frame_lag:
    raise SystemExit(f"FAIL: {action} lower card started after the height animation")
if abs(lockstep[-1][1] - height_window[-1][1]) > 0.1:
    raise SystemExit(f"FAIL: {action} lower card missed final height")
tail = [(time, value) for time, value in second_y
        if time > end + frame_lag and abs(value - height_window[-1][1]) > 0.1]
if tail:
    raise SystemExit(f"FAIL: {action} lower card moved after height settled: {tail}")
if action == "timeout":
    reveal = [int(match.group(1)) for line in open(os.environ["LOG"])
              if (match := re.search(rf"STACK-PROBE visible t=(\d+) id={third} value=true", line))]
    if len(reveal) != 1:
        raise SystemExit(f"FAIL: expected one retained third-card reveal: {reveal}")
    third_before = [value for kind, time, ident, value in events
                    if kind == "y" and ident == third and time < reveal[0]]
    third_after = [value for kind, time, ident, value in events
                   if kind == "y" and ident == third and time >= reveal[0]]
    if third_before or len(third_after) != 1 or third_after[0] <= 0:
        raise SystemExit(f"FAIL: retained third card did not snap on reveal: {third_before}, {third_after}")
    second_zero = [time for time, value in second_y if abs(value) <= 0.1]
    if not second_zero or second_zero[0] > reveal[0] + frame_lag:
        raise SystemExit("FAIL: second card had not settled before retained third revealed")
print(f"notification stack {action} passed ({len(lockstep)} lockstep samples)")
PY
}

run_mode child-behavior false false child-behavior
run_mode normal false false move
run_mode reduce-motion true false move
run_mode idle false true move
run_mode showall-shrink false false move showall
run_height_mode body-expansion expand
run_height_mode timeout-collapse timeout
legacy_log="$probe_root/legacy-column-move-red.result"
legacy_status=0
run_height_mode legacy-column-move-red expand column-move >"$legacy_log" 2>&1 || legacy_status=$?
if [ "$legacy_status" -eq 0 ]; then
    echo "FAIL: legacy Column.move unexpectedly tracked height relayout" >&2
    exit 1
elif ! grep -Fqx 'FAIL: expand lower card stalled during height animation (0 lockstep samples)' "$legacy_log"; then
    cat "$legacy_log" >&2
    echo "FAIL: legacy Column.move did not fail its expected geometry assertion" >&2
    exit 1
else
    echo "notification stack Column.move height red demonstrated"
fi
