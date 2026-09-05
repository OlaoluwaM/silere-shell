pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import "../../config"
import "../../services"

// Runs from the menu module so it shares MenuPageLifecycle's config and
// service imports. The root wrapper only loads this owner and reports its log.
QtObject {
    id: root

    property int checks: 0
    property int failures: 0
    property var defaultLifecycle: null
    property var lifecycle: null
    property var warmLifecycle: null
    property var pendingLifecycle: null
    property var _next: null
    property bool _started: false
    property bool _initialReduceMotion: false
    property int _initialPageReleaseDelay: 0
    property int _initialCloseReleaseDelay: 0

    readonly property Component lifecycleFactory: Component {
        MenuPageLifecycle {}
    }

    function check(condition: bool, label: string): void {
        root.checks++
        if (condition) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function after(delay: int, next: var): void {
        root._next = next
        _wait.interval = delay
        _wait.restart()
    }

    function build(): void {
        if (root._started) return
        root._started = true

        root.defaultLifecycle = lifecycleFactory.createObject(root, {
            activeTab: 0,
            menuOpen: true
        })
        root.check(root.defaultLifecycle !== null,
            "default-delay lifecycle constructs")
        if (!root.defaultLifecycle) {
            root.finish()
            return
        }

        const expectedPageDelay = Math.max(Motion.pageOut, Motion.ms(100)) + 30
        const expectedCloseDelay = Math.max(Motion.pageOut, Motion.ms(100)) + 120
        root.check(root.defaultLifecycle.pageReleaseDelay === expectedPageDelay
                && root.defaultLifecycle.closeReleaseDelay === expectedCloseDelay,
            "production page and close grace follow the current motion setting")
        root._initialPageReleaseDelay = root.defaultLifecycle.pageReleaseDelay
        root._initialCloseReleaseDelay = root.defaultLifecycle.closeReleaseDelay

        root.defaultLifecycle.activateDeferred()
        root.defaultLifecycle.activeTab = 3
        root.after(root.defaultLifecycle.pageReleaseDelay + 20,
            root._afterDefaultPageRelease)
    }

    function _afterDefaultPageRelease(): void {
        root.check(!root.defaultLifecycle.homeRetained
                && root.defaultLifecycle.systemRetained,
            "production page grace releases an outgoing page")

        root._initialReduceMotion = ShellSettings.reduceMotion
        ShellSettings.reduceMotion = !root._initialReduceMotion
        root.after(1, root._afterMotionToggle)
    }

    function _afterMotionToggle(): void {
        const expectedPageDelay = Math.max(Motion.pageOut, Motion.ms(100)) + 30
        const expectedCloseDelay = Math.max(Motion.pageOut, Motion.ms(100)) + 120
        root.check(root.defaultLifecycle.pageReleaseDelay === expectedPageDelay
                && root.defaultLifecycle.closeReleaseDelay === expectedCloseDelay
                && root.defaultLifecycle.pageReleaseDelay !== root._initialPageReleaseDelay
                && root.defaultLifecycle.closeReleaseDelay !== root._initialCloseReleaseDelay,
            "production grace defaults stay bound after reduce-motion changes")
        ShellSettings.reduceMotion = root._initialReduceMotion

        root.lifecycle = lifecycleFactory.createObject(root, {
            activeTab: 0,
            menuOpen: true,
            pageReleaseDelay: 30,
            settingsReleaseDelay: 60,
            settingsWarmReleaseDelay: 45,
            closeReleaseDelay: 75
        })
        root.check(root.lifecycle !== null, "MenuPageLifecycle constructs")
        if (!root.lifecycle) {
            root.finish()
            return
        }

        root.check(root.lifecycle.homeRetained
                && !root.lifecycle.settingsRetained
                && !root.lifecycle.recentRetained
                && !root.lifecycle.systemRetained,
            "home is retained before deferred pages load")

        root.lifecycle.warmSettings()
        root.check(root.lifecycle.loadedDeferred
                && root.lifecycle.settingsRetained
                && root.lifecycle.settingsNavRetained,
            "warming settings retains its page and navigation")

        root.lifecycle.activeTab = 1
        root.check(root.lifecycle.settingsRetained
                && root.lifecycle.settingsNavRetained
                && root.lifecycle.homeRetained,
            "opening warmed settings cancels speculative release")

        root.lifecycle.activeTab = 2
        root.check(root.lifecycle.recentRetained
                && root.lifecycle.homeRetained
                && root.lifecycle.settingsRetained,
            "rapid page switch keeps outgoing pages through their grace")

        root.lifecycle.activeTab = 3
        root.check(root.lifecycle.systemRetained
                && root.lifecycle.recentRetained,
            "rapid second switch retains the interrupted recent page")

        root.after(105, root._afterRapidSwitch)
    }

    function _afterRapidSwitch(): void {
        root.check(root.lifecycle.systemRetained
                && !root.lifecycle.homeRetained
                && !root.lifecycle.recentRetained
                && !root.lifecycle.settingsRetained
                && !root.lifecycle.settingsNavRetained,
            "each outgoing page releases after its own delay")

        root.lifecycle.activeTab = 1
        root.check(root.lifecycle.settingsRetained
                && root.lifecycle.settingsNavRetained,
            "returning to settings restores its retained owner state")

        root.lifecycle.menuOpen = false
        root.after(35, root._reopenBeforeCloseRelease)
    }

    function _reopenBeforeCloseRelease(): void {
        root.lifecycle.menuOpen = true
        root.check(root.lifecycle.settingsRetained
                && root.lifecycle.settingsNavRetained,
            "reopening before close grace keeps settings warm")
        root.after(55, root._afterOldCloseDeadline)
    }

    function _afterOldCloseDeadline(): void {
        root.check(root.lifecycle.settingsRetained
                && root.lifecycle.settingsNavRetained,
            "reopening cancels the old close release after its original deadline")
        root.lifecycle.menuOpen = false
        root.after(100, root._afterCloseRelease)
    }

    function _afterCloseRelease(): void {
        root.check(!root.lifecycle.settingsRetained
                && !root.lifecycle.settingsNavRetained
                && !root.lifecycle.recentRetained
                && !root.lifecycle.systemRetained,
            "a completed close grace releases deferred pages")
        root.lifecycle.menuOpen = true
        root.check(root.lifecycle.settingsRetained
                && root.lifecycle.settingsNavRetained,
            "reopening the same deferred tab rebuilds pages after close release")

        root.warmLifecycle = lifecycleFactory.createObject(root, {
            activeTab: 0,
            menuOpen: true,
            pageReleaseDelay: 30,
            settingsReleaseDelay: 60,
            settingsWarmReleaseDelay: 45,
            closeReleaseDelay: 75
        })
        root.check(root.warmLifecycle !== null,
            "speculative lifecycle constructs")
        if (!root.warmLifecycle) {
            root.finish()
            return
        }
        root.warmLifecycle.warmSettings()
        root.check(root.warmLifecycle.settingsRetained
                && root.warmLifecycle.settingsNavRetained,
            "speculative settings stay warm before their shorter release")
        root.after(70, root._afterWarmRelease)
    }

    function _afterWarmRelease(): void {
        root.check(!root.warmLifecycle.settingsRetained
                && !root.warmLifecycle.settingsNavRetained,
            "expired speculative warm releases settings before comparison grace")

        root.pendingLifecycle = lifecycleFactory.createObject(root, {
            activeTab: 0,
            menuOpen: true,
            pageReleaseDelay: 30,
            settingsReleaseDelay: 60,
            settingsWarmReleaseDelay: 45,
            closeReleaseDelay: 75
        })
        root.check(root.pendingLifecycle !== null,
            "pending lifecycle constructs")
        if (!root.pendingLifecycle) {
            root.finish()
            return
        }

        root.pendingLifecycle.menuOpen = false
        root.pendingLifecycle.activeTab = 3
        root.pendingLifecycle.activateDeferred()
        root.check(root.pendingLifecycle.systemRetained,
            "deferred activation after close retains its requested page")
        root.pendingLifecycle.menuOpen = true
        root.after(90, root._afterPendingReopen)
    }

    function _afterPendingReopen(): void {
        root.check(root.pendingLifecycle.systemRetained,
            "opening after deferred activation cancels the pending close release")
        root.finish()
    }

    function finish(): void {
        console.warn("PROBE-POPUP-LIFECYCLE "
            + (root.failures === 0 ? "passed " : "failed ")
            + root.checks + " checks")
        Qt.exit(root.failures === 0 ? 0 : 1)
    }

    readonly property Timer _wait: Timer {
        onTriggered: {
            const next = root._next
            root._next = null
            if (next) next()
        }
    }

    readonly property Connections _settingsConnections: Connections {
        target: ShellSettings
        function onReadyChanged(): void {
            if (ShellSettings.ready) Qt.callLater(root.build)
        }
    }

    Component.onCompleted: {
        if (ShellSettings.ready) Qt.callLater(root.build)
    }
}
