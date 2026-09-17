import QtQuick
import Quickshell
import Quickshell.Io
import "services"
import "popup-fixtures" as Fixtures

ShellRoot {
    id: root

    readonly property var controlNames: [
        "menu", "calendar", "tray", "traypopup", "quickActions", "keybinds", "wallpapers", "media"
    ]
    property alias checks: progress.checks
    property alias failures: progress.failures
    property bool persistentReady: false
    property bool started: false
    property int openedSignals: 0
    property int anchorPhase: 0
    property QtObject replacementAnchor: null
    property QtObject temporaryPopup: null
    readonly property bool coldKeybindsOpen: KeybindsPopupState.open
    readonly property bool coldWallpapersOpen: WallpapersPopupState.open

    PersistentProperties {
        id: progress
        reloadableId: "silerePopupStateProbe"
        property int checks: 0
        property int failures: 0
        property bool reloaded: false
        onLoaded: root.persistentReady = true
    }

    Connections {
        target: Quickshell
        function onReloadCompleted() { Quickshell.inhibitReloadPopup() }
    }
    Connections {
        target: ControlSurfaces
        function onOpened() { root.openedSignals++ }
    }

    Component {
        id: anchorFactory
        QtObject { property real menuAnchorX: 42 }
    }
    Component {
        id: popupFactory
        // Exercise the production base's construction and destruction. Dynamic
        // instances produce Quickshell's "not the root component of its file"
        // singleton warnings; they are expected only for this fixture.
        PopupState { open: true }
    }

    function check(ok: bool, label: string): void {
        root.checks++
        if (ok) return
        root.failures++
        console.warn("PROBE-FAIL " + label)
    }

    function stateOpen(name: string): bool {
        switch (name) {
        case "menu": return MenuState.open
        case "calendar": return CalendarState.open
        case "tray": return TrayMenuState.open
        case "traypopup": return TrayPopupState.open
        case "quickActions": return QuickActionsState.open
        case "keybinds": return KeybindsPopupState.open
        case "wallpapers": return WallpapersPopupState.open
        case "media": return MediaPopupState.open
        }
        return false
    }

    function openState(name: string): void {
        switch (name) {
        case "menu": MenuState.open = true; break
        case "calendar": CalendarState.open = true; break
        case "tray":
            TrayMenuState.popupSourced = false
            TrayMenuState.open = true
            break
        case "traypopup": TrayPopupState.open = true; break
        case "quickActions": QuickActionsState.open = true; break
        case "keybinds": KeybindsPopupState.open = true; break
        case "wallpapers": WallpapersPopupState.open = true; break
        case "media": MediaPopupState.open = true; break
        }
    }

    function noControlsOpen(): bool {
        for (let i = 0; i < root.controlNames.length; i++)
            if (root.stateOpen(root.controlNames[i])) return false
        return true
    }

    function onlyStateOpen(name: string): bool {
        for (let i = 0; i < root.controlNames.length; i++) {
            const current = root.controlNames[i]
            if (root.stateOpen(current) !== (current === name)) return false
        }
        return true
    }

    function reset(): void {
        Idle.isIdle = false
        OverviewState.active = false
        OverlayCoordinator.closeAll()
        MenuState.close()
        CalendarState.close()
        TrayMenuState.close()
        TrayPopupState.close()
        QuickActionsState.close()
        KeybindsPopupState.close()
        WallpapersPopupState.close()
        MediaPopupState.close()
    }

    function testOrdinaryPairwiseOpens(): void {
        for (let first = 0; first < root.controlNames.length; first++) {
            const firstName = root.controlNames[first]
            root.reset()
            root.openState(firstName)
            root.check(root.onlyStateOpen(firstName), "ordinary open keeps only " + firstName)
            for (let second = 0; second < root.controlNames.length; second++) {
                if (first === second) continue
                const secondName = root.controlNames[second]
                root.openState(secondName)
                root.check(root.onlyStateOpen(secondName),
                    firstName + " yields to " + secondName)
                root.openState(firstName)
                root.check(root.onlyStateOpen(firstName),
                    secondName + " yields to " + firstName)
            }
        }
    }

    function testTrayRelationships(): void {
        root.reset()
        TrayPopupState.open = true
        TrayMenuState.popupSourced = true
        TrayMenuState.open = true
        root.check(TrayPopupState.open && TrayMenuState.open,
            "a tray-list item menu keeps its tray-list parent open")
        MediaPopupState.open = true
        root.check(root.onlyStateOpen("media") && !TrayMenuState.popupSourced,
            "media closes the tray-list child and clears its source")

        root.reset()
        TrayPopupState.open = true
        TrayMenuState.popupSourced = true
        TrayMenuState.open = true
        MenuState.open = true
        root.check(root.onlyStateOpen("menu") && !TrayMenuState.popupSourced,
            "another popup closes the tray-list child and clears its source")

        root.reset()
        TrayPopupState.open = true
        TrayMenuState.popupSourced = false
        TrayMenuState.open = true
        root.check(TrayMenuState.open && !TrayPopupState.open,
            "an inline tray context menu closes the unrelated tray list")
    }

    function testCloseAll(): void {
        for (let i = 0; i < root.controlNames.length; i++) {
            const name = root.controlNames[i]
            root.reset()
            root.openState(name)
            OverlayCoordinator.closeAll()
            root.check(root.noControlsOpen(), "closeAll closes " + name)
        }
    }

    function testEnvironmentTransitions(): void {
        for (let i = 0; i < root.controlNames.length; i++) {
            const name = root.controlNames[i]
            root.reset()
            root.openState(name)
            Idle.isIdle = true
            root.check(!root.stateOpen(name) && root.noControlsOpen(),
                "idle transition closes " + name)

            Idle.isIdle = false
            root.openState(name)
            OverviewState.active = true
            root.check(!root.stateOpen(name) && root.noControlsOpen(),
                "overview transition closes " + name)
        }
        root.reset()
    }

    function testLateOpens(): void {
        const environments = ["idle", "overview"]
        for (let environment = 0; environment < environments.length; environment++) {
            root.reset()
            if (environments[environment] === "idle") Idle.isIdle = true
            else OverviewState.active = true
            for (let i = 0; i < root.controlNames.length; i++) {
                const name = root.controlNames[i]
                root.openState(name)
                root.check(root.noControlsOpen(),
                    environments[environment] + " rejects late " + name + " open")
            }
        }
        root.reset()
    }

    function run(): void {
        if (root.started) return
        root.started = true
        void OverlayCoordinator.armed
        root.testOrdinaryPairwiseOpens()
        root.testTrayRelationships()
        root.testCloseAll()
        root.testEnvironmentTransitions()
        root.testLateOpens()
        root.testRegistry()
        root.testEarlyOpen()
        root.testOpenMethods()
        root.testControlSurfaces()
        root.startAnchorChecks()
    }

    function states(): var {
        return [MenuState, CalendarState, TrayMenuState, TrayPopupState,
            QuickActionsState, KeybindsPopupState, WallpapersPopupState, MediaPopupState]
    }

    function testRegistry(): void {
        const states = root.states()
        root.check(OverlayCoordinator.popups.length === 8,
            "all eight popup states register once")
        for (let i = 0; i < states.length; i++) OverlayCoordinator.registerPopup(states[i])
        root.check(OverlayCoordinator.popups.length === 8,
            "repeated registration does not duplicate states")
        let openCount = 0
        for (let i = 0; i < states.length; i++) if (states[i].open) openCount++
        root.check(OverlayCoordinator._openCount === openCount
                && OverlayCoordinator.anyOpen === (openCount > 0),
            "registry count agrees with actual open states")
    }

    function testOpenMethods(): void {
        const anchor = anchorFactory.createObject(root)
        const screen = Quickshell.screens[0] ?? null
        const states = root.states()
        for (let i = 0; i < states.length; i++) {
            root.reset()
            const state = states[i]
            if (state === TrayMenuState)
                state.toggleAt(42, screen, anchor, false, anchor, anchor, false)
            else if (state === QuickActionsState) state.toggleAt(42, screen, false, anchor)
            else if (state === KeybindsPopupState || state === WallpapersPopupState) state.toggle()
            else state.toggleAt(42, screen, anchor)
            root.check(root.onlyStateOpen(root.controlNames[i]) && OverlayCoordinator._openCount === 1,
                "real open method claims exclusivity for " + root.controlNames[i])
            if (state === KeybindsPopupState || state === WallpapersPopupState) {
                root.check(state.triggerScreen === null && state.anchorSource === undefined,
                    "centered state has no anchor machinery")
                state.toggle()
            } else {
                root.check(state.triggerScreen === screen && state.effectiveAnchorX === 42,
                    "anchored open retains its screen and live geometry")
                anchor.menuAnchorX = 73
                root.check(state.effectiveAnchorX === 73, "live anchor movement remains observable")
                anchor.menuAnchorX = 42
                state.close()
            }
            root.check(!state.open && state.triggerScreen === null && OverlayCoordinator._openCount === 0,
                "close resets common lifecycle state")
        }
        MenuState.openUnanchored()
        MenuState.close()
        MenuState.openUnanchored()
        root.check(MenuState.open && MenuState.anchorSource === null
                && OverlayCoordinator._openCount === 1, "rapid unanchored reopen counts once")
        root.reset()
        TrayPopupState.toggleAt(42, screen, anchor)
        TrayMenuState.toggleAt(42, screen, anchor, false, anchor, anchor, true)
        root.check(TrayPopupState.open && TrayMenuState.open && OverlayCoordinator._openCount === 2,
            "real tray child open preserves its parent and counts both")
        OverlayCoordinator.closeAll()
        root.check(OverlayCoordinator._openCount === 0, "closing a tray pair leaves no open count")
        anchor.destroy()
    }

    function testEarlyOpen(): void {
        root.reset()
        // Model an open signal arriving before completion registers this state.
        OverlayCoordinator.unregisterPopup(MenuState)
        Idle.isIdle = true
        const before = root.openedSignals
        MenuState.open = true
        root.check(!MenuState.open && OverlayCoordinator._openCount === 0,
            "an open before registration still obeys the idle guard")
        root.check(root.openedSignals === before, "rejected opens do not emit control-open notifications")
        root.reset()
        OverlayCoordinator.registerPopup(MenuState)
        root.testRegistry()
    }

    function testControlSurfaces(): void {
        root.reset()
        const states = root.states()
        for (let i = 0; i < states.length; i++) {
            const before = root.openedSignals
            states[i].open = true
            const controls = states[i] === MenuState || states[i] === QuickActionsState
            const hints = controls || states[i] === CalendarState || states[i] === TrayMenuState
            root.check(ControlSurfaces.anyOpen === controls
                    && ControlSurfaces.anyAnchoredOpen === hints,
                "control and bar-hint classifications remain unchanged for " + root.controlNames[i])
            root.check(root.openedSignals === before + (controls ? 1 : 0),
                "control opened signal retains its classification")
            states[i].close()
        }
        PowerProfiles._getRetries = 3
        MenuState.openUnanchored()
        root.check(PowerProfiles._getRetries === 0, "menu opening reaches the power-profile refresh consumer")
        MenuState.close()
        PowerProfiles._getRetries = 3
        QuickActionsState.openUnanchored()
        root.check(PowerProfiles._getRetries === 0, "quick actions reopening reaches the refresh consumer")
        root.reset()
    }

    function startAnchorChecks(): void {
        const anchor = anchorFactory.createObject(root)
        MenuState.openAt(42, null, anchor)
        anchor.destroy()
        root.anchorPhase = 0
        anchorSettle.interval = 40
        anchorSettle.start()
    }

    Timer {
        id: anchorSettle
        onTriggered: {
            if (root.anchorPhase === 0) {
                root.check(MenuState.open && MenuState.anchorSource === null,
                    "an existing anchored popup waits for anchor recovery")
                root.replacementAnchor = anchorFactory.createObject(root)
                MenuState.adoptAnchor(root.replacementAnchor)
                interval = 200
            } else if (root.anchorPhase === 1) {
                root.check(MenuState.open && MenuState.anchorSource === root.replacementAnchor,
                    "replacement anchor cancels the pending close")
                MenuState.close()
                root.replacementAnchor.destroy()
                const anchor = anchorFactory.createObject(root)
                CalendarState.openAt(42, null, anchor)
                anchor.destroy()
                interval = 220
            } else if (root.anchorPhase === 2) {
                root.check(!CalendarState.open, "an unreplaced anchor closes after the recovery window")
                const anchor = anchorFactory.createObject(root)
                MediaPopupState.toggleAt(42, null, anchor)
                anchor.destroy()
                interval = 40
            } else if (root.anchorPhase === 3) {
                root.check(!MediaPopupState.open, "media anchor loss closes without a recovery delay")
                const anchor = anchorFactory.createObject(root)
                TrayPopupState.toggleAt(42, null, anchor)
                anchor.destroy()
            } else if (root.anchorPhase === 4) {
                root.check(!TrayPopupState.open, "tray-list anchor loss closes without a recovery delay")
                const anchor = anchorFactory.createObject(root)
                MediaPopupState.toggleAt(42, null, anchor)
                Media.shown = false
                root.check(!MediaPopupState.open, "media disappearance closes despite a surviving anchor")
                Media.shown = true
                TrayPopupState.toggleAt(42, null, anchor)
                Fixtures.SystemTray.items.values = []
                root.check(!TrayPopupState.open, "an empty tray closes despite a surviving anchor")
                Fixtures.SystemTray.items.values = [{}]
                anchor.destroy()
                root.reset()
                root.testRegistry()
                root.temporaryPopup = popupFactory.createObject(root)
                root.check(OverlayCoordinator.popups.length === 9
                        && OverlayCoordinator._openCount === 1,
                    "an initially open popup registers and counts only once")
                root.temporaryPopup.destroy()
                interval = 40
            } else if (root.anchorPhase === 5) {
                root.check(OverlayCoordinator.popups.length === 8
                        && OverlayCoordinator._openCount === 0,
                    "destroying an open popup removes its registration and count")
                const environments = ["idle", "overview"]
                for (let i = 0; i < environments.length; i++) {
                    root.reset()
                    if (environments[i] === "idle") Idle.isIdle = true
                    else OverviewState.active = true
                    const registered = OverlayCoordinator.popups.length
                    const before = root.openedSignals
                    const popup = popupFactory.createObject(root, { controlSurface: true })
                    root.check(!popup.open && OverlayCoordinator._openCount === 0,
                        environments[i] + " rejects an initially open popup during construction")
                    root.check(OverlayCoordinator.popups.length === registered + 1,
                        "a rejected initial open still registers exactly once")
                    root.check(root.openedSignals === before,
                        "a rejected initial open does not notify control consumers")
                    popup.destroy()
                }
                root.reset()
            } else if (root.anchorPhase === 6) {
                root.check(OverlayCoordinator.popups.length === 8,
                    "destroying initially rejected popups removes their registrations")
                MenuState.openUnanchored()
                progress.reloaded = true
                Qt.callLater(function() { Quickshell.reload(false) })
                return
            }
            root.anchorPhase++
            restart()
        }
    }

    function finish(): void {
        console.warn("PROBE-OVERLAY-COORDINATOR "
            + (root.failures === 0 ? "passed " : "failed ") + root.checks + " checks")
    }

    IpcHandler {
        target: "popupProbe"
        function verify(name: string): string {
            root.check(root.onlyStateOpen(name), "cold IPC opens " + name + " exclusively")
            return root.failures === 0 ? "ok" : "failed"
        }
        function run(): void { root.run() }
    }

    Timer {
        interval: 20
        running: true
        repeat: true
        onTriggered: {
            if (!root.persistentReady || !ShellSettings.ready) return
            if (progress.reloaded) {
                root.check(root.noControlsOpen(), "reload starts with closed popup state")
                root.testRegistry()
                root.finish()
                stop()
            } else if (KeybindsPopupState.available && WallpapersPopupState.available) {
                console.warn("PROBE-OVERLAY-READY")
                stop()
            }
        }
    }
}
