.pragma library

// The power actions' words and glyphs, shared by the desktop's countdown card and the lock's
// power card so the two read the same. Pure data, so the lock process can read it without
// starting PowerActionState, which belongs to the shell's process.
function table(kinds) {
    const all = {
        logout:   { label: "Log out",   glyph: "󰍃", phrase: "Logging out",  failTitle: "Log out failed" },
        suspend:  { label: "Suspend",   glyph: "󰒲", phrase: "Suspending",   failTitle: "Suspend failed" },
        reboot:   { label: "Reboot",    glyph: "󰑐", phrase: "Rebooting",    failTitle: "Reboot failed" },
        poweroff: { label: "Power off", glyph: "󰐥", phrase: "Powering off", failTitle: "Shut down failed" }
    }
    const out = {}
    for (const kind of kinds) out[kind] = all[kind]
    return out
}
