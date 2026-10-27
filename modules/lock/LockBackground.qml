import QtQuick
import QtQuick.Effects
import "../../config"
import "../../services"

// The wallpaper behind the lock, blurred and dimmed. Hyprland's layer-rule blur never
// reaches a session-lock surface, so the blur is drawn here. Until the image loads, and
// for good when there is none or it fails, the surface's own background colour shows.
Item {
    id: root

    property string outputName: ""

    // the process lives for one lock, so the source is read fresh each time; the cache
    // stays off because wallpaper-set renames a new file over this same path
    Image {
        id: _wallpaper
        anchors.fill: parent
        // not before the surface has its size, or the decode runs twice: once for nothing
        source: root.width > 0 && root.height > 0 ? IconResolver.localSource(ShellSettings.lockWallpaper) : ""
        // half the output's size is already more detail than a blur this strong keeps, at a
        // quarter of the memory per output
        sourceSize.width: Math.ceil(root.width / 2)
        sourceSize.height: Math.ceil(root.height / 2)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
        onStatusChanged: {
            if (_wallpaper.status === Image.Error)
                console.warn(LockState.log, "silere-shell: lock wallpaper failed to load on",
                    (root.outputName || "the preview") + ":", ShellSettings.lockWallpaper)
        }
    }

    MultiEffect {
        anchors.fill: parent
        source: _wallpaper
        visible: _wallpaper.status === Image.Ready
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1.0
        blurMax: 64
    }

    // dims toward black rather than the palette's background, so a light wallpaper still
    // leaves the clock legible
    Rectangle {
        anchors.fill: parent
        visible: _wallpaper.status === Image.Ready
        color: Theme.withAlpha(Theme.mix(Theme.background, Theme.depthSink, 0.5), 0.42)
    }
}
