import QtQuick
import "../../../config"
import "../../../services"
import "../../common"

// Three independent threshold chips, not one StatusActionPill: CPU/MEM/TEMP each has
// its own value and its own hysteresis, so each needs to appear and disappear on its
// own instead of sharing one glyph slot. TEMP rides CpuTemp's existing hot/critical
// state (same tempHotThreshold, already debounced and clearing at threshold-5) rather
// than re-deriving it; CPU/MEM have no such state anywhere else, so it's tracked here
// against ShellSettings.cpuHotPercent/memHotPercent with the same threshold-5 clear.
Item {
    id: root

    property bool compact: ShellSettings.barCompact
    readonly property int _hysteresis: 5

    readonly property real _cpuValue: SysInfo.cpuPct * 100
    readonly property real _memValue: SysInfo.memTotalKb > 0 ? SysInfo.memPct * 100 : 0

    property bool _cpuHot: false
    property bool _memHot: false
    readonly property bool _tempHot: CpuTemp.available && CpuTemp.hot

    readonly property bool show: root._cpuHot || root._memHot || root._tempHot
    property real _baseOpacity: show ? 1.0 : 0.0
    readonly property bool layoutVisible: show || _baseOpacity > 0.001

    visible: layoutVisible
    opacity: _baseOpacity
    implicitWidth: _row.implicitWidth
    implicitHeight: Metrics.barRowHeight

    on_CpuValueChanged: root._syncCpuHot()
    on_MemValueChanged: root._syncMemHot()
    Component.onCompleted: { root._syncCpuHot(); root._syncMemHot() }

    MotionBehavior on _baseOpacity { NumberAnimation { duration: Motion.medium; easing.type: Easing.OutCubic } }

    Connections {
        target: ShellSettings
        function onCpuHotPercentChanged() { root._syncCpuHot() }
        function onMemHotPercentChanged() { root._syncMemHot() }
    }

    Row {
        id: _row
        anchors.verticalCenter: parent.verticalCenter
        spacing: Metrics.pillGapFor(root.compact)

        Pill {
            id: _cpuChip
            anchors.verticalCenter: parent.verticalCenter
            height: root.height
            compact: root.compact
            interactive: false
            animateGlyph: false
            shrinkDelay: 0
            collapsed: !root._cpuHot
            visible: root._cpuHot || opacity > 0.001
            opacity: root._cpuHot ? 1.0 : 0.0
            scale: root._cpuHot ? 1.0 : 0.7
            transformOrigin: Item.Center
            MotionBehavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            MotionBehavior on scale   { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }
            glyph: "󰻠"
            glyphAlignReference: "󰻠"
            glyphPixelSize: Settings.iconSize + 1
            glyphColor: Theme.warning
            textColor: Theme.warning
            text: Math.round(root._cpuValue) + "%"
        }

        Pill {
            id: _memChip
            anchors.verticalCenter: parent.verticalCenter
            height: root.height
            compact: root.compact
            interactive: false
            animateGlyph: false
            shrinkDelay: 0
            collapsed: !root._memHot
            visible: root._memHot || opacity > 0.001
            opacity: root._memHot ? 1.0 : 0.0
            scale: root._memHot ? 1.0 : 0.7
            transformOrigin: Item.Center
            MotionBehavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            MotionBehavior on scale   { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }
            glyph: "󰘚"
            glyphAlignReference: "󰘚"
            glyphPixelSize: Settings.iconSize + 1
            glyphColor: Theme.warning
            textColor: Theme.warning
            text: Math.round(root._memValue) + "%"
        }

        Pill {
            id: _tempChip
            anchors.verticalCenter: parent.verticalCenter
            height: root.height
            compact: root.compact
            interactive: false
            animateGlyph: false
            shrinkDelay: 0
            collapsed: !root._tempHot
            visible: root._tempHot || opacity > 0.001
            opacity: root._tempHot ? 1.0 : 0.0
            scale: root._tempHot ? 1.0 : 0.7
            transformOrigin: Item.Center
            MotionBehavior on opacity { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutCubic } }
            MotionBehavior on scale   { NumberAnimation { duration: Motion.normal; easing.type: Easing.OutQuart } }
            glyph: "󰔏"
            glyphAlignReference: "󰔏"
            glyphPixelSize: Settings.iconSize + 1
            glyphColor: CpuTemp.critical ? Theme.error : Theme.warning
            textColor: CpuTemp.critical ? Theme.error : Theme.warning
            text: Math.round(CpuTemp.temp) + "°"
        }
    }

    function _nextHot(value: real, wasHot: bool, enter: int): bool {
        return wasHot ? value >= (enter - root._hysteresis) : value >= enter
    }

    function _syncCpuHot(): void { root._cpuHot = root._nextHot(root._cpuValue, root._cpuHot, ShellSettings.cpuHotPercent) }
    function _syncMemHot(): void { root._memHot = root._nextHot(root._memValue, root._memHot, ShellSettings.memHotPercent) }
}
