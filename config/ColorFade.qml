import QtQuick
import "../services"

MotionBehavior {
    // while the palette itself is easing, the source colour behind this one is already
    // moving: fading again double-eases it and restarts on every frame of the shift
    enabled: gate && !ShellSettings.reduceMotion && !Idle.isIdle && !Theme.paletteShifting

    ColorAnimation { duration: Motion.color }
}
