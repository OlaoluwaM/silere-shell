import QtQuick
import "../../config"

// Everything a lock surface draws over its background colour. The preview window draws this
// same item, so the dev loop iterates on what locks.
//
// One output, the one the keyboard is on, gets the whole lock; the others show the clock
// alone. Every output keeps its field, hidden where it is not the primary, so a surface that
// takes the keyboard can show it the moment it claims the primary.
Item {
    id: root

    property string outputName: ""
    // the preview's one window is always the primary
    property bool previewWindow: false

    readonly property bool primary: root.previewWindow
        || (root.outputName.length > 0 && LockState.primaryOutput === root.outputName)

    // the design's corner margin; the type grows with uiScale, the frame stays put
    readonly property int edge: 80
    // where the clock's digit ink starts, as the mockup draws it in JetBrains Mono
    readonly property int inkTop: 82

    // the unlock waits for this fade, so the desktop never shows through half-drawn content
    opacity: LockState.unlocking ? 0 : 1
    MotionBehavior on opacity { NumberAnimation { duration: Motion.popOutFade } }

    // a surface whose window takes the keyboard (at start, after resume, after hotplug) is
    // where typing lands, so it takes the field and the field takes the keys
    readonly property bool _windowActive: Window.active
    on_WindowActiveChanged: {
        if (!root._windowActive) return
        LockState.claimOutput(root.outputName)
        LockState.refreshCapsLock()
        _field.claimFocus()
    }
    onPrimaryChanged: if (root.primary) _field.claimFocus()
    Component.onCompleted: if (root.primary) _field.claimFocus()

    LockBackground {
        anchors.fill: parent
        outputName: root.outputName
    }

    LockClock {
        x: root.edge
        y: root.inkTop
        showDate: root.primary
    }

    LockBattery {
        anchors.right: parent.right
        anchors.rightMargin: root.edge
        y: root.inkTop
        wanted: root.primary
    }

    LockPasswordField {
        id: _field
        // the mockup sets the field a little in from the clock's box
        x: 86
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root.edge
        width: Math.max(0, Math.min(LockState.px(380), parent.width - 2 * x))
        visible: root.primary
    }

    // the field's own Enter submits; Esc has to work wherever the keyboard is in the window
    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: LockState.cancel()
    }
}
