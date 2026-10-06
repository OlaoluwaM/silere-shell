pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland
import "../../config"
import "../../services"
import "../common"
import "controls"
import "settings"

PanelWindow {
    id: win

    required property ShellScreen targetScreen

    readonly property string _output: Compositor.monitorName(win.screen)

    Connections {
        target: Compositor
        function onWorkspaceActivated(output) {
            if (output === win._output && MenuState.open) MenuState.close()
        }
    }

    screen:        targetScreen
    color:         "transparent"
    exclusiveZone: -1
    WlrLayershell.namespace: "silere-menu"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: MenuState.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    visible: MenuState.open || panel.opacity > 0.001

    anchors {
        top:    true
        left:   true
        right:  true
        bottom: true
    }

    Shortcut {
        sequence: "Escape"
        context:  Qt.ApplicationShortcut
        enabled:  MenuState.open
        onActivated: {
            if (panel.powerOpen) {
                panel._setPowerOpen(false)
            } else if (panel.activeTab === 0 && homeLoader.item && homeLoader.item.dismissInline()) {
            } else if (panel.activeTab === 1 && settingsLoader.item && settingsLoader.item.dismissInline()) {
            } else {
                MenuState.close()
            }
        }
    }

    OutsideTapGuard {
        id: _tapGuard
        open: MenuState.open
    }

    Item { id: _fillArea; anchors.fill: parent }
    mask: Region { item: MenuState.open ? _fillArea : null }

    TapHandler {
        id: _dismiss
        enabled: MenuState.open
        onTapped: {
            if (_tapGuard.ignoring) return
            const p = _dismiss.point.position
            if (p.x < panel.x || p.x > panel.x + panel.width ||
                p.y < panel.y || p.y > panel.y + panel.height) {
                MenuState.close()
            }
        }
    }

    // one leaving page's frozen geometry. It outlasts the page's exit by a beat, so the page
    // reflows only once it is fully clear
    component PagePin: QtObject {
        id: pin
        property bool held: false
        property int pad: 0
        property int innerW: 0
        // what the geometry was derived from, so a page called back mid-fade can tell whether
        // it would rest where it is pinned
        property int panelW: 0
        property bool railExpanded: false
        function hold(padNow: int, innerNow: int, panelNow: int, expandedNow: bool): void {
            pin.pad = padNow
            pin.innerW = innerNow
            pin.panelW = panelNow
            pin.railExpanded = expandedNow
            pin.held = true
            _release.restart()
        }
        // the page leaves again before its exit ends, so the same geometry has to outlast a new exit
        function extend(): void {
            _release.restart()
        }
        function drop(): void {
            _release.stop()
            pin.held = false
        }
        readonly property Timer _release: Timer {
            interval: Motion.pageSwapOut + Motion.ms(30)
            onTriggered: pin.held = false
        }
    }

    PopupShadow { card: panel }

    FloatingPopupCard {
        id: panel

        win: win
        open: MenuState.open
        anchorX: MenuState.effectiveAnchorX
        barBottom: Metrics.barAtBottom
        targetWidth: placementW
        animatePlacement: false
        clip: true
        // the rail and content pane below already paint Theme.menuPane edge to edge, so this
        // card's own fill would stack a second translucent layer under theirs; in glass mode
        // that compounds toward opaque and kills the frost, so leave the card itself unpainted
        color: Theme._glass ? "transparent" : Theme.popup

        // the rail cap and the detail pane are both px while a category label scales with
        // uiScale, so each end takes the same growth: the pane keeps its width and the
        // longest label, 13 characters, stops eliding at the top of the type range
        readonly property int _typeGain: Metrics.snap4(
            13 * 0.6 * Math.max(0, Settings.fontSize - Settings.fontSizeBase))

        // every panel width stays on the 4px grid, or the outline's right edge lands on a
        // half output px at fractional scale and rasterizes wider than its left
        readonly property int _compactW: 400
        readonly property int _powerW: 568
        readonly property int _settingsW: 632 + _typeGain
        readonly property bool _settingsNavVisible:
            activeTab === 1 && !powerOpen
        readonly property bool _railExpanded: _settingsNavVisible || powerOpen
        readonly property int _availablePanelW: win.width > 0
            ? Math.max(4, Metrics.snap4Down(win.width - _minX * 2))
            : _settingsW
        // the one place a panel width is decided, so predicting a width before a change lands
        // cannot drift from the width the change then produces
        function _widthFor(tab: int, power: bool): int {
            return Math.max(1, Math.min(
                tab === 1 ? _settingsW : power ? _powerW : _compactW, _availablePanelW))
        }
        readonly property int panelW: _widthFor(activeTab, powerOpen)
        readonly property int placementW: Math.max(1,
            Math.min(_settingsW, _availablePanelW))
        readonly property int railCollapsedW: 44
        readonly property int _navMinW: 112
        readonly property int _navMaxW: 160 + _typeGain
        readonly property int navW: {
            const available = panelW - railCollapsedW
            const desired = Math.max(_navMinW, Metrics.snap4(panelW * 0.28))
            const detailSafe = Math.max(_navMinW, available - 224)
            const sidebarFit = Math.max(0, available - 96)
            return Math.max(0, Math.min(_navMaxW, desired, detailSafe, sidebarFit))
        }
        readonly property int railExpandedW: railCollapsedW + navW
        // animated here, not on the rail Item: the content pane derives its x and width from this, and easing only the rail leaves the content snapping ahead of it
        property int railW: _railExpanded ? railExpandedW : railCollapsedW
        MotionBehavior on railW {
            gate: panel._geometryReady && panel.fullyShown
            NumberAnimation {
                duration: Motion.menuResize
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }
        // the pane is the clip box, so it tracks the live edge and uncovers the page as the panel
        // moves. The pages inside do not follow it: one that re-lays out on every frame of a resize
        // reads as the text shaking, so they lay out at the geometry they will rest at (innerW)
        readonly property int contentW: Math.max(1, Math.round(width - railW))
        readonly property int _restContentW: Math.max(1,
            panelW - (_railExpanded ? railExpandedW : railCollapsedW))
        // keyed on the target width, or the pad steps 16 -> 22 mid-run as the live width crosses 460
        readonly property int contentPad: activeTab === 1
            ? Math.max(16, Math.min(24,
                Metrics.snap4(16 + (panelW - _compactW) * 8 / (_settingsW - _compactW))))
            : _railExpanded && panelW >= 460 ? 22 : 16
        // the left inset sits against the rail's hairline, which already reads as
        // separation; the right inset meets the panel outline directly, so it gets
        // a touch more room for the two edges to feel equally spaced
        readonly property int contentPadRight: contentPad + 4
        readonly property int innerW: Math.max(1, _restContentW - contentPad - contentPadRight)
        // a page on its way out keeps the geometry it started with until it has faded: the
        // destination's would reflow it under its own exit. Held per page, so a second switch
        // cannot move a page that is still fading from the first
        PagePin { id: _pinHome }
        PagePin { id: _pinSettings }
        PagePin { id: _pinRecent }
        PagePin { id: _pinSystem }
        function _pinFor(tab: int): PagePin {
            return tab === 0 ? _pinHome : tab === 1 ? _pinSettings
                : tab === 2 ? _pinRecent : _pinSystem
        }
        // a called-back page still finishing its exit is leaving in every sense but activeTab
        function _pinApplies(tab: int): bool {
            return panel._pinFor(tab).held && (tab !== panel.activeTab
                || panel._loaderFor(tab).item?.exiting === true)
        }
        function _pageX(tab: int): real {
            return panel._pinApplies(tab) ? panel._pinFor(tab).pad - panel.contentPad : 0
        }
        function _pageW(tab: int): real {
            return panel._pinApplies(tab) ? panel._pinFor(tab).innerW : panel.innerW
        }
        // a switch that keeps the width has no moving edge to show direction, so the pages slide.
        // Settled before anything moves: a page reading panelW from inside its own active
        // handler can still see the width it is leaving
        property bool _swapMovesEdge: false
        readonly property int idealMinH: 360
        readonly property int minRailFitH: 252
        readonly property int pageTopInset: 16
        readonly property int pageBottomInset: 12
        // content-borne, unlike the two insets above: the run-out past a page's last card
        // has to scroll with the page so the card clears the pane edge at the end of the range
        readonly property int pageTrail: 24
        // a page shorter than its tab's floor floats in the pane instead of being hugged.
        // Settings has the nav column to justify the height; system has only its own cards,
        // so its floor sits lower. Screen fractions, the same basis recentViewportH uses.
        readonly property int tabFloorH: win.height <= 0 ? 0
            : activeTab === 1 ? Metrics.snap4(win.height * 0.66)
            : activeTab === 3 ? Metrics.snap4(win.height * 0.44)
            : 0
        // on tall pages (settings, system) the panel would otherwise stretch to nearly the
        // full screen; capping it around three quarters keeps the rail/tray in view and lets
        // the content flickable below take over the rest via scrolling
        readonly property real _maxPanelHFrac: 0.72
        readonly property int _availablePanelH: win.height > 0
            ? Math.max(1, Math.min(
                Math.floor(win.height - _edgeY - _minX),
                Math.floor(win.height * _maxPanelHFrac)))
            : contentPane.targetH
        // the 44%/55% bounds are the maintainer's own call, not a derived value: the panel
        // opens at 44% of the screen even with an empty history, an accepted tradeoff so the
        // page doesn't open collapsed to nothing. 70 is NotificationCard's own minimum height,
        // carried over from upstream, so this under-counts tall cards on purpose. availH is the
        // hard ceiling regardless of either bound - the panel's own room always wins.
        readonly property int recentViewportH: {
            const availH = panel._availablePanelH - panel.pageTopInset - panel.pageBottomInset
            const floorH = Metrics.snap4(win.height * 0.44)
            const capH   = Math.min(Metrics.snap4(win.height * 0.55), availH)
            const wantH  = Metrics.rowHeightFor(38) + 18 + Notifications.historyCount * 70
            return Math.max(1, Math.min(capH, Math.max(floorH, Metrics.snap4(wantH))))
        }
        readonly property int _resolvedPanelH: Math.max(1,
            Math.min(contentPane.targetH, _availablePanelH))
        // A lazy page briefly reports the placeholder height before its final
        // implicit height. Hold the live edge through that interval so a tab
        // switch has one height destination instead of shrinking then growing.
        readonly property int targetPanelH: _tabHeightHeld
            ? Math.max(1, Math.min(_tabHeldH, _availablePanelH))
            : _resolvedPanelH

        readonly property int activeTab: MenuState.activeTab

        property bool powerOpen: false
        // armed before the write, not from a handler on it: the width change reflows the page and
        // can retarget the height in the same flush, which a handler would reach after the first
        // write and leave it snapping. The open and close resets do not go through here
        function _setPowerOpen(open: bool): void {
            if (panel.powerOpen === open) return
            panel._armOuterHeightMotion()
            panel.powerOpen = open
        }

        property bool _geometryReady:  false
        property bool _outerHeightMotion: false
        property bool _tabHeightHeld: false
        property int  _tabHeldH: idealMinH

        MenuPageLifecycle {
            id: _pageLifecycle
            activeTab: panel.activeTab
            menuOpen: MenuState.open
        }

        Component.onCompleted: {
            Qt.callLater(function() { panel._geometryReady = true })
        }

        function _settlePageVisuals(): void {
            if (homeLoader.item) homeLoader.item.settleVisual(activeTab === 0)
            if (settingsLoader.item) settingsLoader.item.settleVisual(activeTab === 1)
            if (recentLoader.item) recentLoader.item.settleVisual(activeTab === 2)
            if (systemLoader.item) systemLoader.item.settleVisual(activeTab === 3)
        }

        onCloseFinished: {
            if (open) return
            _settlePageVisuals()
            powerOpen = false
        }

        function switchTab(idx: int): void {
            const tab = Math.max(0, Math.min(3, idx))
            // a change announces itself through tabChanging, which pins the leaving page and closes the
            // drawer in that order; this covers a tap on the tab already showing
            MenuState.selectTab(tab)
            panel._setPowerOpen(false)
            contentFlick.contentY = 0
        }

        // how long the page arriving on a tab change holds back: the page leaving now takes a full
        // exit, a page still fading from an earlier switch takes what is left of its own, and
        // nothing visible leaving means nothing to wait for. Measured before the change moves
        // anything, since the pages read it from inside their own active handlers
        property int _swapWait: 0
        function _loaderFor(tab: int): Loader {
            return tab === 0 ? homeLoader : tab === 1 ? settingsLoader
                : tab === 2 ? recentLoader : systemLoader
        }
        function _beginTabSwap(to: int): void {
            const now = Date.now()
            const from = panel.activeTab
            // a page called back while still fading resumes in place, which is only right when its
            // pinned geometry is the geometry it rests at; otherwise it would move at partial opacity
            const arriving = panel._loaderFor(to).item
            const arrivingPin = panel._pinFor(to)
            if (arriving && arriving.opacity > 0.01 && arrivingPin.held
                    && (arrivingPin.panelW !== panel._widthFor(to, false)
                        || arrivingPin.railExpanded !== (to === 1)))
                arriving.finishExitBeforeEnter()
            let wait = 0
            for (let tab = 0; tab < 4; tab++) {
                const page = panel._loaderFor(tab).item
                if (tab === to || !page || page.opacity <= 0.01) continue
                // the leaving page's own exit starts in the flush the arriving page waits in, so it
                // needs no slack; one still fading from an earlier switch was timed by the clock
                wait = Math.max(wait, tab === from ? Motion.pageSwapOut
                    : page.exitEndsAt - now + Motion.frameAllowance)
            }
            panel._swapWait = Math.min(Motion.pageSwapOut + Motion.frameAllowance,
                Math.max(0, wait))
            // every tab change closes the drawer, so the width it lands on is the drawerless one
            // a width still travelling from an earlier change counts too: the edge is moving even
            // when this change leaves the target where it was
            panel._swapMovesEdge = panel._widthFor(to, false) !== panel.panelW
                || Math.abs(panel.width - panel.panelW) > 0.5
            const leaving = panel._loaderFor(from).item
            if (panel.open && Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
                    && leaving && leaving.opacity > 0.01) {
                // a called-back page still finishing its exit sits at its pinned geometry, not the
                // panel's; re-pinning from the panel would move it mid-fade
                if (panel._pinApplies(from)) panel._pinFor(from).extend()
                else panel._pinFor(from).hold(panel.contentPad, panel.innerW,
                    panel.panelW, panel._railExpanded)
            }
        }

        function _beginTabHeightHold(tab: int): void {
            if (!panel.open || ShellSettings.reduceMotion) return
            // a page that is already final has one height destination, so there is nothing to
            // hold: the height starts with the width instead of a timer tick later
            if (panel._pageSettled(tab)) {
                // a hold left by an earlier lazy switch would start this height a tick behind the width
                panel._tabHeightHeld = false
                _tabHeightRelease.stop()
                panel._armOuterHeightMotion()
                return
            }
            if (panel._tabHeightHeld) return
            panel._tabHeldH = Math.max(1, Math.round(panel.height))
            panel._tabHeightHeld = true
        }

        function _pageSettled(tab: int): bool {
            if (tab === 1) {
                if (settingsLoader.status === Loader.Error) return true
                return settingsLoader.status === Loader.Ready
                    && settingsLoader.item?.contentReady === true
            }
            const status = tab === 0 ? homeLoader.status
                : tab === 2 ? recentLoader.status
                : systemLoader.status
            return status === Loader.Ready || status === Loader.Error
        }

        function _scheduleTabHeightRelease(): void {
            if (panel._tabHeightHeld && panel._pageSettled(panel.activeTab))
                _tabHeightRelease.restart()
        }

        function _armOuterHeightMotion(): void {
            if (!panel.open || ShellSettings.reduceMotion) return
            panel._outerHeightMotion = true
            _outerHeightMotionHold.restart()
        }

        Connections {
            target: MenuState
            function onTabRequested(index) {
                if (index !== 0) _pageLifecycle.activateDeferred()
                panel.switchTab(index)
            }
            function onTabChanging(index) {
                // every route to a tab change passes here, IPC included, while the old page still
                // sets the height and fills the pane. The pin has to read the geometry before the
                // drawer closes, since closing it retargets the geometry being pinned
                panel._beginTabSwap(index)
                panel._setPowerOpen(false)
                panel._beginTabHeightHold(index)
            }
            function onActiveTabChanged() {
                contentFlick.contentY = 0
                panel._scheduleTabHeightRelease()
                if (!MenuState.open) panel._settlePageVisuals()
            }
            function onSettingsSectionChanged() {
                if (MenuState.settingsActive) panel._armOuterHeightMotion()
            }
            function onOpenChanged() {
                if (MenuState.open) {
                    // reopening before closeFinished leaves the last swap half-run: its leaving page
                    // still exiting while the active one snaps in. Settle every page before the
                    // pins drop, or a page at partial opacity reflows
                    panel._settlePageVisuals()
                    // closeFinished is canceled when a close animation reverses; transient drawer state must not depend on that callback
                    panel.powerOpen = false
                    panel._outerHeightMotion = false
                    panel._tabHeightHeld = false
                    panel._swapMovesEdge = false
                    panel._swapWait = 0
                    for (let tab = 0; tab < 4; tab++) panel._pinFor(tab).drop()
                    _tabHeightRelease.stop()
                    _outerHeightMotionHold.stop()
                    contentFlick.contentY = 0
                } else {
                    _settingsWarmDelay.stop()
                }
            }
        }

        Timer {
            id: _outerHeightMotionHold
            interval: Motion.pageOut + Motion.menuResize + Motion.ms(60)
            onTriggered: panel._outerHeightMotion = false
        }

        Timer {
            id: _tabHeightRelease
            interval: 0
            onTriggered: {
                if (!panel._tabHeightHeld || !panel._pageSettled(panel.activeTab)) return
                panel._armOuterHeightMotion()
                panel._tabHeightHeld = false
            }
        }

        Connections {
            target: ShellSettings
            function onReduceMotionChanged() {
                if (!ShellSettings.reduceMotion) return
                _tabHeightRelease.stop()
                panel._tabHeightHeld = false
                panel._outerHeightMotion = false
            }
        }

        width:  panelW
        height: targetPanelH

        // must match railW's curve and length, or the panel's outer edge and the rail's inner edge
        // disagree mid-motion. Neither branches on direction, so a power drawer that stays open
        // across a narrowing tab switch cannot split them.
        // Not before the card is shown: a window warmed by a hover has its geometry armed
        // before the click, and the width would grow out of the rail under the fade.
        MotionBehavior on width {
            gate: panel._geometryReady && panel.fullyShown
            NumberAnimation {
                duration: Motion.menuResize
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }
        // width and height are one motion, or the panel's corner travels a bent path: same curve,
        // same length, same start frame
        MotionBehavior on height {
            gate: panel._geometryReady && panel.open && panel._outerHeightMotion
            NumberAnimation {
                duration: Motion.menuResize
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Motion.standard
            }
        }

        onFullyShownChanged: {
            if (fullyShown && !_pageLifecycle.loadedDeferred) {
                Qt.callLater(function() {
                    if (panel && panel.fullyShown)
                        _pageLifecycle.activateDeferred()
                })
            }
        }

        Item {
            id: rail
            x: 0; y: 0
            width: panel.railW
            height: panel.height
            clip: false
            z: 6

            Item {
                anchors.fill: parent
                clip: true

                Rectangle {
                    x: 0; y: 0
                    width: parent.width + panel.radius
                    height: parent.height
                    radius: panel.radius
                    antialiasing: true
                    color: Theme.menuPane
                }

                Hairline {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    vertical: true
                    // the expanded drawer is declared later, so keep the rail edge above its surface instead of letting it paint over it
                    z: 20
                    color: Theme.menuDivider
                    ColorFade on color {}
                }

                Rectangle {
                    x: panel.railCollapsedW
                    width: Math.max(0, parent.width - x)
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    // this strip sits over the rail's own Theme.menuPane fill above, so under glass any
                    // pane-alpha fill here (popupHover included) stacks a second layer and frosts the
                    // drawer near-opaque; menuCard's glass wash lifts it off the pane the way cards
                    // lift, and mix() outside glass is opaque, so it stacks nothing
                    color: Theme._glass ? Theme.menuCard : Theme.mix(Theme.menuPane, Theme.menuControl, 0.14)
                    visible: parent.width > panel.railCollapsedW + 0.5
                }

                Item {
                    id: _settingsRailSurface
                    x: panel.railCollapsedW
                    width: panel.navW
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    property real _slide: panel._settingsNavVisible
                        ? 0 : -Motion.pageOffset
                    opacity: panel._settingsNavVisible ? 1 : 0
                    visible: opacity > 0.001
                    enabled: panel._settingsNavVisible
                    transform: Translate { x: _settingsRailSurface._slide }
                    MotionBehavior on opacity {
                        id: _navFade
                        NumberAnimation {
                            duration: _navFade.targetValue > 0.5
                                ? Motion.ms(130) : Motion.ms(90)
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: _navFade.targetValue > 0.5
                                ? Motion.standardDecel : Motion.standardAccel
                        }
                    }
                    MotionBehavior on _slide {
                        NumberAnimation {
                            duration: Motion.menuResize
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.standard
                        }
                    }

                    Loader {
                        id: _settingsNavLoader
                        anchors.fill: parent
                        active: _pageLifecycle.settingsNavRetained
                            || (MenuState.open && panel.activeTab === 1)
                        asynchronous: !panel._settingsNavVisible
                        sourceComponent: Component {
                            SettingsNav {
                                powerOpen: panel.powerOpen
                                onCurrentPageRetapped: contentFlick.contentY = 0
                                // the nav reports its final height at once while its groups animate, so
                                // here the panel does need its own easing
                                onGroupToggled: panel._armOuterHeightMotion()
                            }
                        }
                    }
                }

                Item {
                    id: _powerRailSurface
                    x: panel.railCollapsedW
                    width: panel.navW
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    height: panel.powerOpen
                        ? (_powerRailLoader.item?.implicitHeight ?? 0) : 0
                    clip: true
                    opacity: panel.powerOpen ? 1 : 0
                    visible: height > 0.5 || opacity > 0.001
                    enabled: panel.powerOpen

                    MotionBehavior on height {
                        NumberAnimation {
                            duration: Motion.menuResize
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.standard
                        }
                    }
                    MotionBehavior on opacity {
                        id: _powerRailFade
                        NumberAnimation {
                            duration: Motion.fast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: _powerRailFade.targetValue > 0.5
                                ? Motion.standardDecel : Motion.standardAccel
                        }
                    }

                    Loader {
                        id: _powerRailLoader
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 9
                        anchors.rightMargin: 9
                        anchors.bottom: parent.bottom
                        height: item ? item.implicitHeight : 0
                        active: panel.powerOpen || _powerRailSurface.height > 0.5
                        sourceComponent: Component {
                            PowerRailContent { active: panel.powerOpen }
                        }
                    }
                }

            }

            RailLabelGroup { id: _railLabels }

            Timer {
                id: _settingsWarmDelay
                // Ignore incidental sweeps down the icon rail. This is input
                // intent detection, not visual motion, so reduce-motion does not
                // collapse the delay to zero.
                interval: 90
                onTriggered: if (_railSettings.hovered) _pageLifecycle.warmSettings()
            }

            Column {
                id: _railNav
                width: panel.railCollapsedW
                x: 0
                y: 10
                spacing: 6

                RailNavItem {
                    id: _railHome
                    labels: _railLabels
                    railW: panel.railCollapsedW
                    glyph: "󰋜"
                    label: "Home"
                    labelPillEnabled: !panel._railExpanded
                        || panel.navW < panel._navMinW
                    active: panel.activeTab === 0
                    onTapped: panel.switchTab(0)
                }

                RailNavItem {
                    id: _railRecent
                    labels: _railLabels
                    railW: panel.railCollapsedW
                    glyph: "󰋚"
                    label: "Notifications"
                    labelPillEnabled: !panel._railExpanded
                        || panel.navW < panel._navMinW
                    active: panel.activeTab === 2
                    onTapped: panel.switchTab(2)

                    Rectangle {
                        readonly property bool _show: Notifications.hasHistory && !_railRecent.active
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.horizontalCenterOffset: 8
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: -8
                        width: Math.max(height, _railBadgeCount.implicitWidth + 7)
                        height: 14; radius: height / 2
                        color: Theme.accent; antialiasing: true
                        opacity: _show ? 1.0 : 0.0
                        scale:   _show ? 1.0 : 0.5
                        visible: opacity > 0.01
                        transformOrigin: Item.Center
                        MotionBehavior on opacity {NumberAnimation { duration: Motion.fast } }
                        MotionBehavior on scale   {NumberAnimation { duration: Motion.ms(120); easing.type: Easing.OutCubic } }
                        OutlineBorder {
                            radius: parent.radius
                            outlineWidth: 2
                            outlineColor: Theme.menuPane
                        }
                        ShellText {
                            id: _railBadgeCount
                            anchors.fill: parent
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                            text: Notifications.historyCount > 99 ? "99+" : Notifications.historyCount
                            color: Theme.background
                            font.pixelSize: Settings.fontTiny
                            font.weight: Font.Bold
                        }
                    }
                }

                RailNavItem {
                    id: _railSettings
                    labels: _railLabels
                    railW: panel.railCollapsedW
                    glyph: "󰒓"
                    label: "Settings"
                    labelPillEnabled: !panel._railExpanded
                        || panel.navW < panel._navMinW
                    active: panel.activeTab === 1
                    onTapped: panel.switchTab(1)
                    onHoveredChanged: {
                        if (hovered) _settingsWarmDelay.restart()
                        else _settingsWarmDelay.stop()
                    }
                }

                RailNavItem {
                    id: _railSystem
                    labels: _railLabels
                    railW: panel.railCollapsedW
                    glyph: "󰾅"
                    label: "System"
                    labelPillEnabled: !panel._railExpanded
                        || panel.navW < panel._navMinW
                    active: panel.activeTab === 3
                    onTapped: panel.switchTab(3)
                }
            }

            Item {
                id: _railPowerSlot
                readonly property int gap: 10
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                anchors.left: parent.left
                width: panel.railCollapsedW
                // derived, not summed: RailNavItem is rowHeightFor(34), which grows with the
                // font, so a hardcoded total drops the icon below its own inset at larger type
                height: _railDivider.height + _railPowerSlot.gap + _railPower.height
                z: 9

                Hairline {
                    id: _railDivider
                    anchors.top: parent.top
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 18
                    color: Theme.menuDivider
                }

                RailNavItem {
                    id: _railPower
                    labels: _railLabels
                    anchors.top: _railDivider.bottom
                    anchors.topMargin: _railPowerSlot.gap
                    anchors.horizontalCenter: parent.horizontalCenter
                    railW: panel.railCollapsedW
                    glyph: "󰐥"
                    label: "Power"
                    labelPillEnabled: !panel._railExpanded
                        || panel.navW < panel._navMinW
                    accentColor: Theme.error
                    active: panel.powerOpen
                    onTapped: panel._setPowerOpen(!panel.powerOpen)
                }
            }
        }

        Item {
            id: contentPane
            // no MotionBehavior here: x tracks panel.railW, which is already animated at the source —
            // a second Behavior on top double-eases and lags the pane behind the rail it's supposed to hug
            x: panel.railW
            y: 0
            width: panel.contentW
            clip: true

            Rectangle {
                x: -panel.radius
                y: 0
                width: parent.width + panel.radius
                height: parent.height
                radius: panel.radius
                antialiasing: true
                color: Theme.menuPane
            }

            readonly property int targetH: {
                const contentH = panel.pageTopInset + tabContent.height
                    + panel.pageBottomInset
                const navH = panel.activeTab === 1
                    ? (_settingsNavLoader.item?.implicitHeight ?? 0) + 16 : 0
                return 4 * Math.ceil(Math.max(panel.minRailFitH,
                    panel.idealMinH, panel.tabFloorH, contentH, navH) / 4)
            }

            height: panel.height

            TapHandler {
                enabled: panel.powerOpen
                onTapped: panel._setPowerOpen(false)
            }

            ShellFlickable {
                id: contentFlick
                anchors.fill: parent
                // the page insets sit on the viewport, not inside the content: as part
                // of the scrollable content they vanished mid-scroll, leaving pages to
                // clip flush against the pane's rounded corners on short screens
                anchors.topMargin: panel.pageTopInset
                anchors.bottomMargin: panel.pageBottomInset
                contentWidth: width
                contentHeight: tabContent.height
                interactive: !panel.powerOpen && panel.activeTab !== 2
                    && _contentSettle.overflows

                function clampToContent(): void {
                    const maxY = Math.max(0, contentHeight - height)
                    if (contentY > maxY) contentY = maxY
                    else if (contentY < 0) contentY = 0
                }

                function revealSettingsSelect(): void {
                    const row = MenuState.settingsSelectOwner
                    if (!row || !panel.open || panel.activeTab !== 1) return
                    // a list taller than the viewport keeps its header in view, not its end
                    const top = row.mapToItem(contentFlick.contentItem, 0, 0).y
                    const bottom = top + row.height
                    const margin = 8
                    let target = contentY
                    if (row.height + margin * 2 > height)
                        target = top - margin
                    else if (top - margin < target)
                        target = top - margin
                    else if (bottom + margin > target + height)
                        target = bottom + margin - height
                    contentY = Math.max(0,
                        Math.min(Math.max(0, contentHeight - height), target))
                }

                // the dropdown grows over its own Disclosure and the panel follows it frame by frame, so
                // the reveal measures once that has landed
                Timer {
                    id: _selectReveal
                    interval: Motion.medium + 24
                    onTriggered: contentFlick.revealSettingsSelect()
                }

                Connections {
                    target: MenuState
                    // the panel's own height motion stays off for these: the content already animates its
                    // height, and a NumberAnimation restarted every frame trails it and lands late
                    function onSettingsSelectClaimed() {
                        if (panel.open && panel.activeTab === 1) _selectReveal.restart()
                    }
                    function onSettingsSelectOpenChanged() {
                        if (!MenuState.settingsSelectOpen) _selectReveal.stop()
                    }
                }

                onContentHeightChanged: clampToContent()
                onHeightChanged: {
                    clampToContent()
                    if (MenuState.settingsSelectOpen && panel.activeTab === 1)
                        _selectReveal.restart()
                }

                // default focus target while the menu is open: nothing else claims focus
                // until a field is clicked, so the arrows page the content the same way
                // the keybinds viewer scrolls (quarter-viewport jumps, no animation --
                // a focused editor still consumes its own arrow presses first)
                focus: true
                function _scrollStep(delta: real): void {
                    const maxY = Math.max(0, contentHeight - height)
                    contentY = Math.max(0, Math.min(maxY, contentY + delta))
                }
                Keys.onUpPressed: contentFlick._scrollStep(-Math.round(height / 4))
                Keys.onDownPressed: contentFlick._scrollStep(Math.round(height / 4))

                Item {
                    id: tabContent
                    // a build shorter than this reads as a flicker, not as feedback
                    property bool _pageSlow: false
                    x: panel.contentPad
                    y: 0
                    width: panel.innerW
                    readonly property bool _pagePending:
                        panel.activeTab === 1
                            ? settingsLoader.status !== Loader.Ready
                                || settingsLoader.item?.contentReady !== true
                      : panel.activeTab === 2 ? recentLoader.status !== Loader.Ready
                      : panel.activeTab === 3 ? systemLoader.status !== Loader.Ready
                      : false
                    readonly property bool _pageError:
                        panel.activeTab === 1
                            ? settingsLoader.status === Loader.Error
                                || settingsLoader.item?.contentError === true
                      : panel.activeTab === 2 ? recentLoader.status === Loader.Error
                      : panel.activeTab === 3 ? systemLoader.status === Loader.Error
                      : false
                    on_PagePendingChanged: {
                        if (tabContent._pagePending) {
                            _pageSlowDefer.restart()
                        } else {
                            _pageSlowDefer.stop()
                            tabContent._pageSlow = false
                        }
                    }
                    Timer {
                        id: _pageSlowDefer
                        interval: 220
                        onTriggered: tabContent._pageSlow = tabContent._pagePending
                    }
                    readonly property real _pageH:
                            panel.activeTab === 0 ? (homeLoader.item?.implicitHeight ?? 0)
                          : panel.activeTab === 1 ? (settingsLoader.item?.implicitHeight
                                ?? _pagePlaceholder.implicitHeight)
                          : panel.activeTab === 2 ? (recentLoader.item?.implicitHeight
                                ?? _pagePlaceholder.implicitHeight)
                          : (systemLoader.item?.implicitHeight ?? _pagePlaceholder.implicitHeight)
                    // the notifications page is a viewport sized to the panel, so a trail there
                    // would only push its list off the bottom
                    height: _pageH + (panel.activeTab === 2 ? 0 : panel.pageTrail)
                    clip: false

                    Item {
                        id: _pagePlaceholder
                        width: parent.width
                        height: implicitHeight
                        implicitHeight: Math.max(1, panel.idealMinH
                            - panel.pageTopInset - panel.pageBottomInset)
                        readonly property bool _shown:
                            tabContent._pageSlow || tabContent._pageError
                        opacity: _pagePlaceholder._shown ? 1 : 0
                        visible: opacity > 0.001
                        enabled: false
                        z: 5

                        MotionBehavior on opacity {
                            id: _placeholderFade
                            NumberAnimation {
                                duration: Motion.pageOut
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: _placeholderFade.targetValue > 0.5
                                    ? Motion.standardDecel : Motion.standardAccel
                            }
                        }

                        Column {
                            anchors.centerIn: parent
                            spacing: 8

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 40
                                height: 40
                                radius: 20
                                antialiasing: true
                                color: tabContent._pageError
                                    ? Theme.withAlpha(Theme.error, 0.10)
                                    : Theme.withAlpha(Theme.accent, 0.08)

                                OutlineBorder {
                                    radius: 20
                                    outlineColor: tabContent._pageError
                                        ? Theme.withAlpha(Theme.error, 0.34)
                                        : Theme.withAlpha(Theme.accent, 0.20)
                                }

                                ShellText {
                                    anchors.centerIn: parent
                                    text: tabContent._pageError ? "󰅙" : "󰔟"
                                    color: tabContent._pageError
                                        ? Theme.withAlpha(Theme.error, 0.82)
                                        : Theme.withAlpha(Theme.accent, 0.76)
                                    font.pixelSize: Settings.iconSize + 5
                                }
                            }

                            ShellText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(1, _pagePlaceholder.width - 24)
                                horizontalAlignment: Text.AlignHCenter
                                text: tabContent._pageError
                                    ? "Couldn’t load this page"
                                    : panel.activeTab === 1 ? "Loading settings…"
                                    : panel.activeTab === 2 ? "Loading notifications…"
                                    : "Loading system…"
                                color: Theme.withAlpha(Theme.text, 0.76)
                                font.pixelSize: Settings.fontSize
                                font.weight: Font.Medium
                            }

                            ShellText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.max(1, _pagePlaceholder.width - 24)
                                horizontalAlignment: Text.AlignHCenter
                                visible: tabContent._pageError
                                text: "The menu is still usable; check the shell log for details"
                                wrapMode: Text.WordWrap
                                maximumLineCount: 2
                                color: Theme.withAlpha(Theme.subtext, 0.54)
                                font.pixelSize: Settings.fontCaption
                            }
                        }
                    }

                    Loader {
                        id: homeLoader
                        x: panel._pageX(0)
                        width: panel._pageW(0)
                        active: _pageLifecycle.homeRetained
                        asynchronous: false
                        onStatusChanged: panel._scheduleTabHeightRelease()
                        sourceComponent: Component {
                            HomePage {
                                width: parent.width
                                swapWait: panel._swapWait
                                slideOnSwap: !panel._swapMovesEdge
                                active: panel.activeTab === 0 && MenuState.open
                                powerOpen: panel.powerOpen
                                animateOnCreate: panel.fullyShown
                            }
                        }
                    }

                    Loader {
                        id: settingsLoader
                        x: panel._pageX(1)
                        width: panel._pageW(1)
                        active: _pageLifecycle.loadedDeferred
                            && _pageLifecycle.settingsRetained
                        asynchronous: true
                        onStatusChanged: panel._scheduleTabHeightRelease()
                        sourceComponent: Component {
                            SettingsPage {
                                width: parent.width
                                swapWait: panel._swapWait
                                slideOnSwap: !panel._swapMovesEdge
                                active: panel.activeTab === 1 && MenuState.open
                                powerOpen: panel.powerOpen
                                animateOnCreate: panel.fullyShown
                                scroller: contentFlick
                                onContentReadyChanged: panel._scheduleTabHeightRelease()
                                onSectionSwapped: contentFlick.contentY = 0
                            }
                        }
                    }

                    Loader {
                        id: recentLoader
                        x: panel._pageX(2)
                        width: panel._pageW(2)
                        active: _pageLifecycle.loadedDeferred
                            && _pageLifecycle.recentRetained
                        asynchronous: true
                        onStatusChanged: panel._scheduleTabHeightRelease()
                        sourceComponent: Component {
                            RecentPage {
                                width: parent.width
                                swapWait: panel._swapWait
                                slideOnSwap: !panel._swapMovesEdge
                                viewportHeight: panel.recentViewportH
                                active: panel.activeTab === 2 && MenuState.open
                                powerOpen: panel.powerOpen
                                animateOnCreate: panel.fullyShown
                            }
                        }
                    }

                    Loader {
                        id: systemLoader
                        x: panel._pageX(3)
                        width: panel._pageW(3)
                        active: _pageLifecycle.loadedDeferred
                            && _pageLifecycle.systemRetained
                        asynchronous: true
                        onStatusChanged: panel._scheduleTabHeightRelease()
                        sourceComponent: Component {
                            SystemPage {
                                width: parent.width
                                swapWait: panel._swapWait
                                slideOnSwap: !panel._swapMovesEdge
                                active: panel.activeTab === 3 && MenuState.open
                                powerOpen: panel.powerOpen
                                animateOnCreate: panel.fullyShown
                            }
                        }
                    }
                }
            }

            ScrollSettle {
                id: _contentSettle
                list: contentFlick
                armed: panel.open
                contextKey: panel.activeTab === 1
                    ? "settings:" + MenuState.settingsSection
                    : "tab:" + panel.activeTab
            }

            ListEdgeLines {
                anchors.fill: contentFlick
                list: contentFlick
                visible: panel.activeTab !== 2 && _contentSettle.ready
                z: 4
            }

            MenuScrollThumb {
                list: contentFlick
                shown: panel.open && !panel.powerOpen && panel.activeTab !== 2
                z: 5
            }
        }

        OutlineBorder {
            radius: panel.radius
            outlineColor: Theme.outline
            z: 20
        }
    }

}
