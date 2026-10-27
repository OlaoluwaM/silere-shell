// Read before the engine starts: the lock shares the shell's config directory and must
// never be the process that writes, backs up or re-permissions the user's settings.
//@ pragma Env SILERE_SETTINGS_READ_ONLY = 1
// One surface per output animates at once, the same multi-window case that makes shell.qml
// default to the elapsed-time driver; DefaultEnv still lets a user or driver override it.
// No UseQApplication: that serves the tray's platform menus, and the lock has no tray.
//@ pragma DefaultEnv QSG_USE_SIMPLE_ANIMATION_DRIVER = 1
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "modules/lock"
import "config"

// The lock screen's own short-lived process, started for each lock by nixos-config's
// silere-lock wrapper and gone once the session is unlocked. The wrapper reads its end
// from the exit status, so every code means one thing:
//   0  the user unlocked
//   1  the lock could not even be requested (no ext-session-lock-v1)
//   2  the lock ended without an unlock: the compositor finished it, whether refusing it
//      up front or ending it later, or a surface failed to build
//   3  refused to lock: not started by the wrapper, or sandboxed
// A QML load error makes qs exit 255 on its own.
//
// Singletons start on first use, so this process runs only the ones it reaches, and it may
// reach only those that claim no session-wide resource. Allowed: LockState, LockPower,
// Theme, Settings, Metrics, Motion, MatugenTheme, GlassSample, GeneratedDefaults,
// ShellSettings, ConfigStore, XdgPaths, FontScan, SystemTools, Compositor with its Hyprland
// or Niri backend, HyprDispatch, SafeText, Monitors and Idle, which the field already
// reaches; IconResolver, for the wallpaper's file URL (it touches DesktopEntries only when
// asked for an app icon, which the lock never does); and Battery, which pulls in MenuState
// and the small state singletons it reads. The clock formats through ClockFormat.js rather
// than DateTime, whose catch-up watchers would start Network and TimeZoneWatch here for
// nothing. Their IPC handlers sit on this
// instance's own socket, and every write the settings layer would make is gated by the
// read-only pragma above. Never reach anything that owns a session-wide D-Bus name or
// service (the notification server, the tray watcher, MPRIS) or another session-wide
// resource; Recording, for one, creates its state directory whenever the bar shows its
// widget.
ShellRoot {
    id: root

    // the wrapper alone sets SILERE_LOCK_WRAPPER; a bare `qs -p lock.qml` in the dev loop
    // would otherwise lock the real session, and nothing can unlock it without the PAM service
    readonly property bool sandboxed: String(Quickshell.env("SILERE_SANDBOX") || "").length > 0
    readonly property bool allowed: Quickshell.env("SILERE_LOCK_WRAPPER") === "1" && !root.sandboxed
    // wins over everything: the surface content in a plain window, and nothing locks
    readonly property bool preview: Quickshell.env("SILERE_LOCK_PREVIEW") === "1"
    readonly property string readyFile: String(Quickshell.env("SILERE_LOCK_READY_FILE") || "")

    property bool unlockRequested: false
    // set once the lock is requested, so its creation is never mistaken for its end
    property bool _taken: false
    property bool _readySent: false
    property bool _exiting: false

    // the wrapper waits for this, not for `hyprctl locked`, which turns true before a frame
    readonly property bool ready: _lock.secure && LockState.fieldCount > 0

    // a file save must never rebuild a live lock
    settings.watchFiles: false

    // the power card reaches systemd only from a real lock; a preview or sandboxed run gets
    // a stand-in, so the dev loop can never suspend or reboot the machine it runs on
    Binding {
        target: LockPower
        property: "live"
        value: root.allowed && !root.preview
    }

    function _exit(code: int, why: string): void {
        if (root._exiting) return
        root._exiting = true
        if (code === 0) console.info(LockState.log, "silere-shell: exiting with 0:", why)
        else console.warn(LockState.log, "silere-shell: exiting with " + code + ":", why)
        Qt.exit(code)
    }

    // runs after Quickshell has realized the lock, which happens once creation completes
    function _start(): void {
        if (root.preview) {
            console.info(LockState.log, "silere-shell: previewing the lock in a window; nothing locks")
            return
        }
        if (root.sandboxed) {
            root._exit(3, "SILERE_SANDBOX is set, and a sandboxed run never locks the session")
            return
        }
        if (!root.allowed) {
            root._exit(3, "not started by the silere-lock wrapper (SILERE_LOCK_WRAPPER is not 1);"
                + " set SILERE_LOCK_PREVIEW=1 to preview the lock instead")
            return
        }
        if (!_lock.locked) {
            root._exit(1, "the session lock could not be requested; the compositor may lack ext-session-lock-v1")
            return
        }
        root._taken = true
        console.info(LockState.log, "silere-shell: session lock requested")
    }

    function _onLockState(): void {
        if (!root._taken || _lock.locked) return
        if (root.unlockRequested) {
            // Quickshell reports one unlock twice, once from inside its own teardown
            if (_exitAfterUnlock.running) return
            console.info(LockState.log, "silere-shell: session unlocked")
            _exitAfterUnlock.start()
        } else {
            root._exit(2, "the lock ended without an unlock: the compositor finished it, or a surface failed")
        }
    }

    function _signalReady(): void {
        if (root._readySent) return
        root._readySent = true
        console.info(LockState.log, "silere-shell: lock confirmed secure with the field up after",
            Date.now() - Quickshell.launchTime.getTime(), "ms")
        if (root.readyFile.length === 0) {
            console.warn(LockState.log, "silere-shell: SILERE_LOCK_READY_FILE is unset; no ready file written")
            return
        }
        _readyFile.setText("ready\n")
    }

    onReadyChanged: if (root.ready) root._signalReady()

    Component.onCompleted: Qt.callLater(root._start)

    Connections {
        target: LockState
        function onAuthenticated() {
            if (root.preview) {
                console.info(LockState.log, "silere-shell: preview authenticated; nothing to unlock")
                return
            }
            if (!root._taken || LockState.unlocking) return
            LockState.unlocking = true
            _unlockAfterFade.start()
        }
    }

    WlSessionLock {
        id: _lock

        // bound, never a literal true: Quickshell takes the lock as soon as loading finishes,
        // before _start can check anything, so the binding is the only thing that can refuse
        locked: root.allowed && !root.preview && !root.unlockRequested

        onLockStateChanged: root._onLockState()
        onSecureStateChanged: {
            if (_lock.secure) console.info(LockState.log, "silere-shell: compositor confirmed the lock")
        }

        // Quickshell builds one per output and adds or drops them on hotplug. Kept trivial with
        // no required properties: a surface that fails to build unlocks the whole session
        WlSessionLockSurface {
            id: _surface
            color: Theme.background

            onVisibleChanged: {
                if (_surface.visible) console.info(LockState.log, "silere-shell: lock surface shown on",
                    _surface.screen ? _surface.screen.name : "an unnamed output")
            }

            LockContent {
                anchors.fill: parent
                outputName: _surface.screen ? _surface.screen.name : ""
            }
        }
    }

    LazyLoader {
        active: root.preview
        component: FloatingWindow {
            title: "Silere lock preview"
            // the design's logical size, pinned: a tiling compositor floats a window that
            // cannot resize, so the preview stays comparable with the mockup
            implicitWidth: 1440
            implicitHeight: 900
            minimumSize: Qt.size(1440, 900)
            maximumSize: Qt.size(1440, 900)
            color: Theme.background

            LockContent {
                anchors.fill: parent
                previewWindow: true
            }
        }
    }

    // A direct write, past the read-only settings gate: this is the wrapper's handshake file,
    // not a settings file, and the wrapper made its directory fresh for this lock
    FileView {
        id: _readyFile
        path: root.readyFile
        preload: false
        atomicWrites: true
        blockWrites: true
        printErrors: false
        onSaved: console.info(LockState.log, "silere-shell: ready file written")
        onSaveFailed: error => console.warn(LockState.log, "silere-shell: could not write the ready file:",
            FileViewError.toString(error))
    }

    Timer {
        id: _unlockAfterFade
        interval: Motion.popOutFade + Motion.frameAllowance
        onTriggered: root.unlockRequested = true
    }

    // one frame after the unlock, so the request is flushed to the compositor before exit
    Timer {
        id: _exitAfterUnlock
        interval: Motion.frameAllowance
        onTriggered: root._exit(0, "the user unlocked")
    }
}
