import QtQuick
import "../../../services"
import "../controls"

Column {
    width: parent ? parent.width : 0
    spacing: 0

    SectionLabel { label: "NOW PLAYING"; first: true }
    SettingsCard {
        ToggleRow {
            glyph: "󰎇"; label: "Artist and title"
            checked: ShellSettings.mediaWidgetFormat === "artist-title"
            onToggled: nextChecked => ShellSettings.mediaWidgetFormat =
                nextChecked ? "artist-title" : "title"
        }
        ToggleRow {
            glyph: "󰐊"; label: "Playback status"
            description: "Show play state and progress"
            key: "mediaWidgetHelper"
        }
        ToggleRow {
            glyph: "󰥶"; label: "Cover art from the web"
            description: "Fetch art a player links off-machine"
            key: "mediaRemoteArt"
        }
    }

}
