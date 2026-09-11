import QtQuick
import Quickshell
import "services"

ShellRoot {
    id: root

    readonly property var controlNames: [
        "menu", "calendar", "tray", "traypopup", "quickActions", "keybinds", "wallpapers", "media"
    ]
    property int checks: 0
    property int failures: 0

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
        void OverlayCoordinator.armed
        root.testOrdinaryPairwiseOpens()
        root.testTrayRelationships()
        root.testCloseAll()
        root.testEnvironmentTransitions()
        root.testLateOpens()
        console.warn("PROBE-OVERLAY-COORDINATOR "
            + (root.failures === 0 ? "passed " : "failed ") + root.checks + " checks")
    }

    Component.onCompleted: Qt.callLater(root.run)
}
