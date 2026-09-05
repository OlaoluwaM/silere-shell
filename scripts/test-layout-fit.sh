#!/usr/bin/env bash
set -euo pipefail
export LC_ALL=C

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/probe-lib.sh"

trap 'exit 130' INT TERM

# A settings row can build cleanly and still lose its own label: the surface probe
# only proves the section instantiates. This builds each one at the width the
# detail pane actually ships at and fails if Qt marks any text truncated.
#
# 388 is derived, not chosen: the settings panel targets 632, the rail takes 44
# plus a nav column capped at 160, and the pane pads 20 a side — see
# MenuWindow's panelW/navW/contentPad. Narrower than this only happens on a
# screen under roughly 700px wide, where status text is expected to elide.
CONTENT_WIDTH="${FIT_W:-388}"
PROBE="scripts/probe-fit.qml"

_probe_require_qs
[ -f "$PROBE" ] || { echo "FAIL: $PROBE missing" >&2; exit 1; }

# Every width here is a text measurement, so it is only meaningful against the font
# the shell actually ships with. Without it Settings.font falls back to whatever
# exists and a substitute's advance widths condemn labels that fit fine in practice —
# a bare CI container measured "Hidden until this is installed" at twice its real
# width. fc-match always answers, so the returned family has to be compared.
WANT_FONT="${FIT_FONT:-JetBrainsMono Nerd Font}"
if ! command -v fc-match >/dev/null 2>&1; then
    if [ "${SILERE_REQUIRE_QML_TOOLS:-0}" = "1" ]; then
        echo "FAIL: fontconfig (fc-match) not found; strict validation cannot measure the shipped font" >&2
        exit 1
    fi
    echo "SKIP: fontconfig missing, cannot confirm the shipped font" >&2
    exit 0
fi
have_font="$(fc-match -f '%{family[0]}' "$WANT_FONT" 2>/dev/null || true)"
if [ "$have_font" != "$WANT_FONT" ]; then
    if [ "${SILERE_REQUIRE_QML_TOOLS:-0}" = "1" ]; then
        echo "FAIL: $WANT_FONT not installed (got \"${have_font:-none}\"); strict validation cannot measure a substitute" >&2
        exit 1
    fi
    echo "SKIP: $WANT_FONT not installed (got \"${have_font:-none}\"); text metrics would measure a substitute" >&2
    exit 0
fi

list="$(find modules/menu/settings -name 'Settings*Section.qml' | sort)"
[ -n "$list" ] || { echo "FAIL: no settings sections found" >&2; exit 1; }

# The other tabs are narrower: 400 panel less the 44 rail and 12 of pad a side. The nav
# column ships at its 160 cap. HomePage stays out on purpose — its status lines carry
# network and device names from outside the shell, which are meant to elide.
list="$list
modules/menu/RecentPage.qml|332
modules/menu/PowerRailContent.qml|332
modules/menu/VitalsStrip.qml|332
modules/menu/SettingsNav.qml|160"

scratch="$(mktemp -d "${TMPDIR:-/tmp}/silere-layout.XXXXXX")"
log="$(mktemp "${TMPDIR:-/tmp}/silere-layout.XXXXXX.log")"
probe_pid=""
cleanup() {
    _probe_stop "${probe_pid:-}"
    rm -f "$log"
    rm -rf "$scratch"
}
trap 'cleanup; exit 130' INT TERM
trap cleanup EXIT

probe_project="$scratch/project"
mkdir -p "$probe_project"
_probe_project "$ROOT" "$PROBE" "$probe_project"

status=0
# Both ends of the supported type range: labels are sized off font metrics, so the
# largest scale is where a row first runs out of room.
for scale in 1.0 1.15; do
    conf="$scratch/$scale"
    runtime="$scratch/runtime-$scale"
    mkdir -p "$conf/silere-shell"
    mkdir -p "$runtime"
    chmod 0700 "$runtime"
    printf '{ "__version": 1, "uiScale": %s }\n' "$scale" > "$conf/silere-shell/settings.json"

    : > "$log"
    FIT_ROOT="$probe_project" FIT_LIST="$list" FIT_W="$CONTENT_WIDTH" \
        XDG_CONFIG_HOME="$conf" XDG_STATE_HOME="$conf" XDG_RUNTIME_DIR="$runtime" \
        QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 \
        qs -p "$probe_project/${PROBE##*/}" --no-color >"$log" 2>&1 &
    probe_pid=$!
    _probe_wait "$log" "$probe_pid" 'FIT-DONE' 240 0.5 || true

    if ! grep -q 'FIT-DONE' "$log" 2>/dev/null; then
        cat "$log" >&2
        echo "FAIL: layout fit probe did not finish at scale $scale" >&2
        status=1
        _probe_stop "$probe_pid"
        probe_pid=""
        continue
    fi
    if grep -qE "FIT-TRUNC|FIT-CLIP|FIT-WIDE|FIT-FAIL" "$log"; then
        grep -E "FIT-TRUNC|FIT-CLIP|FIT-WIDE|FIT-FAIL" "$log" | sed 's/^/  /' >&2
        status=1
    fi
    errs="$(_probe_errors "$log")"
    if [ -n "$errs" ]; then
        printf '%s\n' "$errs" | sed 's/^/  /' >&2
        status=1
    fi
    done_line="$(grep -o 'FIT-DONE.*' "$log" | tail -1)"
    # a scan that reaches no text reports zero findings for the wrong reason
    if [ "$(printf '%s' "$done_line" | sed -n 's/.*texts \([0-9]*\).*/\1/p')" -lt 200 ]; then
        echo "FAIL: layout fit probe scanned too little text at scale $scale: $done_line" >&2
        status=1
    # likewise for the clip check: no item measured against a clipping ancestor
    # means the overflow scan reported clean because it never ran
    elif [ "$(printf '%s' "$done_line" | sed -n 's/.*clipped \([0-9]*\).*/\1/p')" -lt 500 ]; then
        echo "FAIL: layout fit probe measured too few clipped items at scale $scale: $done_line" >&2
        status=1
    fi
    _probe_stop "$probe_pid"
    probe_pid=""
done

if [ "$status" -eq 0 ]; then
    echo "menu labels fit at the widths they ship at across the type range"
fi
exit "$status"
