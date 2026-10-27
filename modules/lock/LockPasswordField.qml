import QtQuick
import "../../config"
import "../common"

// The lock's one input. Each output draws its own field, but they all edit LockState's one
// buffer, so the text follows whichever output the keyboard happens to land on.
Item {
    id: root

    implicitHeight: _field.height

    Component.onCompleted: LockState.fieldCount++
    Component.onDestruction: LockState.fieldCount--

    Rectangle {
        id: _field
        width: parent.width
        height: Metrics.rowHeightFor(48)
        radius: Theme.radiusField
        antialiasing: true
        color: Theme.menuControl

        OutlineBorder {
            radius: _field.radius
            outlineColor: LockState.messageIsError ? Theme.withAlpha(Theme.error, 0.5)
                : _input.activeFocus ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
                : Theme.menuControlLine
            ColorFade on outlineColor {}
        }

        TextInput {
            id: _input
            anchors.left: parent.left; anchors.leftMargin: 16
            anchors.right: parent.right; anchors.rightMargin: 16
            anchors.verticalCenter: parent.verticalCenter
            focus: true
            readOnly: LockState.checking || LockState.unlocking
            echoMode: TextInput.Password
            passwordCharacter: "•"
            // echoMode alone leaves inputMethodHints at 0: an IME would still predict and
            // capitalise a case-sensitive password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                | Qt.ImhNoAutoUppercase
            color: Theme.text
            selectionColor: Theme.withAlpha(Theme.accent, 0.4)
            font.family: Settings.font; font.pixelSize: Settings.fontSize
            clip: true
            Accessible.name: "Password"

            // A binding on text would be rewritten by the user's own edits on this output, so
            // the shared buffer is pushed in by hand and each edit pushed back out
            Component.onCompleted: _input.text = LockState.typed
            onTextEdited: LockState.typed = _input.text
            onAccepted: LockState.submit()

            Connections {
                target: LockState
                function onTypedChanged() {
                    if (_input.text !== LockState.typed) _input.text = LockState.typed
                }
            }

            ShellText {
                anchors.fill: parent
                verticalAlignment: Text.AlignVCenter
                visible: _input.text.length === 0
                text: "Password"
                color: Theme.withAlpha(Theme.subtext, 0.45)
                font.pixelSize: Settings.fontSize
            }
        }
    }

    // hangs in the margin under the field, so a message never moves the field
    ShellText {
        id: _message

        // a module's own words outrank the generic "Checking…" while it talks
        readonly property bool _generic: LockState.checking && LockState.message.length === 0

        anchors.top: _field.bottom; anchors.topMargin: 8
        anchors.left: parent.left; anchors.leftMargin: 16
        width: Math.max(0, parent.width - 32)
        // a PAM module's text can carry newlines; more than one line would run off the output
        maximumLineCount: 1
        elide: Text.ElideRight
        text: _message._generic ? "Checking…" : LockState.message
        color: LockState.messageIsError && !_message._generic ? Theme.error : Theme.subtext
        font.pixelSize: Settings.fontLabel
    }
}
