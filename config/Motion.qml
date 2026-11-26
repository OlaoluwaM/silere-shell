pragma Singleton

import QtQuick
import Quickshell
import "../services"

Singleton {
    readonly property bool _rm: ShellSettings.reduceMotion

    // one multiplier on every duration the shell animates with: above 1 the whole shell moves
    // slower. Waits that are not motion, like hoverLinger, stay outside it
    readonly property real pace: 1.62
    function ms(base: int): int { return _rm ? 0 : Math.round(base * pace) }

    // idle and reduce motion both mean "no visible motion"; taking both as arguments keeps it testable without a live idle state
    function allowsMotion(idle: bool, reduceMotion: bool): bool { return !idle && !reduceMotion }

    readonly property int instant: ms(80)
    readonly property int fast:    ms(130)
    readonly property int normal:  ms(165)
    readonly property int medium:  ms(190)
    readonly property int slow:    ms(260)
    readonly property int width:   ms(180)
    readonly property int color:   ms(160)
    // wallpaper-driven palette swaps (ADR 0001): deliberately ends inside awww's
    // 2s grow — finished colors over a finishing wallpaper reads as intent, and
    // matching the full 2s would drag text through muddy mid-contrast
    readonly property int palette: ms(400)

    readonly property int hoverIn:  ms(145)
    readonly property int hoverOut: ms(190)
    readonly property int press:    ms(90)
    readonly property real hoverScale: 1.018
    readonly property real pressScale: 0.965
    // how long a bar widget that opened out under the pointer stays open once the pointer has
    // left, so one that slips off and comes straight back finds it as it was. A wait rather
    // than motion, so reduce-motion does not scale it
    readonly property int hoverLinger: 200

    // one tactile acknowledgement for the whole shell; surfaces vary the amplitude, never the timing
    readonly property int bumpRise:   ms(70)
    readonly property int bumpSettle: ms(140)

    // shared curves keep surfaces, content and shadows on the same velocity profile. The trailing 1,1 is the bezier end point Qt requires
    readonly property var standard:        [0.2, 0.0, 0.0, 1.0, 1, 1]
    readonly property var standardDecel:   [0.0, 0.0, 0.0, 1.0, 1, 1]
    readonly property var standardAccel:   [0.3, 0.0, 1.0, 1.0, 1, 1]
    readonly property var emphasizedDecel: [0.05, 0.7, 0.1, 1.0, 1, 1]
    readonly property var emphasizedAccel: [0.3, 0.0, 0.8, 0.15, 1, 1]

    readonly property real popEdgeOffset: 6
    readonly property int  popIn:      ms(240)
    readonly property int  popInFade:  ms(170)
    readonly property int  popOut:     ms(160)
    readonly property int  popOutFade: ms(130)
    readonly property int  popSettle:  ms(240)

    // scroll physics are user-driven, not animation: they stay put under reduce-motion
    readonly property real flickDeceleration: 1800
    readonly property real flickVelocity:     2200

    // the menu panel's own geometry (outer edge, rail, nav slide, power drawer, height) rides
    // Motion.standard over one length in both directions, so every edge of the panel lands on the
    // same frame. The emphasized pair front-loads half the distance into the first frame, which
    // reads as a snap at the largest moving surface in the shell
    readonly property int menuResize: ms(260)
    // a list opening from a chevron (Settings dropdowns, the home page's pickers and device
    // lists); the panel follows its growth frame by frame, so it needs no shared clock
    // outside the pace: a list is revealed by a moving clip edge, which cuts through its rows for
    // as long as it runs, and a slower run only shows that for longer
    readonly property int listOpen:  _rm ? 0 : 320
    readonly property int listClose: _rm ? 0 : 220
    // quiet window a viewport must hold before scroll affordances trust it (see ScrollSettle)
    readonly property int panelSettle:   ms(180)
    // paces the calendar's month paging and the settings section enter. The panel itself resizes over
    // menuResize, which the section enter waits out on its own
    readonly property int pageIn:      ms(240)
    readonly property int pageOut:     ms(120)
    readonly property real pageOffset: 10
    // a tab swap fades through: the leaving page clears before the arriving one starts, so no frame
    // holds two pages at partial opacity. The exit is short because it only has to clear the way
    readonly property int pageSwapOut: ms(90)
    readonly property int pageSwapIn:  ms(210)
    // a wall-clock reading is taken before the animation driver's next tick starts the exit it times,
    // so a wait measured from it has to leave one frame, or the two pages overlap for a frame. This is
    // measurement slack rather than motion, so reduce-motion does not scale it
    readonly property int frameAllowance: 17

    readonly property int barMorph: ms(260)
}
