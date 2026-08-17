import QtQuick
import Quickshell
import Quickshell.Io

// Generic launch mechanics for a user-declared command template (e.g.
// "nm-connection-editor --edit {uuid}" or plain "blueman-manager"): whitespace
// split, {name}-style placeholder substitution, an argv[0] PATH probe, and a
// detached exec. WifiProfile's editor launch and the Bluetooth manager escape
// hatch each own one instance pointed at their own template/cooldown instead
// of reimplementing probing and substitution twice. QtObject, not Item: this
// never needs geometry or a scene-graph node, only child Timer/Process state.
QtObject {
    id: root

    property string template: ""
    // guards a bar-pill click and a details-row click landing back to back from
    // spawning two editor windows; a couple of seconds is long enough to absorb
    // a double click but short enough nobody notices it on a deliberate retry
    property int cooldownMs: 1500

    readonly property list<string> argv: root._parse(root.template)
    readonly property string argv0: root.argv.length > 0 ? root.argv[0] : ""
    property bool _toolFound: false
    readonly property bool available: root.argv0.length > 0 && root._toolFound
    property bool _cooling: false
    readonly property bool onCooldown: root._cooling
    property string lastError: ""

    function _parse(t: string): var {
        return String(t || "").trim().split(/\s+/).filter(s => s.length > 0)
    }

    function usesPlaceholder(name: string): bool {
        const needle = "{" + name + "}"
        return root.argv.some(a => a.indexOf(needle) >= 0)
    }

    // placeholderName/value/pattern are omitted entirely for a template with no
    // target to substitute; when they are given, value must be non-empty and
    // pass pattern (the caller's own validation for that value's shape — e.g. a
    // uuid regex) or the launch is refused instead of running with a bad target
    function launch(placeholderName: string, value: string, pattern: var): bool {
        if (!root.available || root._cooling) return false
        root.lastError = ""
        let out = root.argv.slice()
        if (placeholderName && placeholderName.length > 0) {
            const needle = "{" + placeholderName + "}"
            if (out.some(a => a.indexOf(needle) >= 0)) {
                if (!value || value.length === 0 || (pattern && !pattern.test(value))) {
                    root.lastError = "launch target is not available"
                    return false
                }
                out = out.map(a => a.split(needle).join(value))
            }
        }
        root._cooling = true
        root._cooldown.restart()
        Quickshell.execDetached(out)
        return true
    }

    // QtObject has no default property, so children are held as named properties
    // instead of bare nested declarations
    readonly property Timer _cooldown: Timer {
        interval: root.cooldownMs
        onTriggered: root._cooling = false
    }

    // bumped on every probe request so a result belonging to a superseded template
    // (exec() restarts the process rather than queuing a second one, and the old
    // invocation's own exit still fires first) never lands as _toolFound
    property int _probeGen: 0

    function _probe(): void {
        root._probeGen++
        if (root.argv0.length === 0) { root._toolFound = false; return }
        root._probeProc.exec(["bash", "-c", "command -v -- \"$1\" >/dev/null 2>&1", "bash", root.argv0])
    }

    readonly property BoundedProcess _probeProc: BoundedProcess {
        timeoutMs: 5000
        property int _gen: 0
        onRunningChanged: if (running) _gen = root._probeGen
        onExited: (code) => {
            if (_probeProc._gen === root._probeGen) root._toolFound = (code === 0)
        }
    }

    // the initial `template:` binding already fires this once at construction (its
    // value differs from the "" default), so a separate Component.onCompleted probe
    // would just be a second, redundant PATH check for the same command
    onTemplateChanged: root._probe()
}
