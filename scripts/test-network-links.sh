#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"
# The probe counts reads of /proc/net/dev and the listings they lead to, so a container or
# Wi-Fi change on the host mid-run would add to its counts. A network namespace of its own
# lists only lo; where unprivileged namespaces are off, it reads the host's list instead.
if [[ "${1:-}" != "--private-bus" && "${1:-}" != "--netns" ]] && unshare -Urn true 2>/dev/null; then
    exec unshare -Urn bash "$0" --netns "$@"
fi
[[ "${1:-}" != "--netns" ]] || shift
# a disposable shell registers the notification server; on the desktop bus it could claim the
# live daemon's name should that daemon drop out mid-run. The launcher never returns
if [[ "${1:-}" != "--private-bus" ]]; then
    _probe_private_bus "$0" "$@"
fi
shift
_probe_require_qs

# the trap goes first: a failed mktemp below would otherwise leave the
# directory already made behind
probe_root=""
probe_pid=""
cleanup() {
    _probe_stop "$probe_pid"
    [ -z "$probe_root" ] || rm -rf "$probe_root"
}
trap cleanup EXIT
trap 'exit 130' INT TERM

probe_root="$(mktemp -d "${TMPDIR:-/tmp}/silere-links.XXXXXX")"
mkdir -p "$probe_root/config/silere-shell" "$probe_root/runtime" "$probe_root/project" "$probe_root/bin"
chmod 0700 "$probe_root/runtime"
printf '{"__version":1}\n' > "$probe_root/config/silere-shell/settings.json"
_probe_project "$ROOT" scripts/probe-network-links.qml "$probe_root/project"
# the probe takes the session idle and back, which the real singleton would take from the compositor
rm "$probe_root/project/services"
cp -a "$ROOT/services" "$probe_root/project/services"
cp "$ROOT/scripts/fixtures/coordinator/Idle.qml" "$probe_root/project/services/Idle.qml"

# The stand-in ip follows ip-events, which the probe appends to, unless ip-mode says fail,
# when it refuses its netlink socket the way ip does. The stand-in nmcli lists one tunnel and
# answers its address from nm-address; both log what they were asked.
printf 'watch\n' > "$probe_root/ip-mode"
: > "$probe_root/ip-events"
printf '10.66.0.2/32\n' > "$probe_root/nm-address"
cat > "$probe_root/bin/ip" <<EOF2
#!/usr/bin/env bash
printf 'start %s %s\\n' "\$\$" "\$*" >> "$probe_root/ip-starts"
if [ "\$*" != "-o monitor link" ]; then
    printf '%s\\n' "\$*" >> "$probe_root/ip-other"
    echo "Argument \"\$1\" is unknown, try \"ip help\"." >&2
    exit 255
fi
if [ "\$(cat "$probe_root/ip-mode")" = fail ]; then
    echo "Cannot open netlink socket: Permission denied" >&2
    exit 1
fi
exec tail -n 0 -F "$probe_root/ip-events" 2>/dev/null
EOF2
cat > "$probe_root/bin/nmcli" <<EOF2
#!/usr/bin/env bash
case "\$*" in
    "-t -f TYPE,UUID,NAME connection show --active")
        printf 'list\\n' >> "$probe_root/nmcli-calls"
        printf 'wireguard:probe-uuid:Probe VPN\\n'
        ;;
    "-t -g IP4.ADDRESS connection show uuid probe-uuid")
        printf 'addr\\n' >> "$probe_root/nmcli-calls"
        cat "$probe_root/nm-address"
        ;;
    *)
        printf '%s\\n' "\$*" >> "$probe_root/nmcli-other"
        exit 1
        ;;
esac
EOF2
chmod +x "$probe_root/bin/ip" "$probe_root/bin/nmcli"

PATH="$probe_root/bin:$PATH" SILERE_LINKS_PROBE_ROOT="$probe_root" \
    XDG_CONFIG_HOME="$probe_root/config" XDG_STATE_HOME="$probe_root/config" XDG_CACHE_HOME="$probe_root/config/cache" \
    XDG_RUNTIME_DIR="$probe_root/runtime" HYPRLAND_INSTANCE_SIGNATURE="" NIRI_SOCKET="" \
    QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen \
    QT_NO_XDG_DESKTOP_PORTAL=1 setsid qs -p "$probe_root/project/probe-network-links.qml" --no-color >"$probe_root/probe.log" 2>&1 &
probe_pid=$!
_probe_wait "$probe_root/probe.log" "$probe_pid" 'PROBE-LINKS [pf]a[si][sl]ed' 900 0.1 || true

errs="$(_probe_errors "$probe_root/probe.log")"
if ! grep -q 'PROBE-LINKS passed' "$probe_root/probe.log" \
        || grep -q 'PROBE-FAIL' "$probe_root/probe.log" || [ -n "$errs" ]; then
    cat "$probe_root/probe.log" >&2
    echo 'FAIL: network link probe failed or logged a runtime error' >&2
    exit 1
fi
for stray in ip-other nmcli-other; do
    if [ -e "$probe_root/$stray" ]; then
        cat "$probe_root/$stray" >&2
        echo "FAIL: a stand-in saw a call the probe does not expect ($stray)" >&2
        exit 1
    fi
done
grep -oE 'PROBE-LINKS (event|deletion|quiet|deleting|stream|wake|fallback).*' "$probe_root/probe.log" || true
grep -oE 'PROBE-LINKS passed [0-9]+ checks' "$probe_root/probe.log" | tail -1
