pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"

PanelWindow {
    id: osd

    required property ShellScreen targetScreen

    screen:         targetScreen
    color:          "transparent"
    exclusiveZone:  -1
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "silere-osd"

    implicitHeight: Math.max(150, Math.ceil((stack.implicitHeight + 24) / 64) * 64)

    readonly property bool _active: !ShellSettings.osdBarIntegrated || OsdBarState.barConcealed

    // bar at the bottom: clear its full footprint plus a bit of air; otherwise a
    // comfortable lift off the screen edge rather than sitting flush
    readonly property real _edgeY: Metrics.barAtBottom
        ? Metrics.popupClearance(18)
        : Math.max(24, Metrics.barEdgeInset + 16)

    anchors {
        top:    false
        bottom: true
        left:   true
        right:  true
    }

    margins.bottom: osd._edgeY
    mask: Region {}

    visible: osd._active && OsdBarState.activeCount > 0

    Column {
        id: stack
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 6
        spacing: 6

        Repeater {
            model: osd._active ? OsdBarState.entries : null

            delegate: Item {
                id: card

                required property string kind
                required property string icon
                required property string label
                required property bool muted
                required property bool hasBar
                required property real clamped
                required property bool closing
                required property int serial
                required property var fillColor

                // a small deliberate step above the 36px bar so the card reads as its own
                // block without going chunky
                readonly property int cardH: ShellSettings.osdMatchBar ? Math.max(40, ShellSettings.barHeight) : 46
                readonly property int chromeW: hasBar ? 200 : 94
                // the percent readout counts digits up and down -- size the card for the
                // widest steady label ("100%"/"Muted") so it doesn't breathe at the rails;
                // a transient device-name label may still widen it, that's deliberate
                readonly property int cardW: Math.max(224, Math.min(440, chromeW + Math.max(
                    Math.ceil(_labelMetrics.advanceWidth),
                    Math.ceil(_maxPctMetrics.advanceWidth),
                    Math.ceil(tm.advanceWidth)) + 2))
                readonly property real cardRadius: ShellSettings.osdMatchBar
                    ? Math.min(ShellSettings.barRadius, cardH / 4)
                    : Math.min(Theme.radiusPanel, cardH / 4)
                readonly property real _hiddenSlide: 7

                property bool _ready: false
                property real _op: 0
                property real _slide: _hiddenSlide

                width: cardW
                height: 0
                visible: osd._active && (_ready || _op > 0.001 || height > 0.5)
                z: serial

                Component.onCompleted: _ready = true

                TextMetrics {
                    id: _labelMetrics
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize
                    text: card.label
                }

                TextMetrics {
                    id: _maxPctMetrics
                    font.family:    Settings.font
                    font.pixelSize: Settings.fontSize
                    text: "100%"
                }

                states: [
                    State {
                        name: "hidden"
                        when: !card._ready || card.closing
                        PropertyChanges { card.height: 0; card._op: 0; card._slide: card._hiddenSlide }
                    },
                    State {
                        name: "visible"
                        when: card._ready && !card.closing
                        PropertyChanges { card.height: card.cardH; card._op: 1.0; card._slide: 0 }
                    }
                ]

                transitions: [
                    Transition {
                        to: "visible"
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "height"; duration: Motion.ms(150); easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "_op";    duration: Motion.ms(105); easing.type: Easing.OutCubic }
                            NumberAnimation { target: card; property: "_slide"; duration: Motion.ms(165); easing.type: Easing.OutQuart }
                        }
                    },
                    Transition {
                        to: "hidden"
                        ParallelAnimation {
                            NumberAnimation { target: card; property: "_slide"; duration: Motion.ms(105); easing.type: Easing.InCubic }
                            NumberAnimation { target: card; property: "_op";    duration: Motion.ms(115); easing.type: Easing.InCubic }
                            NumberAnimation { target: card; property: "height"; duration: Motion.ms(165); easing.type: Easing.InCubic }
                        }
                    }
                ]

                MotionBehavior on width {
                    NumberAnimation { duration: Motion.ms(80); easing.type: Easing.OutCubic }
                }

                Item {
                    id: cardWrap
                    width: card.cardW
                    height: card.cardH
                    anchors.horizontalCenter: parent.horizontalCenter
                    opacity: card._op
                    transform: Translate { y: card._slide }

                    Loader {
                        active: ShellSettings.barShadow
                        anchors.fill: parent
                        sourceComponent: FloatingShadow {
                            radius: card.cardRadius
                            atBottom: true
                        }
                    }

                    Rectangle {
                        id: _osdCardFill
                        anchors.fill: parent
                        radius: card.cardRadius
                        antialiasing: true
                        // level cards pick up the same frosted glass as the popups now that
                        // this layer sits in the compositor's blur rule; alert cards stay on
                        // opaque surface deliberately — a warning shouldn't dissolve into the wallpaper
                        color: card.hasBar ? Theme.popup : Theme.surface

                        readonly property color _outlineColor: !card.hasBar
                            ? Theme.withAlpha(card.fillColor, 0.55)
                            : Theme.outline

                        OutlineBorder {
                            radius: _osdCardFill.radius
                            outlineColor: _osdCardFill._outlineColor
                            MotionBehavior on outlineColor {ColorAnimation { duration: Motion.medium } }
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 10

                            ShellText {
                                anchors.verticalCenter: parent.verticalCenter
                                width:               20
                                horizontalAlignment: Text.AlignHCenter
                                text:           card.icon
                                color:          card.hasBar ? Theme.text : card.fillColor
                                font.pixelSize: Settings.fontSize + 4
                                MotionBehavior on color {ColorAnimation { duration: Motion.medium } }
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                visible: card.hasBar
                                width:  96
                                height: 6
                                radius: 3
                                color:  Theme.menuTrack

                                Rectangle {
                                    id: _fill
                                    width: {
                                        const v = card.clamped
                                        return v <= 0 ? 0 : Math.max(parent.radius * 2, parent.width * v)
                                    }
                                    height: parent.height
                                    radius: parent.radius
                                    clip: true
                                    color: card.muted
                                        ? Theme.withAlpha(Theme.subtext, 0.58)
                                        : Theme.withAlpha(card.fillColor, 0.88)

                                    MotionBehavior on width {
                                        gate: !card.closing && !OsdBarState.rapid
                                        NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic }
                                    }
                                }
                            }

                            TextMetrics {
                                id: tm
                                font.family:    Settings.font
                                font.pixelSize: Settings.fontSize
                                text: "Muted"
                            }

                            ShellText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(Math.ceil(tm.advanceWidth),
                                    Math.min(Math.ceil(_labelMetrics.advanceWidth), card.cardW - card.chromeW)) + 2
                                horizontalAlignment: Text.AlignRight
                                elide:          Text.ElideRight
                                text:           card.label
                                // the glyph and rim carry the alert; a coloured readout only costs contrast
                                color:          card.muted
                                    ? Theme.withAlpha(Theme.subtext, 0.7)
                                    : Theme.text
                                font.pixelSize: Settings.fontSize

                                MotionBehavior on color {
                                    ColorAnimation { duration: Motion.medium }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
