import QtQuick

MotionBehavior {
    // stand down while the palette sources interpolate (ADR 0001): each source
    // frame would otherwise retarget this animation and double-ease the leaf
    gate: !MatugenTheme.transitioning
    ColorAnimation { duration: Motion.color }
}
