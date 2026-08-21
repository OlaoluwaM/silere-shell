pragma Singleton

import QtQuick
import Quickshell

// Minute-duration helpers shared by the caffeine and DND duration pickers: one
// sanitizer for the packaged preset lists and one label shape, so the two duration
// UIs can never drift apart on formatting or on what counts as a valid preset.
Singleton {
    // comma-separated minutes -> deduped int list; 0 ("until turned off") is always
    // appended so it stays selectable even if a packaged list omits it
    function sanitizePresets(raw: string): var {
        const parts = String(raw || "").split(",")
        const seen = ({})
        const out = []
        for (let i = 0; i < parts.length; i++) {
            const t = parts[i].trim()
            if (!/^\d+$/.test(t)) continue
            const n = parseInt(t, 10)
            if (seen[n]) continue
            seen[n] = true
            out.push(n)
        }
        if (!seen[0]) out.push(0)
        return out
    }

    function label(minutes: int): string {
        if (minutes <= 0) return "Until turned off"
        if (minutes < 60) return minutes + "m"
        if (minutes % 60 === 0) return (minutes / 60) + "h"
        return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m"
    }
}
