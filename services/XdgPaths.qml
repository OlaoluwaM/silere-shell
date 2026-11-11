pragma Singleton

import QtQuick
import Quickshell

// whitespace is legal in a unix path; trimming it makes the shell disagree with scripts/lib/xdg.sh
Singleton {
    id: root

    function resolveHome(configured, home, fallback: string): string {
        const explicit = String(configured ?? "")
        if (explicit.startsWith("/")) return explicit
        const base = String(home ?? "")
        return base.startsWith("/") ? base + "/" + fallback : ""
    }

    readonly property string configHome: root.resolveHome(
        Quickshell.env("XDG_CONFIG_HOME"), Quickshell.env("HOME"), ".config")
}
