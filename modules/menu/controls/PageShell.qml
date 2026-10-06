import QtQuick
import "../../../config"
import "../../../services"

Item {
    id: root

    required property bool active
    required property bool powerOpen

    property bool animateOnCreate: false
    // how long the arriving page holds back for a visible page that is still leaving, as of the
    // tab change; the owner knows what else is on screen, so the shell takes the number as given
    property int swapWait: 0
    // when this page's own exit finishes, so the owner can tell a sibling how long to hold back
    property real exitEndsAt: 0

    signal pageShown()
    signal pageHidden()

    width: parent ? parent.width : 0
    enabled: root.active && !root.powerOpen
    visible: opacity > 0.001
    property real _pageShift: 0
    property real _transitionDirection: 1
    property int _enterDelay: 0
    transform: Translate { x: root._pageShift }

    // the same idle/reduce-motion policy every other surface follows, so an idle shell does not animate a page change
    readonly property bool _motionAllowed: Motion.allowsMotion(Idle.isIdle, ShellSettings.reduceMotion)
    property bool _announcedActive: false

    function _announceShown(): void {
        if (!root.active || root._announcedActive) return
        root._announcedActive = true
        root.pageShown()
    }

    function _announceHidden(): void {
        if (!root._announcedActive) return
        root._announcedActive = false
        root.pageHidden()
    }

    // a page built after the tab change missed the flush the wait was measured in, so what is left of
    // it comes from the clock, with the frame allowance the clock needs. A wait the owner already padded
    // gets a second frame at most, on a page that is still being built. Clamped both ways: a clock
    // stepped backwards must not hold the page blank
    function _enterWait(elapsedMs: real): int {
        if (root.swapWait <= 0) return 0
        const total = Math.min(root.swapWait, Motion.pageSwapOut) + Motion.frameAllowance
        return Math.min(total, Math.max(0, total - elapsedMs))
    }

    function settleVisual(shown: bool): void {
        _enter.stop()
        _exit.stop()
        root.exitEndsAt = 0
        root.opacity = shown ? 1.0 : 0.0
        root._pageShift = 0
        if (!MenuState.open) root._announceHidden()
    }

    property bool _menuOpenSettled: false
    Connections {
        target: MenuState
        function onOpenChanged() {
            if (!MenuState.open) root._menuOpenSettled = false
            else Qt.callLater(() => root._menuOpenSettled = MenuState.open)
        }
    }

    Component.onCompleted: {
        const enterNow = root.active && root.animateOnCreate
            && MenuState.open && root._motionAllowed
        root._transitionDirection = MenuState.tabDirection === 0
            ? 1 : MenuState.tabDirection
        root.opacity = root.active && !enterNow ? 1.0 : 0.0
        root._pageShift = enterNow
            ? Motion.pageOffset * root._transitionDirection : 0
        if (MenuState.open) Qt.callLater(() => root._menuOpenSettled = MenuState.open)
        if (enterNow) Qt.callLater(function() {
            if (root.active && MenuState.open && root._motionAllowed) {
                root._enterDelay = root._enterWait(Date.now() - MenuState.tabChangedAt)
                _enter.restart()
            } else root.settleVisual(root.active)
        })
        Qt.callLater(root._announceShown)
    }

    onActiveChanged: {
        root._transitionDirection = MenuState.tabDirection === 0
            ? 1 : MenuState.tabDirection
        if (root.active) {
            _exit.stop()
            root.exitEndsAt = 0
            if (!root._menuOpenSettled || !root._motionAllowed) {
                root.settleVisual(true)
                root._announceShown()
                return
            }
            // the leaving page's exit starts in this same flush, so the owner's wait lines the two
            // clocks up. A page still fading out and coming back has nobody to wait for: the page
            // that took its place has not started yet
            if (root.opacity < 0.01) {
                root._pageShift = Motion.pageOffset * root._transitionDirection
                root._enterDelay = root.swapWait
            } else {
                root._enterDelay = 0
            }
            _enter.restart()
            root._announceShown()
        } else {
            _enter.stop()
            if (!MenuState.open) {
                return
            }
            if (root._motionAllowed) {
                root.exitEndsAt = Date.now() + Motion.pageSwapOut
                _exit.restart()
            } else root.settleVisual(false)
            root._announceHidden()
        }
    }

    on_MotionAllowedChanged: {
        if (root._motionAllowed) return
        _enter.stop()
        _exit.stop()
        root.exitEndsAt = 0
        if (MenuState.open) root.settleVisual(root.active)
        else root._pageShift = 0
    }

    SequentialAnimation {
        id: _enter
        PauseAnimation { duration: root._enterDelay }
        ParallelAnimation {
            NumberAnimation { target: root; property: "opacity"; to: 1.0; duration: Motion.pageSwapIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardDecel }
            NumberAnimation { target: root; property: "_pageShift"; to: 0.0; duration: Motion.pageSwapIn; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedDecel }
        }
    }
    ParallelAnimation {
        id: _exit
        NumberAnimation { target: root; property: "opacity"; to: 0.0; duration: Motion.pageSwapOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccel }
        NumberAnimation { target: root; property: "_pageShift"; to: -Motion.pageOffset * root._transitionDirection; duration: Motion.pageSwapOut; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccel }
    }
}
