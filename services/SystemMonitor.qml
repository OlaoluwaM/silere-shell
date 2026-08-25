pragma Singleton

import QtQuick
import Quickshell

// Clicking a vitals tile (the menu's SYSTEM strip, the bar's hot chips) opens
// the system monitor on that tile's own view. The command is a user-declared
// template (ShellSettings.systemMonitorCommand) through the same
// TemplateLauncher the wifi editor and bluetooth manager escape hatches use;
// {widget} is substituted with the clicked tile's view name. The vocabulary is
// bottom's --default_widget_type set, validated below so nothing outside it
// ever reaches the exec; a template without the placeholder (a monitor with no
// per-view CLI) still launches, it just lands on its own default view.
Singleton {
    id: root

    TemplateLauncher {
        id: _launcher
        template: ShellSettings.systemMonitorCommand
    }

    readonly property bool available: _launcher.available
    readonly property string lastError: _launcher.lastError

    function launch(widget: string): void {
        _launcher.launch("widget", widget, /^(cpu|mem|temp|disk|battery)$/)
    }
}
