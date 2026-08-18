pragma ComponentBehavior: Bound

import QtQuick
import Quickshell.Widgets
import "../../../config"
import "../../../services"
import "../../common"

ClippingRectangle {
    id: root
    width: parent ? parent.width : 0
    readonly property int _seekBlock: Media.hasPosition ? 26 : 0
    // A2 -- Dissolve: no separate footer surface anymore, so the old "16 top gap" constant
    // is gone. What's left is eyebrow-topMargin + eyebrow + the art's breathing room +
    // the text block + the seek gap + the transport row + its own bottom margin, each
    // matching the anchor margins used below -- a floor still guards the rare frame where
    // an implicit height is still settling (e.g. right at Component.onCompleted).
    readonly property int _artBreath: 76
    // 4px multiple: an odd height lands the bottom border on a half physical pixel and doubles it
    // _identityRow used to live inside _mediaCol's Column, which drops an invisible child's
    // contribution to implicitHeight for free; now that it's a top-anchored sibling instead,
    // this formula has to gate its own contribution the same way or a player with no MPRIS
    // identity (the row goes invisible) leaves dead space where the eyebrow would have sat
    height: 4 * Math.ceil(Math.max(220,
        (_identityRow.visible ? 12 + _identityRow.height : 0) + _artBreath + _mediaCol.implicitHeight + 12 + _seekBlock + _controlsRow.height + 14) / 4)
    radius: Theme.radiusCard
    color: Theme.menuCard
    opacity: Media.shown ? 1.0 : 0.0
    visible: opacity > 0.01

    // art-retry-on-reopen below needs to know when THIS card last became visible again --
    // MenuState.open used to double as that signal because the menu was the only host, but
    // modules/mediapopup/MediaPopupWindow.qml now hosts the same card off MediaPopupState
    // instead, so the host tells us here rather than the card assuming which singleton it is
    property bool hostOpen: MenuState.open

    function _focusPlayer(): void {
        // close BOTH possible hosts, not just the menu: when the popup hosts this card
        // and the player window is on the current workspace, no workspace switch fires
        // the hosts' workspace-activated auto-close, and the popup would sit with
        // exclusive keyboard focus over the window we just raised. Only one host is
        // ever open, so closing the other is a no-op.
        MenuState.close()
        MediaPopupState.close()
        HyprActions.focusMediaPlayer(Media.playerName, Media.title)
    }

    function settleMediaVisual(): void {
        _mediaCol.settleText()
        if (_artIn.running) _artIn.complete()
        if (_artInScale.running) _artInScale.complete()
        if (_artOut.running) _artOut.complete()
    }

    // compact rounded-rect stepper for the identity row's source switcher: sized down from
    // MediaButton's transport-row scale but sharing its hover/press language (fill + outline
    // + scale), so it still reads as the same control family instead of a plain flat toggle.
    // Idle fill is opaque (Theme.menuHint, the same chip tone the eyebrow label sits on)
    // rather than transparent -- it used to ride bare on the art like the scrim it sat
    // beside, and washed out the same way; it now wins over any cover for the same reason.
    component SourceStepButton: Item {
        id: _step
        property string glyph: ""
        signal triggered()

        implicitWidth: 20
        implicitHeight: 20
        width: implicitWidth
        height: implicitHeight

        HoverHandler { id: _stepHover; cursorShape: Qt.PointingHandCursor }
        TapHandler   { id: _stepTap; onTapped: _step.triggered() }

        readonly property real _scale: _stepTap.pressed ? Motion.pressScale
            : _stepHover.hovered ? Motion.hoverScale : 1.0

        Rectangle {
            id: _stepFill
            anchors.fill: parent
            radius: Theme.radiusInline
            antialiasing: true
            scale: _step._scale
            transformOrigin: Item.Center
            color: _stepTap.pressed ? Theme.controlFill(Theme.text, 0.14)
                : _stepHover.hovered ? Theme.controlFill(Theme.text, 0.09)
                : Theme.menuHint
            ColorFade on color {}
            MotionBehavior on scale {
                NumberAnimation {
                    duration: _stepTap.pressed ? Motion.press
                        : _stepHover.hovered ? Motion.hoverIn : Motion.hoverOut
                    easing.type: Easing.OutCubic
                }
            }

            // idle edge matches the eyebrow chip and the rail's tooltip pill
            // (Theme.menuCardBorder); hovering swaps to the hotter control-line tone
            OutlineBorder {
                radius: _stepFill.radius
                outlineWidth: 1
                outlineColor: _stepHover.hovered ? Theme.menuControlLineHot : Theme.menuCardBorder
                ColorFade on outlineColor {}
            }
        }

        ShellText {
            anchors.centerIn: parent
            text: _step.glyph
            color: _stepHover.hovered ? Theme.text : Theme.withAlpha(Theme.subtext, 0.68)
            font.pixelSize: Settings.fontLabel
            ColorFade on color {}
        }
    }

    OutlineBorder {
        // above the album art and its veil: both fill the card and are declared later
        z: 1
        radius: root.radius
        outlineWidth: 1
        outlineColor: Theme.menuCardBorder
    }

    // fade only: a scale leg ran as a third competing animation and resampled NativeRendering text off-pixel
    Disclosure on opacity { expanded: Media.shown; enterEasing: Easing.OutCubic }

    // on reappear, text may be stranded at opacity 0 by a crossfade interrupted while hidden
    Connections {
        target: Media
        function onShownChanged() {
            if (Media.shown) root.settleMediaVisual()
        }
    }
    Connections {
        target: ShellSettings
        function onReduceMotionChanged() {
            if (ShellSettings.reduceMotion) root.settleMediaVisual()
        }
    }

    Item {
        id: _art
        anchors.fill: parent
        // the veil below is transparent for its top third, so this ceiling is what stops
        // highlights punching through the eyebrow row sitting directly on raw art up there
        readonly property real maxAlpha: 0.64
        property bool _useA: true
        property string _curUrl: ""
        property var _pendingLayer: null
        readonly property real shownAlpha: Math.max(_artA.opacity, _artB.opacity)

        function _apply() {
            const url = Media.stableArtUrl
            if (url === _curUrl) return
            _curUrl = url
            _pendingLayer = null
            _artRetry.stop()
            if (!url || url.length === 0) {
                _artIn.stop(); _artInScale.stop(); _artOut.stop()
                _artA.opacity = 0; _artA.scale = 1.0; _artA.source = ""
                _artB.opacity = 0; _artB.scale = 1.0; _artB.source = ""
                return
            }
            const idle = _useA ? _artB : _artA
            _pendingLayer = idle
            // re-assigning an identical source is a no-op in Qt; clear first so an error retry reloads
            if (String(idle.source) === url) idle.source = ""
            idle.source = url
        }

        function _releaseLayer(img) {
            const current = _useA ? _artA : _artB
            if (!img || img === current || img === _pendingLayer) return
            img.opacity = 0
            img.scale = 1.0
            img.source = ""
        }

        property int _retries: 0
        Timer {
            id: _artRetry
            interval: 2500
            onTriggered: { if (!root.hostOpen) return; _art._curUrl = ""; _art._apply() }
        }
        function _failed(img) {
            if (img !== _pendingLayer) return
            _pendingLayer = null
            _curUrl = ""
            if (root.hostOpen && _retries < 3) { _retries++; _artRetry.restart() }
        }

        function _promote(img, isA) {
            // object identity, not URL compare, Qt normalises URLs (e.g. %20)
            if (img !== _pendingLayer || img.status !== Image.Ready) return
            _pendingLayer = null
            _artRetry.stop()
            _retries = 0
            _useA = isA
            const outgoing = isA ? _artB : _artA
            if (ShellSettings.reduceMotion) {
                img.scale = 1.0; img.opacity = maxAlpha; outgoing.opacity = 0
                _releaseLayer(outgoing)
                return
            }
            img.scale = 1.06
            _artIn.target = img;      _artIn.restart()
            _artInScale.target = img; _artInScale.restart()
            _artOut.target = outgoing; _artOut.to = 0; _artOut.restart()
        }

        Connections { target: Media; function onStableArtUrlChanged() { _art._retries = 0; _art._apply() } }
        Connections { target: root; function onHostOpenChanged() { if (root.hostOpen) { _art._retries = 0; _art._apply() } } }
        Component.onCompleted: _apply()

        Image {
            id: _artA
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // uncached: caching keeps every past track's 512² decode for the whole session
            cache: false
            sourceSize.width:  512
            sourceSize.height: 512
            opacity: 0
            visible: opacity > 0.01
            onStatusChanged: status === Image.Error ? _art._failed(_artA) : _art._promote(_artA, true)
        }
        Image {
            id: _artB
            anchors.fill: parent
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width:  512
            sourceSize.height: 512
            opacity: 0
            visible: opacity > 0.01
            onStatusChanged: status === Image.Error ? _art._failed(_artB) : _art._promote(_artB, false)
        }

        NumberAnimation { id: _artIn;      property: "opacity"; to: _art.maxAlpha; duration: Motion.ms(380); easing.type: Easing.OutCubic }
        NumberAnimation { id: _artInScale; property: "scale";   to: 1.0;           duration: Motion.ms(520); easing.type: Easing.OutCubic }
        NumberAnimation {
            id: _artOut
            property: "opacity"
            duration: Motion.ms(300)
            easing.type: Easing.OutCubic
            onFinished: _art._releaseLayer(_artOut.target)
        }
    }

    // A2 -- Dissolve: the old design darkened the WHOLE card with one flat scrim strong
    // enough to keep text legible, which made the transport row and the seek bar sit on a
    // half-dimmed cover instead of a real surface -- neither reads as fully "art" nor fully
    // "chrome". This one gradient replaces it: transparent where the art should just be
    // ambiance, dissolving into a solid floor where controls live, with no seam between an
    // "art zone" and a "footer zone" because there isn't a second surface underneath it.
    Rectangle {
        anchors.fill: parent
        visible: _art.shownAlpha > 0.01
        // the floor has to be the SAME opaque solid-on-glass tone RailNavItem's hover
        // tooltip uses (Theme.menuHint), not a translucent wash: a wash floor would let
        // the cover bleed through behind the seek bar and transport row exactly like the
        // old scrim did, and menuHint is already opaque in glass, non-glass, and HC (HC
        // forces _glass off in Theme, so it falls through to the same opaque menuCard mix)
        gradient: Gradient {
            GradientStop { position: 0.00; color: "transparent" }
            GradientStop { position: 0.34; color: "transparent" }
            GradientStop { position: 0.55; color: Theme.withAlpha(Theme.menuHint, 0.55) }
            GradientStop { position: 0.76; color: Theme.menuHint }
            GradientStop { position: 1.00; color: Theme.menuHint }
        }
    }

    // the veil above protects only the lower half, and the eyebrow row sits on raw art
    // above it -- this used to get its own scrim gradient to keep the micro label legible,
    // but a gradient strong enough for a bright cover washed out a dark one and vice versa:
    // it punished every cover to save the worst case. The eyebrow chip below wins over any
    // cover by being opaque instead, so there is nothing left for a scrim here to do.

    // covers only the art above the text block -- the eyebrow and the title/artist column
    // are declared after this MouseArea, so their own hit targets (the source-step buttons)
    // still win the tap; everywhere else in this band, clicking raises the player. Seek and
    // transport sit below _seek.top and were never part of this target.
    MouseArea {
        id: _playerTarget
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: _seek.top
        cursorShape: Qt.PointingHandCursor
        onClicked: root._focusPlayer()
    }

    // pinned to the card's top edge, over raw art (the veil is transparent up here) --
    // moved off its old mid-card spot so nothing textual competes with the title for the
    // gradient's half-tone band, and so the source stepper reads as chrome pinned to the
    // card frame rather than as part of the dissolving text block beneath it
    Item {
        id: _identityRow
        anchors {
            top: parent.top; topMargin: 12
            left: parent.left; leftMargin: 16
            right: parent.right; rightMargin: 16
        }
        readonly property int _chipHPad: 8
        readonly property int _chipVPad: 4
        // the taller of the chip (label + its own padding) and the stepper pair, so the
        // 20px buttons never get vertically clipped against the micro-sized label;
        // a hidden Row still reports its children's height, so gate it on visible
        // or a single-player card grows this row for buttons nobody can see
        height: Math.max(_identityChip.height, _sourceNav.visible ? _sourceNav.height : 0)
        visible: _mediaCol._shownIdentity.length > 0

        // opaque chip, not a scrim: worst-case-proof by construction instead of hoping a
        // gradient's alpha reads over whatever the current cover happens to be. Same
        // solid-on-glass tone the tray/tooltip chips use (Theme.menuHint) -- never a wash,
        // or the cover would bleed through exactly like the scrim it replaced.
        Rectangle {
            id: _identityChip
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            readonly property real _maxWidth: _sourceNav.visible
                ? parent.width - _sourceNav.width - 8 : parent.width
            width: Math.min(_identityText.implicitWidth + _identityRow._chipHPad * 2,
                Math.max(0, _identityChip._maxWidth))
            height: _identityText.implicitHeight + _identityRow._chipVPad * 2
            radius: Theme.radiusInline
            color: Theme.menuHint
            antialiasing: true

            OutlineBorder {
                radius: _identityChip.radius
                outlineWidth: 1
                outlineColor: Theme.menuCardBorder
            }

            ShellText {
                id: _identityText
                anchors.left: parent.left; anchors.leftMargin: _identityRow._chipHPad
                anchors.right: parent.right; anchors.rightMargin: _identityRow._chipHPad
                anchors.verticalCenter: parent.verticalCenter
                text: _mediaCol._shownIdentity.toUpperCase()
                color: Theme.withAlpha(Theme.text, 0.85)
                font.pixelSize: Settings.fontMicro
                font.weight: Font.Medium
                font.letterSpacing: 1.2
                elide: Text.ElideRight
            }
        }

        // only with more than one live player; each arrow steps and wraps through
        // Media.playerList and pins Media.preferredPlayer to the target's dbusName
        Row {
            id: _sourceNav
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            visible: Media.playerCount > 1
            spacing: 4

            SourceStepButton { glyph: "󰅁"; onTriggered: Media.cyclePlayer(-1) }
            SourceStepButton { glyph: "󰅂"; onTriggered: Media.cyclePlayer(1) }
        }
    }

    Column {
        id: _mediaCol
        anchors {
            left: parent.left; leftMargin: 16
            right: parent.right; rightMargin: 16
            bottom: _seek.top; bottomMargin: 12
        }
        spacing: 2
        opacity: 1.0

        property real _slide: 0
        transform: Translate { y: _mediaCol._slide }

        property string _shownIdentity: ""
        property string _shownTitle:    ""
        property string _shownArtist:   ""
        function settleText(): void {
            _textFade.stop()
            _shownIdentity = Media.identity
            _shownTitle = Media.title
            _shownArtist = Media.artist
            opacity = 1.0
            _slide = 0
        }
        Component.onCompleted: {
            _shownIdentity = Media.identity
            _shownTitle    = Media.title
            _shownArtist   = Media.artist
        }

        readonly property string trackKey: Media.identity + "\u0000" + Media.title + "\u0000" + Media.artist
        onTrackKeyChanged: {
            if (ShellSettings.reduceMotion || (_shownTitle === "" && _shownArtist === "")) {
                _mediaCol.settleText()
                return
            }
            _textFade.restart()
        }

        SequentialAnimation {
            id: _textFade
            NumberAnimation { target: _mediaCol; property: "opacity"; to: 0.0; duration: Motion.ms(110); easing.type: Easing.InCubic }
            ScriptAction {
                script: {
                    _mediaCol._shownIdentity = Media.identity
                    _mediaCol._shownTitle    = Media.title
                    _mediaCol._shownArtist   = Media.artist
                    _mediaCol._slide = 6
                }
            }
            ParallelAnimation {
                NumberAnimation { target: _mediaCol; property: "opacity"; to: 1.0; duration: Motion.ms(200); easing.type: Easing.OutCubic }
                NumberAnimation { target: _mediaCol; property: "_slide";  to: 0;   duration: Motion.ms(260); easing.type: Easing.OutCubic }
            }
        }

        ShellText {
            id: _titleText
            width: parent.width
            text: _mediaCol._shownTitle.length > 0 ? _mediaCol._shownTitle
                : _mediaCol._shownArtist.length > 0 ? _mediaCol._shownArtist
                : _mediaCol._shownIdentity.length > 0 ? _mediaCol._shownIdentity
                : "Media"
            color: Theme.text
            font.pixelSize: Settings.fontSize + 3
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Item { width: 1; height: 2; visible: _artistText.visible }

        ShellText {
            id: _artistText
            width: parent.width
            visible: _mediaCol._shownTitle.length > 0 && _mediaCol._shownArtist.length > 0
            text: _mediaCol._shownArtist
            color: Theme.withAlpha(Theme.subtext, 0.75)
            font.pixelSize: Settings.fontSize
            elide: Text.ElideRight
        }
    }

    Item {
        id: _seek
        visible: Media.hasPosition
        anchors {
            left:  parent.left;  leftMargin:  16
            right: parent.right; rightMargin: 16
            bottom: _controlsRow.top
            bottomMargin: visible ? 12 : 0
        }
        height: visible ? 14 : 0

        ShellText {
            id: _elapsedLabel
            width: _totalLabel.implicitWidth
            horizontalAlignment: Text.AlignRight
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text:           Media.formatTime(_seekTrack.dragging ? _seekTrack.shownValue * Media.length : Media.positionNow)
            color:          Theme.withAlpha(Theme.text, 0.62)
            font.pixelSize: Settings.fontMicro
        }
        ShellText {
            id: _totalLabel
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text:           Media.lengthKnown ? Media.formatTime(Media.length) : "LIVE"
            color:          Theme.withAlpha(Theme.text, 0.55)
            font.pixelSize: Settings.fontMicro
        }

        SliderTrack {
            id: _seekTrack
            visible: Media.lengthKnown
            anchors.left:  _elapsedLabel.right; anchors.leftMargin:  8
            anchors.right: _totalLabel.left;    anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            height: 12

            interactive: Media.canSeek && Media.lengthKnown
            showThumb:   Media.canSeek && Media.lengthKnown
            hoverGrow:   false
            animate:     false
            commitOnRelease: true
            trackColor:  Theme.withAlpha(Theme.text, 0.20)
            value: Media.positionRatio
            onChanged: value => { if (Media.canSeek) Media.seekToRatio(value) }
        }
    }

    Row {
        id: _controlsRow
        anchors {
            horizontalCenter: parent.horizontalCenter
            bottom: parent.bottom; bottomMargin: 14
        }
        spacing: 24

        MediaButton {
            glyph: "󰒮"
            glyphAlignReference: "󰒮"
            available: Media.canGoPrevious
            onTriggered: Media.previous()
        }

        Item {
            id: _playBtn
            readonly property bool _on: Media.canTogglePlaying
            width: 56; height: 40
            anchors.verticalCenter: parent.verticalCenter
            opacity: _playBtn._on ? 1.0 : 0.25
            MotionBehavior on opacity {
                NumberAnimation { duration: Motion.fast }
            }

            HoverHandler { id: _playH; enabled: _playBtn._on; cursorShape: Qt.PointingHandCursor }
            TapHandler   { id: _playT; enabled: _playBtn._on; onTapped: Media.togglePlay() }

            Rectangle {
                id: _playFill
                anchors.fill: parent
                radius: Theme.radiusControl
                antialiasing: true
                // press-only feedback by request: the hover tint read as a flash against
                // the button's already-visible idle fill (the skip buttons hover fine --
                // they start from nothing). The cursor and the glyph brightening still
                // say "hoverable"; only a real press changes the surface now.
                color: _playT.pressed ? Theme.controlFill(Theme.accent, 0.18)
                    : Theme.menuControl
                ColorFade on color {}

                OutlineBorder {
                    radius: _playFill.radius
                    outlineWidth: 1
                    outlineColor: Theme.menuControlLine
                    ColorFade on outlineColor {}
                }
            }
            // same ink-centering as MediaButton, with the reference FIXED to the pause
            // glyph: the pair shares one design baseline, and re-measuring against
            // whichever glyph is current would jump the icon on every playback toggle
            // (measured 2px low against the skip buttons before this)
            TextMetrics {
                id: _playAlignMetrics
                font: _playGlyph.font
                text: "󰏤"
            }
            // measured trim on top of the metric shift: the play/pause pair still sat
            // ~1px low live after ink-centering (1.5 physical at 1.60 scale) -- the same
            // tightBoundingRect lie the bar's bluetooth/battery/volume pills needed a
            // nudge for. Skip glyphs measured dead even; only this pair lies.
            readonly property int _playAlignNudge: -1
            // horizontal counterpart, per state: the play triangle's ink lies 1.5
            // physical px left inside its advance (measured against the container),
            // while the pause bars are symmetric -- so only the triangle gets the trim
            readonly property int _playAlignNudgeX: _playGlyph.shown === "󰐊" ? 1 : 0
            ShellText {
                id: _playGlyph
                anchors.centerIn: parent
                anchors.verticalCenterOffset: Math.round(
                    (_playGlyph.implicitHeight / 2)
                    - (_playGlyph.baselineOffset
                       + _playAlignMetrics.tightBoundingRect.y
                       + _playAlignMetrics.tightBoundingRect.height / 2))
                    + _playBtn._playAlignNudge
                anchors.horizontalCenterOffset: _playBtn._playAlignNudgeX
                property string shown: ""
                readonly property string target: Media.playing ? "󰏤" : "󰐊"
                property bool _ready: false
                text: shown
                color: _playH.hovered ? Theme.text : Theme.withAlpha(Theme.text, 0.8)
                font.pixelSize: Settings.fontSize + 10
                ColorFade on color {}

                Component.onCompleted: { shown = target; _ready = true }
                onTargetChanged: {
                    if (!_ready || ShellSettings.reduceMotion) { shown = target; return }
                    _playStamp.restart()
                }
                SequentialAnimation {
                    id: _playStamp
                    NumberAnimation { target: _playGlyph; property: "scale"; to: 0.72; duration: Motion.instant; easing.type: Easing.InCubic }
                    ScriptAction    { script: _playGlyph.shown = _playGlyph.target }
                    NumberAnimation { target: _playGlyph; property: "scale"; from: 0.72; to: 1.0; duration: Motion.fast; easing.type: Easing.OutQuart }
                }
            }
        }

        MediaButton {
            glyph: "󰒭"
            glyphAlignReference: "󰒭"
            available: Media.canGoNext
            onTriggered: Media.next()
        }
    }
}
