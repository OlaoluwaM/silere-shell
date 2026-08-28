import QtQuick
import "../../../config"
import "../../../services"

// Its own cluster, not a third PrivacyWidget chip: the mic chip states a passive
// privacy fact, but this pill is a control -- it carries a live timer and clicking
// it stops the capture -- so it takes the StatusActionPill wiring CaffeineWidget
// uses and its own widget group so the bar walls it off with dividers.
StatusActionPill {
    id: root

    show: Recording.recording

    // GNOME's screencast idiom: the dot blinks, the timer holds steady. The pulse
    // drives glyphOpacity rather than the whole pill (NetworkWidget's trick) so the
    // digits stay readable, and rather than glyphColor so it never retargets the
    // glyph's ColorFade behavior every tick.
    property real _blink: 1.0
    glyphOpacity: _blink

    // once asked to stop, the busy sweep takes over until the wrapper removes the
    // state file: wf-recorder keeps finalising for a moment after the SIGINT, and a
    // click that visibly changed nothing while the timer runs on reads as a miss
    property bool _stopping: false
    busy: _stopping
    onShowChanged: {
        if (!show) { _stopping = false; _stopSettle.stop() }
        else if (Recording.startedAtMs > 0) _elapsedLabel = _formatElapsed()
    }

    // bounded, because the stop command is detached with no result to watch: if it
    // fails or the recorder ignores it, the pill degrades to clickable again instead
    // of sweeping forever with the retry path locked out
    Timer {
        id: _stopSettle
        interval: 5000
        onTriggered: root._stopping = false
    }

    // the bare timer text says nothing about what is being timed
    accessibleName: "Recording, " + root._elapsedLabel
    glyph: "󰑊"
    glyphAlignReference: "󰑊"
    // Theme.error, not a private red: it's the same tier the vitals' critical chips and
    // Battery.critical ride, and a live recording is exactly that class of signal
    glyphColor: Theme.error
    textColor:  Theme.error

    // recording alone is not enough to be clickable: on a packaging without a stop
    // command this pill is a plain indicator, same dormancy as Recording itself
    interactive: show && !busy && Recording.canStop
    onActivated: {
        root._stopping = true
        _stopSettle.restart()
        Recording.stop()
    }

    property string _elapsedLabel: "00:00"
    text: _elapsedLabel
    // seeded synchronously too (NotificationCard's belt-and-suspenders): the Timer's
    // triggeredOnStart waits on the next animation tick, and a widget mounted while a
    // recording is already minutes in must not paint the placeholder first
    Component.onCompleted: if (Recording.startedAtMs > 0) _elapsedLabel = _formatElapsed()
    // minutes stay zero-padded and the reserve floor matches, so every sub-hour
    // label is the same five glyphs and the hour rollover is the one moment the
    // pill's width ever moves
    reserveText: "00:00"

    function _formatElapsed(): string {
        const total = Math.max(0, Math.round((Date.now() - Recording.startedAtMs) / 1000))
        const h = Math.floor(total / 3600)
        const m = String(Math.floor((total % 3600) / 60)).padStart(2, "0")
        const s = String(total % 60).padStart(2, "0")
        return h > 0 ? h + ":" + m + ":" + s : m + ":" + s
    }

    Timer {
        interval: 1000
        repeat: true
        // concealment and idle both pause the tick (the PulseLoop below's gate);
        // triggeredOnStart snaps the label current the moment recording starts,
        // the bar comes back, or the session wakes up
        running: root.show && Recording.startedAtMs > 0 && root.barActive && !Idle.isIdle
        triggeredOnStart: true
        onTriggered: root._elapsedLabel = root._formatElapsed()
    }

    // Discrete, not eased: an InOutSine pulse changes glyphOpacity on every vsync, so
    // the bar is damaged ~60x/s for the whole recording -- and the screen recorder
    // ends up encoding the very indicator that announces it is running. A two-state
    // flip only damages the bar on each toggle (~1.7/s, GNOME's own blink cadence),
    // and reduceMotion leaves it resting at 1.0 the same way the PulseLoop it replaces did.
    Timer {
        interval: 600
        repeat: true
        running: root.show && root.barActive && !Idle.isIdle && !ShellSettings.reduceMotion
        onRunningChanged: if (!running) root._blink = 1.0
        onTriggered: root._blink = (root._blink === 1.0) ? 0.25 : 1.0
    }
}
