pragma Singleton

import QtQuick
import Quickshell

// The bar widget the pointer was last on. A hover reveal stays out for Motion.hoverLinger once
// the pointer leaves, which rides out a slip off the widget and back. A pointer that has gone
// on to another widget is no slip: the one it left folds at once, so two reveals are not out
// together and the fold starts as the pointer arrives, not after it has settled.
//
// Every bar widget with a hover handler of its own writes itself here as the pointer arrives
// (docs/forking.md). Qt tells the widget the pointer reached before the one it left whenever
// a single move carries it across, and after it when a move lands in the gap between them, so
// a revealing widget asks elsewhere() both as its hover ends and when this changes
Singleton {
    id: root

    property QtObject widget: null

    // a widget that was destroyed reads null here, which is nowhere rather than elsewhere
    function elsewhere(from: QtObject): bool {
        return root.widget !== null && root.widget !== from
    }
}
