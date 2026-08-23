pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    // every installed family: the validation set for a configured font. The
    // Nerd-only shortlist below exists separately because the picker previews
    // each option in its own face -- offering all of fc-list (a thousand-plus
    // families on a Noto-carrying system) would instantiate that many fonts.
    property list<string> families: []
    property list<string> nerdFamilies: []
    // icon coverage, not text coverage: Symbols Nerd Font counts here (glyph
    // fallback draws the icons) even though the picker never offers it
    property bool hasIconFont: false
    // true only after fc-list has exited cleanly, so "no families" can be told apart from "not asked yet"
    property bool scanned: false
    property bool scanning: false
    property string lastError: ""
    property bool _scanned: false

    function scan(force: bool): void {
        if ((!force && _scanned) || !SystemTools.hasFcList || _proc.running) return
        _scanned = true
        scanning = true
        lastError = ""
        _proc.running = true
    }

    function refresh(): void { scan(true) }

    // singletons are lazy: creation means the picker is on screen, and a menu-open signal would have fired before this object existed
    Component.onCompleted: scan(false)
    Connections {
        target: SystemTools
        function onReadyChanged() { if (SystemTools.ready) root.scan(false) }
        function onCheckingChanged() {
            if (!SystemTools.checking && SystemTools.ready) root.refresh()
        }
        function onHasFcListChanged() {
            if (SystemTools.hasFcList) {
                if (SystemTools.ready) root.scan(false)
            } else if (SystemTools.ready) {
                root._scanned = false
                root.scanned = false
                root.scanning = false
                root.families = []
                root.nerdFamilies = []
                root.hasIconFont = false
            }
        }
    }

    Process {
        id: _proc
        // %{family} not %{family[0]}: fontconfig lists aliases in one comma-separated value, and slot zero drops installed fonts
        command: ["fc-list", "--format", "%{family}\n"]
        stdout: StdioCollector { id: _out }
        onExited: (code) => {
            root.scanning = false
            if (code !== 0) {
                root._scanned = false
                root.lastError = "Font scan failed (exit " + code + ")"
                return
            }
            // Font family aliases are external input; null-prototype tables
            // keep names such as "constructor" from colliding with JS built-ins.
            const variants = Object.create(null)
            const all = Object.create(null)
            let icons = false
            const lines = (_out.text || "").split("\n")
            for (let i = 0; i < lines.length; i++) {
                const aliases = lines[i].split(",")
                for (let j = 0; j < aliases.length; j++) {
                    const f = aliases[j].trim()
                    if (f.length === 0) continue
                    all[f] = true
                    const match = /^(.*) Nerd Font(?: (Mono))?$/.exec(f)
                    if (!match) continue
                    icons = true
                    if (match[1] === "Symbols") continue
                    const base = match[1]
                    const variant = match[2] || "Regular"
                    if (!variants[base]) variants[base] = Object.create(null)
                    variants[base][variant] = f
                }
            }
            const out = []
            for (const base in variants) {
                const family = variants[base]
                if (family.Regular) out.push(family.Regular)
                else if (family.Mono) out.push(family.Mono)
            }
            const byName = (a, b) => a.localeCompare(b, undefined, { sensitivity: "base" })
            out.sort(byName)
            const everything = Object.keys(all)
            everything.sort(byName)
            root.families = everything
            root.nerdFamilies = out
            root.hasIconFont = icons
            root.scanned = true
            root.lastError = ""
        }
    }
}
