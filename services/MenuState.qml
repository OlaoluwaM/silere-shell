pragma Singleton

import QtQuick
import Quickshell.Io

AnchoredPopupState {
    id: root

    anchorX: 10

    readonly property int homeTab: 0
    readonly property int settingsTab: 1
    readonly property int recentTab: 2
    readonly property int systemTab: 3
    property int _activeTab: homeTab
    property int _previousTab: homeTab
    readonly property int activeTab: _activeTab
    readonly property int previousTab: _previousTab
    readonly property int tabDirection: {
        const delta = tabPosition(activeTab) - tabPosition(previousTab)
        return delta === 0 ? 0 : (delta > 0 ? 1 : -1)
    }
    readonly property bool homeActive: open && activeTab === homeTab
    readonly property bool settingsActive: open && activeTab === settingsTab

    property string settingsSection: "theme"

    // order by user impact and frequency: global appearance first, daily bar surfaces next, then feedback; operational and recovery tools stay last
    readonly property var settingsTree: [
        { glyph: "󰉦", label: "Appearance", children: [
            { glyph: "󰉦", label: "Theme",       section: "theme",
              description: "Colors, accent, and outlines" },
            { glyph: "󰍉", label: "Interface", section: "interface",
              description: "Font, scale, contrast, motion, and displays" }
        ]},
        { glyph: "󰕮", label: "Bar", children: [
            { glyph: "󰍹", label: "Layout",    section: "surface",
              description: "Bar position, size, and shape" },
            { glyph: "󰍴", label: "Underline", section: "underline",
              description: "Line and event glow" },
            { glyph: "󰻂", label: "Spacing",   section: "separators",
              description: "Gaps and dividers" }
        ]},
        { glyph: "󰀻", label: "Widgets", children: [
            { glyph: "󰀻", label: "Show & order", section: "widgets",
              description: "Choose and reorder bar widgets" },
            { glyph: "󰕰", label: "Workspaces", section: "workspaces",
              description: "Markers, labels, and app icons" },
            { glyph: "󰅐", label: "Clock",      section: "clock",
              description: "Date and time" },
            { glyph: "󰝚", label: "Media",      section: "media",
              description: "Track details and visualizer" },
            { glyph: "󰈈", label: "Indicators", section: "indicators",
              description: "Titles, status, and hover" }
        ]},
        { glyph: "󰂚", label: "Feedback", children: [
            { glyph: "󰂚", label: "Notifications", section: "popups",
              description: "Position, timeout, and history" },
            { glyph: "󱀅", label: "OSD",    section: "osd",
              description: "Volume and brightness feedback" },
            { glyph: "󰀦", label: "Alerts", section: "warnings",
              description: "Battery and temperature limits" }
        ]},
        { glyph: "󰒓", label: "System", children: [
            { glyph: "󰕾", label: "Sound", section: "sound",
              description: "Devices, levels, and routing" },
            { glyph: "󰦛", label: "Maintenance", section: "maintenance",
              description: "Defaults and dependencies" }
        ]}
    ]

    readonly property var _flatSections: {
        const out = []
        for (let i = 0; i < settingsTree.length; i++) {
            const it = settingsTree[i]
            if (it.children) for (let j = 0; j < it.children.length; j++) out.push(it.children[j].section)
            else out.push(it.section)
        }
        return out
    }

    function setSettingsSection(s: string): void {
        const next = root._flatSections.indexOf(s) >= 0 ? s : "theme"
        if (next !== settingsSection) settingsSection = next
    }

    signal tabRequested(int index)

    function _validTab(index: int): int {
        return Math.max(homeTab, Math.min(systemTab, index))
    }

    // Match the rail's visual order rather than the internal numeric ids.
    function tabPosition(index: int): int {
        if (index === homeTab) return 0
        if (index === recentTab) return 1
        return 2
    }

    function selectTab(index: int): int {
        const tab = root._validTab(index)
        if (root._activeTab !== tab) {
            root._previousTab = root._activeTab
            root._activeTab = tab
        }
        return tab
    }

    function toggleAt(x: real, screen, source): void {
        if (open) {
            close()
            return
        }
        selectTab(homeTab)
        openAt(x, screen, source)
    }
    function showTab(index: int): void {
        const tab = selectTab(index)
        // set before opening: the lazy surface can't catch a pre-creation signal
        if (!open) open = true
        tabRequested(tab)
    }

    IpcHandler {
        target: "menu"

        function toggle(): void {
            if (root.open) { root.close(); return }
            root.selectTab(root.homeTab)
            root.openUnanchored()
        }
        function close(): void { root.close() }
        // kept for compatibility with keybinds already carrying the numeric index
        function tab(index: int): string {
            if (index < root.homeTab || index > root.systemTab)
                return "unknown menu tab " + index + "; valid: 0 (home), 1 (settings), 2 (recent), 3 (system)"
            root._unanchor()
            root.showTab(index)
            return "ok"
        }
        // named alternative to tab(index) so a keybind reads "menu show settings"
        // instead of a magic number; "recent" is accepted too since that's the
        // internal name for the same tab
        function show(name: string): string {
            let tab
            switch (name) {
            case "home":          tab = root.homeTab; break
            case "settings":      tab = root.settingsTab; break
            case "notifications":
            case "recent":        tab = root.recentTab; break
            case "system":        tab = root.systemTab; break
            default:              tab = -1
            }
            root.triggerScreen = null
            root._setAnchor(null)
            if (tab < 0) {
                root.showTab(root.homeTab)
                return "unknown menu tab '" + name + "'; opened home instead. valid: "
                    + "home, settings, notifications, system"
            }
            root.showTab(tab)
            return "ok"
        }
        // keep `section: "` out of any literal below: ci-lint harvests nav entries by that pattern
        function settings(name: string): string {
            const known = root._flatSections.indexOf(name) >= 0
            root._unanchor()
            root.setSettingsSection(name)
            root.showTab(root.settingsTab)
            if (known) return "ok"
            // pages get renamed; a keybind carrying an old name still opens Settings rather than doing nothing, and says why it landed somewhere else
            return "unknown settings page '" + name + "'; opened theme instead. valid: "
                + root._flatSections.join(", ")
        }
    }
}
