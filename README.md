<p align="center">
  <img src="assets/banner.svg" alt="silere shell - quiet by default." width="720"/>
</p>

<p align="center"><em>silere</em>, from Latin: to be silent.</p>

<p align="center">
  <a href="https://github.com/s3rven/silere-shell/releases"><img src="https://img.shields.io/github/v/release/s3rven/silere-shell?style=flat-square&labelColor=17181d&color=747a98" alt="latest release"/></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-747a98?style=flat-square&labelColor=17181d" alt="license: MIT"/></a>
  <a href="https://quickshell.org/"><img src="https://img.shields.io/badge/built%20on-Quickshell-747a98?style=flat-square&labelColor=17181d" alt="built on Quickshell"/></a>
  <img src="https://img.shields.io/badge/runs%20on-Hyprland%20%C2%B7%20niri-747a98?style=flat-square&labelColor=17181d" alt="runs on Hyprland and niri"/>
</p>

A Quickshell desktop shell for Hyprland and niri. One process draws the bar, menu,
notifications, OSD, calendar and tray, so there is no separate bar, notification daemon
or OSD helper to install and keep in step.

Everything is set from a settings panel inside the shell — there is no config file to
write, and changes apply as you make them.

Background work only runs when it has something to do: an idle session sits near zero
CPU, and every animation stops on its own when you walk away.

<p align="center">
  <img src="assets/shot-desktop.webp" alt="The Silere bar with the menu panel open" width="900"/>
</p>

## Install

You need `git`, Hyprland or niri, and Quickshell 0.3.1 or newer.

```bash
git clone https://github.com/s3rven/silere-shell
cd silere-shell
bash scripts/install.sh
```

The installer names any missing QML module, backs up files before editing them, asks
before touching compositor autostart, and prints the install path when it's done. Restart
your compositor, or start it right away with `qs -p /that/path/shell.qml`.

**Click the active workspace diamond** to open the menu and settings. That is the way in,
so bind a key to it early:

```bash
qs ipc -p ~/.config/silere-shell/shell.qml call menu toggle
```

Fonts, optional tools, unattended installs, Matugen wiring and removal:
[`docs/install.md`](docs/install.md).

## What you get

- **Bar** — workspaces, media, network, volume, brightness, battery, clock, tray, updates.
  Drag them between left, centre and right, per monitor.
- **Menu** — live controls, every setting, and notification history in one panel.
- **Notifications** — actions, images, history, quiet hours, source-window jumping.
- **Theming** — Matugen from your wallpaper or a hand-picked accent, over three dark base
  tones.
- **Calendar** from the clock, **OSD** for volume and brightness, and **quick actions** for
  night light, power profiles and airplane mode.

<p align="center">
  <img src="assets/shot-surfaces.webp" alt="The menu panel, the settings rail, and the calendar" width="900"/>
</p>

## Controls

| area | actions |
|---|---|
| workspaces | click switches. On the active diamond, click opens the menu and right-click opens quick actions. Middle-click sends the focused window to that workspace. Scroll switches too, once you turn it on under Settings › Workspaces. |
| clock | click opens the calendar. Middle-click cycles seconds and date. |
| calendar | scroll changes the month. Click the header to jump back to today. |
| media | click plays or pauses. Scroll changes track. Middle-click jumps to the player. |
| volume | scroll changes volume. Click mutes. |
| brightness | scroll changes brightness. |
| tray | click jumps to the app. Right-click opens its menu. Middle-click runs the app's secondary action, and scrolling is passed through to the app. |
| notifications | click runs the default action. Right-click dismisses. Middle-click jumps to the app that sent it. |
| menu | Escape steps back, then closes. Click anywhere outside to close. |
| history | click an entry to read it in full. |

Silere is pointer-driven: Escape and the Wi-Fi password field are the only keyboard paths.

## Configuration

Everything is configurable from Settings inside the shell. Changes save on their own and
apply without a restart.

Overrides live in `$XDG_CONFIG_HOME/silere-shell/settings.json`, independent of where the
checkout is. Only values that differ from their defaults are written, so the file stays
short. Values are type-checked and numeric ranges are clamped on load, and a file Silere
cannot read is left alone instead of overwritten.

To restore defaults, use **Settings › System › Maintenance**. Editing the file by hand
works too: delete a key to reset one option, or replace the whole file with
`{ "__version": 1 }` to reset everything.

## Scripting

Every surface is scriptable over Quickshell IPC, and Silere can run an executable of your
own on events like `battery-critical` or `workspace-changed`.

```bash
SILERE_DIR="$HOME/.config/silere-shell"
qs ipc -p "$SILERE_DIR/shell.qml" call menu toggle
qs ipc -p "$SILERE_DIR/shell.qml" call menu settings updates
qs ipc -p "$SILERE_DIR/shell.qml" call calendar toggle
qs ipc -p "$SILERE_DIR/shell.qml" call quickActions toggle
qs ipc -p "$SILERE_DIR/shell.qml" call settings set osdTimeout 3000
```

The full IPC surface, the settings section names, and hooks:
[`docs/scripting.md`](docs/scripting.md).

## Updates

Shell and package updates never install on their own. Shell checks follow stable version
tags, accept only releases signed by Silere's bundled public verification key, and show the
pending commits before a two-step installation confirmation. Signature verification proves
where a release came from; it is not a claim that the code is harmless. Package checks only
update the badge.

## Performance

Idle use on a reference session measured under 1% of one CPU core, settling near 120 MB PSS
after an hour — much of that the Qt and GPU driver floor rather than Silere. Measure your
own checkout with `bash scripts/bench.sh 30`. Full numbers and the animation-driver note:
[`docs/performance.md`](docs/performance.md).

## Troubleshooting

```bash
bash scripts/check.sh
```

That runs the dependency, autostart and configuration checks. For startup errors, run
`qs -p shell.qml` directly. Common problems: [`docs/troubleshooting.md`](docs/troubleshooting.md).

## Contributing

Ideas, fixes, and new features are all welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) to
get started. Forking or making it your own? [`docs/forking.md`](docs/forking.md) maps the
tree, lists what a change actually touches, and names the few things a rename has to get
right.

## On AI assistance

I use AI tools to build Silere, and I think it makes the project better. It's just me
working on this. With the help, bugs get fixed the same day I find them instead of sitting
around for weeks.

I still decide what goes in, and I read every change myself. Silere is the only desktop I
use, so anything broken breaks my own machine first.

AI-assisted pull requests are welcome too. See [CONTRIBUTING.md](CONTRIBUTING.md).

## License

MIT (c) s3rven
