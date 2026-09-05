pragma ComponentBehavior: Bound

import QtQuick
import "../../config"

// The menu's pages have different memory costs, but they all follow the same
// rule: keep a page through its exit, then release it unless the user comes
// back before that grace period ends. Keeping that policy beside its timers
// makes the loaders below MenuWindow declarative consumers of one owner.
QtObject {
    id: root

    property int activeTab: 0
    property bool menuOpen: false
    property bool loadedDeferred: false

    property bool homeRetained: false
    property bool settingsRetained: false
    property bool recentRetained: false
    property bool systemRetained: false
    property bool settingsNavRetained: false

    // A page stays through its exit, Settings stays for comparison, speculative
    // warming is shorter, and a closed menu keeps only one final grace window.
    property int pageReleaseDelay: Math.max(Motion.pageOut, Motion.ms(100)) + 30
    property int settingsReleaseDelay: 8000
    property int settingsWarmReleaseDelay: 2500
    property int closeReleaseDelay: Math.max(Motion.pageOut, Motion.ms(100)) + 120

    function activateDeferred(): void {
        if (!root.loadedDeferred) root.loadedDeferred = true
    }

    function warmSettings(): void {
        if (!root.menuOpen || root.activeTab === 1 || root.settingsRetained) return
        root.activateDeferred()
        root.settingsRetained = true
        root.settingsNavRetained = true
        root._settingsWarmRelease.restart()
    }

    function _syncRetention(): void {
        if (root.activeTab === 0) {
            root._homeRelease.stop()
            root.homeRetained = true
        } else if (root.homeRetained) {
            root._homeRelease.restart()
        }

        if (root.activeTab === 1) root.settingsNavRetained = true

        if (!root.loadedDeferred) {
            root._settingsRelease.stop()
            root._recentRelease.stop()
            root._systemRelease.stop()
            root.settingsRetained = false
            root.recentRetained = false
            root.systemRetained = false
            return
        }

        if (root.activeTab === 1) {
            root._settingsWarmRelease.stop()
            root._settingsRelease.stop()
            root.settingsRetained = true
        } else if (root.settingsRetained) {
            root._settingsRelease.restart()
        }

        if (root.activeTab === 2) {
            root._recentRelease.stop()
            root.recentRetained = true
        } else if (root.recentRetained) {
            root._recentRelease.restart()
        }

        if (root.activeTab === 3) {
            root._systemRelease.stop()
            root.systemRetained = true
        } else if (root.systemRetained) {
            root._systemRelease.restart()
        }
    }

    onActiveTabChanged: root._syncRetention()
    onLoadedDeferredChanged: root._syncRetention()
    onMenuOpenChanged: {
        if (root.menuOpen) {
            root._closedRelease.stop()
            root._syncRetention()
        } else {
            root._settingsWarmRelease.stop()
            root._closedRelease.restart()
        }
    }
    Component.onCompleted: root._syncRetention()

    readonly property Timer _homeRelease: Timer {
        interval: root.pageReleaseDelay
        onTriggered: if (root.activeTab !== 0) root.homeRetained = false
    }

    readonly property Timer _settingsRelease: Timer {
        interval: root.settingsReleaseDelay
        onTriggered: {
            if (root.activeTab === 1) return
            root.settingsRetained = false
            root.settingsNavRetained = false
        }
    }

    readonly property Timer _settingsWarmRelease: Timer {
        interval: root.settingsWarmReleaseDelay
        onTriggered: {
            if (root.activeTab === 1) return
            root._settingsRelease.stop()
            root.settingsRetained = false
            root.settingsNavRetained = false
        }
    }

    readonly property Timer _recentRelease: Timer {
        interval: root.pageReleaseDelay
        onTriggered: if (root.activeTab !== 2) root.recentRetained = false
    }

    readonly property Timer _systemRelease: Timer {
        interval: root.pageReleaseDelay
        onTriggered: if (root.activeTab !== 3) root.systemRetained = false
    }

    readonly property Timer _closedRelease: Timer {
        interval: root.closeReleaseDelay
        onTriggered: {
            if (root.menuOpen) return
            root._settingsWarmRelease.stop()
            root._settingsRelease.stop()
            root._recentRelease.stop()
            root._systemRelease.stop()
            root.settingsRetained = false
            root.recentRetained = false
            root.systemRetained = false
            root.settingsNavRetained = false
        }
    }
}
