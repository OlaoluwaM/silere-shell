#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
if [[ "${1:-}" != "--private-bus" ]]; then
    _probe_private_bus "$0" "$@"
fi
shift
_probe_require_qs

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-audio-switch.XXXXXX")"
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    # Probe data must also clean up when the recoverable-delete directory is unavailable.
    if command -v rip >/dev/null 2>&1 && rip -f "$probe_root" >/dev/null 2>&1; then
        return
    fi
    rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM
mkdir -p "$probe_root/project/services" "$probe_root/project/fake-pipewire" "$probe_root/runtime" "$probe_root/bin"
chmod 0700 "$probe_root/runtime"
cp scripts/probe-audio-switch.qml "$probe_root/project/"
# Only the PipeWire type/import seam changes. The two services and their process
# handling run as shipped, without loading the host's PipeWire module.
cp "${SILERE_AUDIO_SWITCH_SOURCE:-$ROOT/services}/Audio.qml" "$probe_root/project/services/Audio.qml"
cp "${SILERE_AUDIO_SWITCH_SOURCE:-$ROOT/services}/AudioMode.qml" "$probe_root/project/services/AudioMode.qml"
sed -i -e 's|import Quickshell.Services.Pipewire|import "../fake-pipewire"|' \
    -e 's/readonly property PwNodeAudio/readonly property var/' \
    -e 's/readonly property PwNode /readonly property var /' "$probe_root/project/services/Audio.qml"
cp services/BoundedProcess.qml services/SafeText.qml "$probe_root/project/services/"
cat > "$probe_root/project/services/qmldir" <<'QML'
singleton Audio Audio.qml
singleton AudioMode AudioMode.qml
singleton SafeText SafeText.qml
singleton SystemTools SystemTools.qml
singleton MenuState MenuState.qml
BoundedProcess BoundedProcess.qml
QML
cat > "$probe_root/project/services/SystemTools.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
    property bool hasWpctl: true
    readonly property bool hasPwDump: false
    property int scanRevision: 0
}
QML
cat > "$probe_root/project/services/MenuState.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject { property bool soundSectionActive: false }
QML
cat > "$probe_root/project/fake-pipewire/qmldir" <<'QML'
singleton Pipewire Pipewire.qml
singleton PwNodeType PwNodeType.qml
PwObjectTracker PwObjectTracker.qml
QML
cat > "$probe_root/project/fake-pipewire/Pipewire.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
    property bool ready: true
    property var defaultAudioSink: null
    property var defaultAudioSource: null
    property var preferredDefaultAudioSink: null
    property var preferredDefaultAudioSource: null
    property var nodes: ({ values: [] })
}
QML
cat > "$probe_root/project/fake-pipewire/PwNodeType.qml" <<'QML'
pragma Singleton
import QtQuick
QtObject {
    enum Types { AudioSource = 1, AudioInStream = 2 }
}
QML
cat > "$probe_root/project/fake-pipewire/PwObjectTracker.qml" <<'QML'
import QtQuick
QtObject { property var objects: [] }
QML
cat > "$probe_root/bin/wpctl" <<'SH'
#!/usr/bin/env bash
set -eu
printf '%s\n' "$*" >> "$SILERE_AUDIO_SWITCH_ROOT/calls"
case "$1" in
    set-profile)
        while [ ! -e "$SILERE_AUDIO_SWITCH_ROOT/release" ]; do sleep 0.02; done
        [ "$3" != 9 ]
        ;;
    set-volume) exit 0 ;;
    *) exit 1 ;;
esac
SH
chmod +x "$probe_root/bin/wpctl"
PATH="$probe_root/bin:$PATH" SILERE_AUDIO_SWITCH_ROOT="$probe_root" \
    XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" XDG_CACHE_HOME="$probe_root/cache" \
    XDG_RUNTIME_DIR="$probe_root/runtime" QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    QT_NO_XDG_DESKTOP_PORTAL=1 setsid qs -p "$probe_root/project/probe-audio-switch.qml" --no-color >"$probe_root/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$probe_root/probe.log" "$probe_pid" 'PROBE-AUDIO-SWITCH' 100 0.25 || true
errs="$(_probe_errors "$probe_root/probe.log")"
if ! grep -q 'PROBE-AUDIO-SWITCH passed' "$probe_root/probe.log" \
        || grep -q 'PROBE-FAIL' "$probe_root/probe.log" || [ -n "$errs" ]; then
    cat "$probe_root/probe.log" >&2
    echo 'FAIL: audio switch probe failed or logged a runtime error' >&2
    exit 1
fi
if [ "$(cat "$probe_root/calls" 2>/dev/null)" != $'set-profile 12 2\nset-profile 12 2\nset-profile 12 9\nset-profile 12 2' ]; then
    cat "$probe_root/probe.log" "$probe_root/calls" 2>/dev/null >&2
    echo 'FAIL: unexpected wpctl calls, including a possible stale microphone write' >&2
    exit 1
fi
echo 'PROBE-AUDIO-SWITCH passed'
