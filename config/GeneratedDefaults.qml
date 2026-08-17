pragma Singleton

// Substitution point for the Nix packaging: the build overwrites this file with
// site-specific defaults (bar geometry, theme, widgets) before Quickshell ever
// sees it, so a rebase never has to touch the shell settings' initializers by
// hand. The copy checked into this fork carries the same values upstream ships,
// so anyone running it outside of Nix sees no behavior change.

import QtQuick
import Quickshell

Singleton {
    id: root

    readonly property bool   barFloating:         false
    readonly property string barPosition:         "top"
    readonly property int    barGap:              4
    readonly property int    barRadius:           14
    readonly property real   barWidth:            0.90
    readonly property bool   barFitGaps:          false
    readonly property int    barHeight:           36
    readonly property bool   barShadow:           false
    readonly property bool   barBorderVisible:    false
    readonly property bool   barShowMedia:        true
    readonly property bool   barShowClock:        true
    readonly property bool   barShowNetwork:      true
    readonly property bool   barShowBluetooth:    true
    readonly property bool   barShowBattery:      true
    readonly property bool   barShowVolume:       true
    readonly property bool   barShowBrightness:   true
    readonly property string barWidgetOrderLeft:  "workspaces,media"
    readonly property string barWidgetOrderCenter: ""
    readonly property string barWidgetOrderRight: "tray,updates,network,bluetooth,caffeine,volume,brightness,battery,clock"
    readonly property string caffeineUnit:        ""
    readonly property string caffeinePresets:     "15,30,60,0"
    readonly property string wifiEditCommand:     "nm-connection-editor --edit {uuid}"
    readonly property string btEditCommand:       "blueman-manager"
    readonly property bool   barShowCaffeine:     true
    readonly property bool   trayWidget:          false
    readonly property bool   updatesWidget:       false
    readonly property bool   neutralTheme:        true
    readonly property string baseTone:            "black"
    readonly property string matugenAccentRole:   "primary"
    readonly property string matugenDepth:        "deeper"
    readonly property string fontFamily:          ""
    readonly property real   uiScale:             1.0
    readonly property bool   clock12h:            false
    readonly property bool   showSeconds:         false
    readonly property bool   osdEnabled:          true
    readonly property int    osdTimeout:          2000
    readonly property bool   glassSurfaces:       false
    readonly property real   glassOpacity:        0.85
    readonly property real   barOpacity:          0.88
}
