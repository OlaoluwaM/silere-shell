import QtQuick
import "../../config"

// Everything a lock surface draws over its background colour. The preview window draws this
// same item, so the dev loop iterates on what locks. Not pixel for pixel: QsWindow is null on
// a lock surface, so OutlineBorder snaps the field's stroke there as if at scale 1.
Item {
    id: root

    // the unlock waits for this fade, so the desktop never shows through half-drawn content
    opacity: LockState.unlocking ? 0 : 1
    MotionBehavior on opacity { NumberAnimation { duration: Motion.popOutFade } }

    LockPasswordField {
        anchors.left: parent.left; anchors.leftMargin: 48
        anchors.bottom: parent.bottom; anchors.bottomMargin: 48
        width: Math.max(0, Math.min(320, parent.width - 96))
    }
}
