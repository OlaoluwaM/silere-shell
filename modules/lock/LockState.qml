pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Services.Pam

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
                root._awaitingUser = true
                root._show(_pam.message, false)
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
                    : root.failures === 1 ? "Wrong password"
                    : "Wrong password, " + root.failures + " attempts", true)
            } else if (result === PamResult.MaxTries) {
                root._show(note.length > 0 ? note : "Too many attempts", true)
            } else {
                root._show(note.length > 0 ? note : "Authentication is unavailable", true)
            }
        }
    }
}
