pragma ComponentBehavior: Bound

import QtQuick
import "../../../config"
import "../../../services"
import "../controls"

Column {
    id: root
    width: parent ? parent.width : 0
    spacing: 0

    ArmConfirm { id: _confirm }
    readonly property bool _armed: _confirm.armed

    // reopening Maintenance re-detects tools installed or removed while the shell is running. FontScan follows the completed tool refresh itself
    Component.onCompleted: SystemTools.refresh()

    Connections {
        target: MenuState
        // null-guarded: these can fire while the section is tearing down, after the
        // helper child is already gone
        function onSettingsSectionChanged() { if (_confirm) _confirm.disarm() }
        function onOpenChanged() { if (!MenuState.open && _confirm) _confirm.disarm() }
    }

    SectionLabel { label: "DEFAULTS"; first: true }
    SettingsCard {
        ControlRow {
            glyph: "󰦛"
            title: root._armed ? "Confirm reset" : "Restore defaults"
            status: ShellSettings.modifiedCount > 0
                ? ShellSettings.modifiedCount + (ShellSettings.modifiedCount === 1
                    ? " setting changed" : " settings changed")
                : "Everything is at its default"
            valueText: root._armed ? "Tap again" : ""
            accentColor: root._armed ? Theme.error : Theme.accent
            active: root._armed
            available: ShellSettings.modifiedCount > 0
            onActivated: if (_confirm.tryConfirm("reset")) ShellSettings.resetToDefaults()
        }
        HintText {
            text: "Backs up settings first and keeps the five newest. Wallpaper colors and calendar marks stay unchanged."
        }
    }

    // the whole section only instantiates while it is the open page; the probe runs once on entry and never polls in the background
    readonly property var _issues: {
        const out = []
        if (!SystemTools.ready) return out
        if (SystemTools.probeFailed) return out

        // a dead font tofus the bar AND the menu that would fix it, so it leads
        if (!SystemTools.hasFcList)
            out.push({ g: "󰈵", n: "Font check", s: "Cannot verify the interface font", v: "fontconfig", p: true })
        else if (FontScan.lastError.length > 0)
            out.push({ g: "󰈵", n: "Font check", s: FontScan.lastError, v: "fc-list" })
        // hasIconFont, not the family lists: Symbols Nerd Font alone keeps
        // icons rendering (glyph fallback) yet appears in neither list
        else if (FontScan.scanned && !FontScan.hasIconFont)
            out.push({ g: "󰈵", n: "Icon font", s: "No Nerd Font installed — bar icons cannot render", v: "nerd-fonts", p: true })
        else if (FontScan.scanned && ShellSettings.fontFamily.length > 0
                 && FontScan.families.indexOf(ShellSettings.fontFamily) < 0)
            out.push({ g: "󰈵", n: "Chosen font", s: "“" + ShellSettings.fontFamily + "” is gone; using " + Settings.font, v: "fallback" })

        // wallpaper theming degrades instead of hiding, so it reads as working while the palette silently stays bundled — both causes need naming
        if (!SystemTools.hasMatugen)
            out.push({ g: "󰉦", n: "Wallpaper theming",
                s: MatugenTheme.usingFallback ? "Wallpaper colors are unavailable"
                    : "Last palette stays; sync stops",
                v: "matugen", p: true })
        else if (MatugenTheme.paletteStale)
            out.push({ g: "󰉦", n: "Wallpaper palette", s: "Unreadable; showing the last colors that loaded", v: "template" })
        // the deployment wires matugen to the wallpaper command, so a missing palette is
        // fixed by setting a wallpaper, not by a repair the shell could run itself
        else if (MatugenTheme.usingFallback)
            out.push({ g: "󰉦", n: "Wallpaper palette", s: "Not written yet; set a wallpaper", v: "palette" })
        // the glass sample comes from the same wallpaper command, so it shares the palette's
        // remedy; only worth naming while something would follow it, and high contrast
        // disables glass before the toggle gets a say
        if (Theme._glass && ShellSettings.glassAdaptive) {
            if (GlassSample.sampleStale)
                out.push({ g: "󰉦", n: "Glass sample", s: "Unreadable; keeping the last sample that loaded", v: "sample" })
            else if (GlassSample.usingFallback)
                out.push({ g: "󰉦", n: "Glass sample", s: "Not written yet; set a wallpaper", v: "sample" })
        }

        const tool = (g, n, v) => out.push({ g: g, n: n, s: "Hidden until this is installed", v: v, p: true })
        if (!SystemTools.hasBrightnessctl)     tool("󰃟", "Brightness control", "brightnessctl")
        if (!SystemTools.hasHyprsunset)        tool("󰖙", "Night light", "hyprsunset")
        if (!PowerProfiles.available)          tool("󰾅", "Power profiles", "power-profiles-daemon")
        // a packaged lock command brings its own locker, so hyprlock is only the fallback's requirement
        if (!SystemTools.hasHyprlock && ShellSettings.lockCommand.trim().length === 0)
            tool("󰌾", "Screen lock", "hyprlock")
        // the warnings page stays visible and settable without notify-send, so this one is inert rather than hidden
        if (!SystemTools.hasNotifySend)
            out.push({ g: "󰂚", n: "System alerts", s: "Battery and temperature warnings cannot be sent", v: "libnotify", p: true })
        return out
    }

    SectionLabel { label: "HEALTH" }
    SettingsCard {
        ControlRow {
            visible: SystemTools.ready && !SystemTools.checking
                && !SystemTools.probeFailed && root._issues.length === 0
            glyph: "󰗠"
            title: "No feature issues found"
            status: "Available controls are ready"
            passive: true
        }
        ControlRow {
            visible: !SystemTools.ready || SystemTools.checking
            glyph: "󰋼"
            title: "Checking optional tools…"
            passive: true
        }
        ControlRow {
            visible: !SystemTools.checking && SystemTools.probeFailed
            glyph: "󰀦"
            title: "Optional tool check failed"
            status: SystemTools.lastError
            passive: true
        }
        Repeater {
            model: root._issues
            ControlRow {
                required property var modelData
                glyph: modelData.g
                title: modelData.n
                status: modelData.s
                valueText: modelData.v
                passive: true
            }
        }
        HintText {
            // A repair action or a vanished font is not something to install.
            visible: root._issues.some(i => i.p === true)
            text: "Install the listed package to enable its feature."
        }
        ControlRow {
            glyph: "󰑐"
            title: "Recheck optional tools"
            status: "Refresh after tool changes"
            valueText: SystemTools.checking ? "Checking…" : "Check"
            available: !SystemTools.checking
            onActivated: SystemTools.refresh()
        }
    }
}
