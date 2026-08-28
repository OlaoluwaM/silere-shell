import QtQuick
import "../../../config"

// the shared arm-to-confirm machine behind every "tap once to arm, tap again
// to confirm" row in the menu: a key identifies what's armed (empty means
// nothing is), a timer disarms it if the second tap never comes, and
// tryConfirm rejects a same-tap double-fire (TapHandler fires once per tap,
// so a double-click would arm and confirm in one gesture) via
// Metrics.confirmGuardMs. Sites own everything past that: which key to pass,
// what else should disarm it (list close, connection drop, ...), and how the
// armed state renders.
QtObject {
    id: root

    property string key: ""
    readonly property bool armed: root.key !== ""
    property real armedAtMs: 0
    property int interval: 3000

    readonly property Timer _disarmTimer: Timer {
        interval: root.interval
        onTriggered: root.disarm()
    }

    function arm(key: string): void {
        root.key = key
        root.armedAtMs = Date.now()
        root._disarmTimer.restart()
    }

    function disarm(): void {
        root.key = ""
        root._disarmTimer.stop()
    }

    // first call for a key arms it; a repeat call for the same key inside the
    // guard window is the double-click half and is ignored; any later repeat
    // confirms and disarms
    function tryConfirm(key: string): bool {
        if (root.key !== key) {
            root.arm(key)
            return false
        }
        if (Date.now() - root.armedAtMs < Metrics.confirmGuardMs) return false
        root.disarm()
        return true
    }
}
