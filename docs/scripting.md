# Scripting

Every surface is scriptable over Quickshell IPC, so compositor keybinds and scripts can
open them without simulating a click. Set `SILERE_DIR` to the path the installer printed.

```bash
SILERE_DIR="$HOME/.config/silere-shell"
qs ipc -p "$SILERE_DIR/shell.qml" call menu toggle
qs ipc -p "$SILERE_DIR/shell.qml" call menu tab 2
qs ipc -p "$SILERE_DIR/shell.qml" call menu settings updates
qs ipc -p "$SILERE_DIR/shell.qml" call calendar toggle
qs ipc -p "$SILERE_DIR/shell.qml" call quickActions toggle
qs ipc -p "$SILERE_DIR/shell.qml" call screenshot flash
qs ipc -p "$SILERE_DIR/shell.qml" call settings toggle reduceMotion
qs ipc -p "$SILERE_DIR/shell.qml" call settings set osdTimeout 3000
```

Menu tabs are `0` (Home), `1` (Settings), and `2` (Recent). `quickActions` holds Do Not
Disturb, night light, power mode and airplane mode. `screenshot flash` lets a screenshot
tool trigger the underline effect directly, without the optional filesystem watcher.

`menu`, `calendar` and `quickActions` each take `close` as well as `toggle`, for a keybind
that dismisses without opening anything. Run `qs ipc -p "$SILERE_DIR/shell.qml" show` for
the current list.

`settings` reads and writes any setting the Settings pages expose: `get`, `set`, `toggle`,
`list [filter]`, and `modified`. A write echoes the value that landed, a rejected one names
the values the key accepts, and `list` prints each key with its own range or vocabulary. The
filter matches a section name as well as a key, so `list clock` reaches `showSeconds`.

## Settings section names

For `menu settings <name>`:

`theme`, `interface`, `surface`, `underline`, `separators`, `widgets`, `workspaces`,
`clock`, `media`, `indicators`, `popups`, `osd`, `warnings`, `updates`, `maintenance`

Names match without case. An unknown one falls back to `theme`, so an out-of-date keybind
still opens Settings.

## Hooks

Silere runs a command of your own when something happens. Drop an executable file in
`~/.config/silere-shell/hooks/`, named for the event:

| hook | arguments |
| --- | --- |
| `battery-critical` | percentage |
| `notification` | app name, summary, `critical` or `normal` |
| `theme-changed` | accent colour |
| `update-available` | count |
| `workspace-changed` | workspace id |

```bash
mkdir -p ~/.config/silere-shell/hooks
cat > ~/.config/silere-shell/hooks/battery-critical <<'EOF'
#!/bin/sh
notify-send "Battery at $1%"
EOF
chmod +x ~/.config/silere-shell/hooks/battery-critical
```

Hooks are read at startup; `qs ipc -p "$SILERE_DIR/shell.qml" call hooks rescan` picks up a
new one without a restart, and `hooks list` shows which are active. An event with no
executable file costs nothing.

Hook runs are capped at 20 a second and 4 at a time, and one still running after 30 seconds
is terminated. Anything past the rate cap is dropped rather than queued. While all four
runners are busy, further events wait, and repeats of the same event collapse to the most
recent one. Hooks are children of the shell, so they stop when it does.
