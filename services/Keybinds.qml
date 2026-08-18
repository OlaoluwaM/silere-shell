pragma Singleton

// Dormant unless GeneratedDefaults.keybindsFile is non-empty -- same packaging-only
// contract as Recording.qml's recordingStateFile. The Nix side writes a static JSON
// array of {keys, desc, group} once per system generation, in the order the popup
// should display it (groups and their rows both arrive in intended display order), so
// there is nothing here to re-sort. watchChanges stays off: a generation never rewrites
// this file under a running shell. reload() is still exposed and called by the popup on
// every open -- cheap insurance for a same-session rebuild, not a live-watch substitute.

import QtQuick
import Quickshell
import Quickshell.Io
import "../config"

Singleton {
    id: root

    readonly property string _path: ShellSettings.keybindsFile
    // entries.length is part of the gate, not just a parsed flag: a syntactically
    // valid but empty array must dormant the popup exactly like a missing/malformed
    // file, or the IPC toggle's "never opens empty" contract has a hole
    readonly property bool available: root._path.length > 0 && root._parsed
        && root.entries.length > 0

    property bool _parsed: false
    property var entries: []
    // first-seen order, not alphabetical -- the Nix side controls display order by how
    // it writes the array, this just mirrors that into a de-duplicated group list
    property var groups: []

    function _applyEntries(raw: var): void {
        const list = []
        const seenGroups = []
        const groupSeen = ({})
        for (let i = 0; i < raw.length; i++) {
            const e = raw[i]
            if (!e || typeof e !== "object") continue
            const keys = typeof e.keys === "string" ? e.keys.trim() : ""
            const desc = typeof e.desc === "string" ? e.desc.trim() : ""
            const group = typeof e.group === "string" && e.group.trim().length > 0
                ? e.group.trim() : "Other"
            if (keys.length === 0 || desc.length === 0) continue
            list.push({ keys: keys, desc: desc, group: group })
            if (!groupSeen[group]) { groupSeen[group] = true; seenGroups.push(group) }
        }
        root.entries = list
        root.groups = seenGroups
    }

    function _clear(): void {
        root._parsed = false
        root.entries = []
        root.groups = []
    }

    function _applyText(text: string): void {
        try {
            const parsed = JSON.parse(text || "[]")
            if (!Array.isArray(parsed)) throw new Error("keybindsFile must be a JSON array")
            root._applyEntries(parsed)
            root._parsed = true
        } catch (e) {
            root._clear()
            console.warn("silere-shell: failed to parse keybindsFile, keybinds popup stays dormant:", String(e))
        }
    }

    // reload() is a no-op while dormant so the popup (which calls it unconditionally on
    // open) never has to check available first
    function reload(): void {
        if (root._path.length > 0) _file.reload()
    }

    // keybindsFile is schema-writable (sec: "-", like recordingStateFile), so a hand-edited
    // settings.json can blank it out while the shell is live. FileView's own onLoaded/
    // onLoadFailed don't fire for a path going TO "", so without this the popup -- if
    // already open at that instant -- would keep showing the last successfully loaded
    // entries instead of going dormant. Mirrors Recording.qml's on_PathChanged restat.
    on_PathChanged: if (root._path.length === 0) root._clear()

    FileView {
        id: _file
        path: root._path.length > 0 ? root._path : ""
        watchChanges: false
        blockLoading: false
        blockAllReads: false
        printErrors: false
        onLoaded: root._applyText(_file.text())
        onLoadFailed: (error) => {
            root._clear()
            if (root._path.length > 0)
                console.warn("silere-shell: could not read keybindsFile, keybinds popup stays dormant:", error)
        }
    }

    // mirrors Caffeine.qml's toggle IpcHandler: `qs ipc call keybinds toggle` drives the
    // same state singleton (KeybindsPopupState) a Hyprland chord would target. Dormant/
    // unreadable stays a no-op so the popup can never open empty.
    IpcHandler {
        target: "keybinds"
        function toggle(): void { if (root.available) KeybindsPopupState.toggle() }
    }
}
