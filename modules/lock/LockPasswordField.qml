pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../services"
import "../common"

// The lock's one input, under the user's name. Each output draws its own field, but they
// all edit LockState's one buffer, so the text follows whichever output the keyboard happens
// to land on. The item's bottom edge is the field's; the message line hangs below it in the
// lock's margin, so a message never moves the field.
Item {
    id: root

    // the field never waits for the font to settle, as the clock does: it is the one thing that
    // must work at once, so it starts in the default face and takes the chosen one when known
    readonly property string family: LockState.fontFamily.length > 0
        ? LockState.fontFamily : LockState.defaultFamily
    // the text's inset from the field's edge, which the name above lines up with
    readonly property int textInset: 16
    readonly property int textSize: LockState.px(15)

    readonly property bool _error: LockState.messageIsError && LockState.typed.length === 0
        && !LockState.checking

    implicitHeight: _field.y + _field.height

    Component.onCompleted: LockState.fieldCount++
    Component.onDestruction: LockState.fieldCount--

    function claimFocus(): void {
        _input.forceActiveFocus()
    }

    ShellText {
        id: _name
        x: root.textInset
        anchors.bottom: _field.top
        anchors.bottomMargin: LockState.px(12)
        width: Math.max(0, root.width - root.textInset * 2)
        elide: Text.ElideRight
        text: String(Quickshell.env("USER") || "")
        color: Theme.subtext
        font.family: root.family
        font.pixelSize: LockState.px(13)
    }

    Rectangle {
        id: _field
        y: _name.implicitHeight + LockState.px(12)
        width: parent.width
        height: Metrics.rowHeightFor(48)
        radius: Theme.radiusControl
        antialiasing: true
        color: root._error
            ? Theme.withAlpha(Theme.mix(Theme.background, Theme.error, 0.12), 0.55)
            : Theme.withAlpha(Theme.background, 0.55)
        ColorFade on color {}

        transform: Translate { id: _shift }

        OutlineBorder {
            radius: _field.radius
            outlineColor: root._error ? Theme.withAlpha(Theme.error, Theme.focusRingSoftAlpha)
                : _input.activeFocus && !LockState.checking
                    ? Theme.withAlpha(Theme.accent, Theme.focusRingSoftAlpha)
                : Theme.menuControlLine
            ColorFade on outlineColor {}
        }

        TextInput {
            id: _input
            anchors.left: parent.left; anchors.leftMargin: root.textInset
            anchors.right: _trail.left; anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            focus: true
            readOnly: LockState.checking || LockState.unlocking
            // a module's visible prompt (a username, a code) shows what is typed
            echoMode: LockState.promptVisible ? TextInput.Normal : TextInput.Password
            passwordCharacter: "•"
            // a platform or touch profile can default this above 0, which shows each typed
            // character in clear for a moment
            passwordMaskDelay: 0
            // echoMode alone leaves inputMethodHints at 0: an IME would still predict and
            // capitalise a case-sensitive password
            inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                | Qt.ImhNoAutoUppercase
            color: LockState.checking ? Theme.subtext : Theme.text
            selectionColor: Theme.withAlpha(Theme.accent, 0.4)
            font.family: root.family
            font.pixelSize: root.textSize
            // the dots run together at the field's size without it
            font.letterSpacing: _input.text.length > 0 && _input.echoMode === TextInput.Password
                ? 0.18 * root.textSize : 0
            clip: true
            Accessible.name: LockState.prompting ? LockState.prompt : "Password"

            // A binding on text would be rewritten by the user's own edits on this output, so
            // the shared buffer is pushed in by hand and each edit pushed back out
            Component.onCompleted: _input.text = LockState.typed
            onTextEdited: LockState.typed = _input.text
            onAccepted: LockState.submit()

            // the state behind the chip changes only on this key, so the press is the cue to
            // ask again; the event carries on to the field untouched
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_CapsLock) LockState.refreshCapsLock()
            }

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
                elide: Text.ElideRight
                // a module's own question replaces the generic label while it waits
                text: LockState.prompting && LockState.prompt.length > 0 ? LockState.prompt : "Password"
                color: Theme.withAlpha(Theme.subtext, 0.45)
                font.family: root.family
                font.pixelSize: root.textSize
            }
        }

        // whatever sits at the field's right end: the Caps Lock chip, or the check in progress.
        // The chip carries its own padding; the bare dots take the text's inset instead, so
        // they sit as far from the right edge as the text does from the left
        Item {
            id: _trail
            anchors.right: parent.right; anchors.rightMargin: _dots.visible ? root.textInset : 10
            anchors.verticalCenter: parent.verticalCenter
            width: _caps.visible ? _caps.width : _dots.visible ? _dots.width : 0
            height: _field.height

            Rectangle {
                id: _caps
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: LockState.capsLock && !LockState.checking
                width: Math.ceil(_capsText.implicitWidth) + 20
                height: Metrics.rowHeightFor(26)
                radius: Theme.radiusField
                antialiasing: true
                color: Theme.withAlpha(Theme.warning, 0.18)

                ShellText {
                    id: _capsText
                    anchors.centerIn: parent
                    text: "Caps Lock"
                    color: Theme.warning
                    font.family: root.family
                    font.pixelSize: LockState.px(12)
                }
            }

            Row {
                id: _dots
                // steps rather than eases, so it reads as waiting, not as progress
                property int lit: 0

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: LockState.checking
                spacing: 4

                Timer {
                    interval: 200
                    repeat: true
                    running: _dots.visible && !ShellSettings.reduceMotion
                    onTriggered: _dots.lit = (_dots.lit + 1) % 3
                    onRunningChanged: _dots.lit = 0
                }

                Repeater {
                    model: 3
                    Rectangle {
                        id: _dot
                        required property int index
                        width: 5
                        height: 5
                        radius: width / 2
                        antialiasing: true
                        color: _dot.index === _dots.lit ? Theme.accent : Theme.withAlpha(Theme.accent, 0.3)
                    }
                }
            }
        }
    }

    // a short no, from the field alone: the name and the message stay where they are
    SequentialAnimation {
        id: _shake
        NumberAnimation { target: _shift; property: "x"; to: -9; duration: Motion.ms(72); easing.type: Easing.OutQuad }
        NumberAnimation { target: _shift; property: "x"; to: 7; duration: Motion.ms(72); easing.type: Easing.InOutQuad }
        NumberAnimation { target: _shift; property: "x"; to: -5; duration: Motion.ms(72); easing.type: Easing.InOutQuad }
        NumberAnimation { target: _shift; property: "x"; to: 3; duration: Motion.ms(72); easing.type: Easing.InOutQuad }
        NumberAnimation { target: _shift; property: "x"; to: 0; duration: Motion.ms(72); easing.type: Easing.OutCubic }
    }

    Connections {
        target: LockState
        function onRejected() {
            _shake.stop()
            _shift.x = 0
            if (root.visible && !ShellSettings.reduceMotion && !Idle.isIdle) _shake.start()
        }
    }

    // hangs in the margin under the field, so a message never moves the field
    ShellText {
        id: _message

        // a module's own words outrank the generic "Checking…" while it talks
        readonly property bool _generic: LockState.checking && LockState.message.length === 0

        anchors.top: _field.bottom; anchors.topMargin: LockState.px(10)
        x: root.textInset
        width: Math.max(0, root.width - root.textInset * 2)
        // a PAM module's text can carry newlines; more than one line would run off the output
        maximumLineCount: 1
        elide: Text.ElideRight
        text: _message._generic ? "Checking…" : LockState.message
        color: LockState.messageIsError && !_message._generic ? Theme.error : Theme.subtext
        font.family: root.family
        font.pixelSize: LockState.px(12)
    }
}
