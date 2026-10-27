pragma ComponentBehavior: Bound

import QtQuick
import "../../config"
import "../../services"
import "../common"
import "../power"

// The lock's power card, centred over a scrim: first the three actions, then for Reboot and
// Power off the countdown in the desktop card's own body, so the two look the same. A tap
// outside closes it as Esc does; LockContent owns the keys.
Item {
    id: root

    // a tile per action: glyph over label, on the shell's button wash
    component Tile: ButtonBase {
        id: _tile

        required property string kind
        readonly property var _action: LockPower.actions[_tile.kind]

        glyph: _tile._action.glyph
        accessibleName: _tile._action.label
        implicitHeight: Metrics.rowHeightFor(76)
        onTriggered: LockPower.pick(_tile.kind)

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusControl
            antialiasing: true
            color: Theme.buttonFill(_tile.accentColor, _tile.hovered, _tile.pressed)
            ColorFade on color {}

            OutlineBorder {
                radius: parent.radius
                outlineColor: Theme.buttonLine(_tile.accentColor, _tile.hovered, _tile.pressed)
                ColorFade on outlineColor {}
            }
        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            ShellText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: _tile.glyph
                color: _tile.hovered ? Theme.mix(Theme.text, _tile.accentColor, 0.22) : Theme.text
                font.pixelSize: Settings.fontSize + 4
                ColorFade on color {}
            }
            ShellText {
                anchors.horizontalCenter: parent.horizontalCenter
                text: _tile._action.label
                color: Theme.text
                font.pixelSize: Settings.fontLabel
            }
        }
    }

    // off on the outputs that show the clock alone
    property bool wanted: true

    visible: root.wanted && (LockPower.open || _card.opacity > 0)

    Rectangle {
        anchors.fill: parent
        color: Theme.withAlpha(Theme.depthSink, 0.45)
        opacity: LockPower.open ? 1 : 0
        MotionBehavior on opacity { NumberAnimation { duration: Motion.normal } }
    }

    TapHandler {
        id: _outside
        enabled: LockPower.open
        onTapped: {
            const p = _outside.point.position
            if (p.x < _card.x || p.x > _card.x + _card.width
                    || p.y < _card.y || p.y > _card.y + _card.height)
                LockPower.dismiss()
        }
    }

    PopupShadow { card: _card }

    FloatingPopupCard {
        id: _card

        win: root
        open: LockPower.open
        anchorX: root.width / 2
        barBottom: false
        centered: true
        animatePlacement: false

        readonly property int pad: 16
        readonly property var action: LockPower.action
        readonly property bool _menu: LockPower.stage === "menu"
        property real progress: 1.0

        width: Math.round(Math.max(260, Math.min(340, root.width - 96)))
        height: Math.round((_card._menu ? _menuBody.implicitHeight : _body.implicitHeight) + _card.pad * 2)
        radius: Theme.radiusPanel

        Accessible.role: Accessible.AlertMessage
        Accessible.name: _card._menu ? "Power" : _body.title
        Accessible.description: _card._menu ? "" : _body.message

        // the duration is the countdown itself, which Motion must not scale or the bar would lie
        NumberAnimation {
            id: _drain
            target: _card
            property: "progress"
            to: 0.0
            easing.type: Easing.Linear
        }

        function _startDrain(): void {
            _drain.stop()
            const total = LockPower.seconds * 1000
            const left = Math.max(0, Math.min(total, LockPower.deadline - Date.now()))
            _card.progress = left / total
            if (ShellSettings.reduceMotion || left <= 0) return
            _drain.from = _card.progress
            _drain.duration = left
            _drain.start()
        }

        Connections {
            target: LockPower
            function onStarted() { _card._startDrain() }
            // the bar holds where it stopped once the countdown ends, either way
            function onStageChanged() { if (LockPower.stage !== "countdown") _drain.stop() }
            // without the drain the bar steps with the seconds instead
            function onRemainingChanged() {
                if (ShellSettings.reduceMotion)
                    _card.progress = LockPower.remaining / LockPower.seconds
            }
        }

        Column {
            id: _menuBody
            x: _card.pad
            y: _card.pad
            width: _card.width - _card.pad * 2
            visible: _card._menu
            spacing: 12

            ShellText {
                text: "Power"
                color: Theme.text
                font.pixelSize: Settings.fontSize
                font.weight: Font.DemiBold
            }

            Row {
                id: _tiles
                width: parent.width
                spacing: 8

                readonly property real _tileWidth: (_tiles.width - _tiles.spacing * 2) / 3

                Tile { kind: "suspend"; width: _tiles._tileWidth }
                Tile { kind: "reboot"; width: _tiles._tileWidth }
                Tile { kind: "poweroff"; width: _tiles._tileWidth }
            }
        }

        PowerCountdownBody {
            id: _body
            x: _card.pad
            y: _card.pad
            width: _card.width - _card.pad * 2
            visible: !_card._menu
            // nothing to take back once the command runs, and a second run would race the first
            enabled: LockPower.stage !== "running"

            readonly property bool _failed: LockPower.stage === "failed"
            readonly property bool _counting: LockPower.stage === "countdown"

            glyph: _card.action ? _card.action.glyph : ""
            title: !_card.action ? "" : _body._failed ? _card.action.failTitle : _card.action.label
            message: !_card.action ? ""
                : _body._failed ? "It may require authorization or be blocked by a running task."
                : _body._counting ? _card.action.phrase + " in " + LockPower.remaining
                    + (LockPower.remaining === 1 ? " second." : " seconds.")
                : _card.action.phrase + "…"
            progress: _body._counting ? _card.progress : 0
            confirmLabel: _body._failed ? "Try again" : _card.action ? _card.action.label : ""
            onCancelled: LockPower.dismiss()
            onConfirmed: {
                if (_body._failed) LockPower.retry()
                else LockPower.confirm()
            }
        }
    }
}
