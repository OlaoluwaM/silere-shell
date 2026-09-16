pragma Singleton

import QtQuick
import Quickshell

Singleton {
    id: root

    // Notification silence and an integrated OSD are the only fullscreen
    // consumers in this fork. Keep their demand shared without reintroducing
    // removed media-progress or visualizer behavior.
    readonly property bool wanted: ShellSettings.notifFullscreenSilence
        || (ShellSettings.osdEnabled && ShellSettings.osdBarIntegrated)
    readonly property bool active: root.wanted && Compositor.activeFullscreen

    // Demand can begin after the focused toplevel changed while no consumer
    // watched it, so refresh the compositor view when tracking starts.
    function refresh(): void { Compositor.refreshToplevels() }

    Component.onCompleted: if (root.wanted) root.refresh()
    onWantedChanged: if (root.wanted) root.refresh()
}
