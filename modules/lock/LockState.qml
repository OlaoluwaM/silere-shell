pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pam
import "../../services"

// What every output's lock surface shares: the text typed so far and the one PAM
// conversation, so a password typed on any output is checked once and unlocks them all.
// lock.qml owns the lock itself and decides what a success means.
Singleton {
    id: root

    // QML categories default to Debug, which would print PAM's prompt text into the
    // journal; lifecycle lines stay at Info and the conversation itself only at Debug
    readonly property LoggingCategory log: LoggingCategory {
        name: "silere.lock"
        defaultLogLevel: LoggingCategory.Info
    }

    // every output's field edits this one buffer, so switching outputs mid-word loses nothing
    property string typed: ""
    // raised by lock.qml once PAM succeeds, so every surface fades out before the unlock
    property bool unlocking: false
    // lock.qml reports the lock ready only once a field exists to type into
    property int fieldCount: 0

    property string message: ""
    property bool messageIsError: false
    property int failures: 0

    readonly property bool checking: _pam.active && !root._awaitingUser
    // a module asked for something other than the password; the field answers it instead
    readonly property bool prompting: _pam.active && root._awaitingUser
    // a visible prompt (a username, a code) wants to see what is typed
    readonly property bool promptVisible: root.prompting && _pam.responseVisible
    readonly property string prompt: root.prompting ? _pam.message : ""

    // held only between Enter and PAM's prompt for it, never longer
    property string _pending: ""
    // PAM asked something new (a one-time code, say) that the user has to type first
    property bool _awaitingUser: false
    // what a module said on its own (a lockout, a fingerprint request): the generic
    // outcome text must not bury it
    property string _note: ""
    // start() can fail synchronously after already reporting the failure through completed
    property bool _starting: false
    property real _startedAt: 0

    signal authenticated()
    // a wrong password or a lockout, for the field's shake
    signal rejected()

    // the design's pixels are at uiScale 1.0 and grow with it like the rest of the shell's
    // type; the lock ignores the output's size, so a big monitor gets the same clock as the
    // bar's text would get there
    function px(design: real): int {
        return Math.round(design * ShellSettings.uiScale)
    }

    // plain "JetBrains Mono", never the Nerd alias: nixos-config points "JetBrainsMono Nerd
    // Font" at another face for the bar
    readonly property string defaultFamily: "JetBrains Mono"
    // chosen once, when the font scan settles or a second has passed, so text never jumps
    // to another face while the lock is up
    property string fontFamily: ""
    readonly property bool fontReady: root.fontFamily.length > 0

    // a failed or absent scan counts as settled; FontScan only sets scanned on success and
    // takes up to 20s to time out, which is far too long to hold the clock back
    readonly property bool _scanSettled: FontScan.scanned || FontScan.lastError.length > 0
        || (SystemTools.ready && !SystemTools.hasFcList)
    readonly property bool _fontInputsSettled: ShellSettings.ready && root._scanSettled
    on_FontInputsSettledChanged: root._settleFont(false)

    function _settleFont(waitedOut: bool): void {
        if (root.fontReady || (!waitedOut && !root._fontInputsSettled)) return
        const wanted = ShellSettings.lockFontFamily.trim()
        if (wanted.length === 0 || wanted === root.defaultFamily) {
            root.fontFamily = root.defaultFamily
        } else if (FontScan.scanned && FontScan.families.indexOf(wanted) >= 0) {
            root.fontFamily = wanted
        } else {
            const why = FontScan.scanned ? "it is not installed"
                : FontScan.lastError.length > 0 ? "the font scan failed (" + FontScan.lastError + ")"
                : "the font scan did not answer within a second"
            console.warn(root.log, "silere-shell: lock font \"" + wanted + "\" unavailable, using "
                + root.defaultFamily + ":", why)
            root.fontFamily = root.defaultFamily
        }
    }

    Timer {
        interval: 1000
        running: !root.fontReady
        onTriggered: root._settleFont(true)
    }

    Component.onCompleted: {
        root._settleFont(false)
        root.refreshCapsLock()
    }

    // a one-second check rather than a SystemClock: a monotonic timer stalls across suspend,
    // and the lock is exactly what is on screen at resume, so a minute-precision clock could
    // show the time it went to sleep for up to a minute. An unchanged string notifies nobody
    property string clockText: ""
    property string dateText: ""

    function _tick(): void {
        const now = new Date()
        root.clockText = DateTime.clockText(now)
        root.dateText = Qt.formatDateTime(now, "dddd, MMMM d")
    }

    Timer {
        interval: 1000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root._tick()
    }

    Connections {
        target: ShellSettings
        function onClock12hChanged() { root._tick() }
    }

    // The output that draws the field. Keyboard focus decides, since that is where typing
    // lands: a surface whose window turns active claims it. Hyprland also reports
    // focusedmon while locked (moving the pointer onto an output focuses it and
    // hands its lock surface the keyboard), which covers the moment before any surface is
    // active. With neither, the first output.
    property string _claimedOutput: ""
    readonly property string primaryOutput: {
        const screens = Quickshell.screens
        const names = []
        for (let i = 0; i < screens.length; i++) names.push(screens[i].name)
        if (names.indexOf(root._claimedOutput) >= 0) return root._claimedOutput
        if (names.indexOf(Compositor.focusedMonitor) >= 0) return Compositor.focusedMonitor
        return names.length > 0 ? names[0] : ""
    }

    function claimOutput(name: string): void {
        if (name.length > 0) root._claimedOutput = name
    }

    Connections {
        target: Compositor
        function onFocusedMonitorChanged() { root.claimOutput(Compositor.focusedMonitor) }
    }

    // Quickshell exposes no modifier state, and a Caps Lock keypress alone misses the state
    // the lock started in. Hyprland's main keyboard reports its locked caps modifier, which
    // is the state the typed text gets, so it is asked at start, whenever Caps Lock is
    // pressed, and whenever a surface takes the keyboard (resume, hotplug): never polled.
    // Other compositors have no such query; the chip stays hidden there.
    property bool capsLock: false
    property bool _capsQueued: false

    function refreshCapsLock(): void {
        if (!Compositor.isHyprland) return
        if (_capsProc.running) {
            root._capsQueued = true
            return
        }
        _capsProc.exec(["hyprctl", "devices", "-j"])
    }

    BoundedProcess {
        id: _capsProc
        timeoutMs: 2000
        stdout: StdioCollector { id: _capsOut }
        onExited: (code) => {
            const again = root._capsQueued
            root._capsQueued = false
            if (_capsProc.completedSuccessfully(code)) {
                try {
                    const keyboards = JSON.parse(_capsOut.text).keyboards || []
                    const main = keyboards.find(k => k.main) ?? keyboards[0]
                    root.capsLock = !!(main && main.capsLock)
                } catch (e) {
                    console.debug(root.log, "silere-shell: unreadable keyboard state:", e)
                }
            }
            if (again) root.refreshCapsLock()
        }
    }

    Connections {
        target: Compositor
        function onIsHyprlandChanged() { root.refreshCapsLock() }
    }

    // an unattended half-typed password should not sit there for the next person to finish
    Timer {
        id: _idleClear
        interval: 10000
        onTriggered: if (!root.checking) root.typed = ""
    }

    onTypedChanged: {
        if (root.typed.length > 0) _idleClear.restart()
        else _idleClear.stop()
    }

    // Esc clears what is typed, and also backs out of a conversation: a module waiting on
    // something that never comes (a fingerprint reader, a hung helper) would otherwise hold
    // the field read-only for good. abort() reports no completed, so the state resets here
    function cancel(): void {
        if (root.unlocking) return
        if (_pam.active) {
            console.info(root.log, "silere-shell: authentication cancelled")
            root._abort()
            root._show("", false)
        } else {
            root.typed = ""
            root._show("", false)
        }
    }

    function _abort(): void {
        _pam.abort()
        root._starting = false
        root._pending = ""
        root._awaitingUser = false
        root._note = ""
    }

    // generous: a fingerprint module waits about 30s for a finger, and a slow PAM stack is
    // still better than a field nobody can type into
    Timer {
        interval: 60000
        running: root.checking
        onTriggered: {
            console.warn(root.log, "silere-shell: authentication gave no answer for a minute; cancelled")
            root._abort()
            root._show("Authentication timed out", true)
        }
    }

    function submit(): void {
        if (root.unlocking || root.typed.length === 0) return
        if (_pam.active && !root._awaitingUser) return
        const secret = root.typed
        root.typed = ""
        root.message = ""
        root.messageIsError = false
        if (_pam.active) {
            root._awaitingUser = false
            _pam.respond(secret)
            return
        }
        root._pending = secret
        root._note = ""
        root._startedAt = Date.now()
        console.info(root.log, "silere-shell: authentication started")
        root._starting = true
        const started = _pam.start()
        const reported = !root._starting
        root._starting = false
        if (!started) root._pending = ""
        if (!started && !reported) {
            console.warn(root.log, "silere-shell: authentication could not start")
            root._show("Authentication is unavailable", true)
        }
    }

    function _show(text: string, isError: bool): void {
        root.message = text
        root.messageIsError = isError
    }

    PamContext {
        id: _pam
        // a dedicated service, so the lock's PAM stack is the deployment's choice alone
        config: "silere-lock"

        onPamMessage: {
            console.debug(root.log, "silere-shell: pam message:", _pam.message,
                "(error:", _pam.messageIsError + ", wants a response:", _pam.responseRequired + ")")
            if (_pam.responseRequired) {
                const secret = root._pending
                root._pending = ""
                // the password answers only a hidden prompt; a visible one (a username, a
                // code) comes first in some stacks and must never be handed the password
                if (secret.length > 0 && !_pam.responseVisible) {
                    _pam.respond(secret)
                    return
                }
                // the prompt itself labels the field, so the line under it stays free
                root._awaitingUser = true
                root._show("", false)
            } else if (_pam.message.length > 0) {
                root._note = _pam.message
                root._show(_pam.message, _pam.messageIsError)
            }
        }

        onError: error => console.warn(root.log, "silere-shell: authentication could not run:",
            PamError.toString(error))

        onCompleted: result => {
            root._starting = false
            root._pending = ""
            root._awaitingUser = false
            const note = root._note
            root._note = ""
            console.info(root.log, "silere-shell: authentication finished:", PamResult.toString(result))
            console.debug(root.log, "silere-shell: the check took", Date.now() - root._startedAt, "ms")
            if (result === PamResult.Success) {
                root.failures = 0
                root._show("", false)
                root.authenticated()
            } else if (result === PamResult.Failed) {
                root.failures++
                root._show(note.length > 0 ? note
                    : "Wrong password · " + root.failures
                        + (root.failures === 1 ? " attempt" : " attempts"), true)
                root.rejected()
            } else if (result === PamResult.MaxTries) {
                root._show(note.length > 0 ? note : "Too many attempts", true)
                root.rejected()
            } else {
                root._show(note.length > 0 ? note : "Authentication is unavailable", true)
            }
        }
    }
}
