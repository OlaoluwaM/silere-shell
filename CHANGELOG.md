# Changelog

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked at the bottom of this file.

Format is [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), with entries
grouped by the part of the shell they touch once a section runs long. Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags; the
settings file carries its own `__version` and migrates separately.

## [Unreleased]

### Added

- The volume control in the menu expands to Output, Input and Apps: choose a microphone, set its level, and set the level of each app playing sound.
- A microphone widget appears while an app is listening and mutes the input on click. It stays out of the way of apps recording system output; Widgets › Show & order turns it off.
- The expanded volume control names the apps holding the microphone open, and carries a row that opens Sound settings.
- Right-clicking the volume or microphone widget opens Sound settings; middle-clicking the volume widget moves to the next output.
- Night light runs on `wlsunset` where `hyprsunset` cannot. System › Maintenance chooses between them.
- System › Maintenance chooses the lock program: hyprlock, swaylock, gtklock, or a command of your own.

### Changed

- A wallpaper palette change crosses the whole interface on one curve instead of each element easing on its own. The approach is adapted from Flawedexa's fork.
- The volume widget shows a headphone glyph while output is on a headset.
- The volume control's tabs move in the direction of the choice, and the tab row holds still while its contents change.
- Hovering the volume or microphone widget names the device in use alongside the controls that are not obvious.
- The lock program chosen automatically follows the compositor: hyprlock leads on Hyprland, swaylock elsewhere.
- The installer's optional-tool list names fontconfig, which the font picker and font checks need.

### Fixed

- The workspace button opens the menu where the compositor reports no workspaces of its own.
- Tray icons render for apps that ship their own icon directory.
- Night Light refreshes externally changed `hyprsunset` state when a control surface opens, without letting a stale probe undo a user toggle.
- One-shot UI motion now settles when the display blanks instead of animating behind the lock screen.
- Popups, media art, workspace effects, and notification exits land cleanly when their animation is interrupted.
- Attention pulses no longer age out while idle or reduced motion has paused them.

## Releases

- [0.9.0](docs/releases/0.9.0.md) — 2026-08-30
- [0.8.0](docs/releases/0.8.0.md) — 2026-08-22
- [0.7.0](docs/releases/0.7.0.md) — 2026-08-18
- [0.6.1](docs/releases/0.6.1.md) — 2026-08-16
- [0.6.0](docs/releases/0.6.0.md) — 2026-08-15
- [0.5.1](docs/releases/0.5.1.md) — 2026-08-13
- [0.5.0](docs/releases/0.5.0.md) — 2026-08-13
- [0.4.0](docs/releases/0.4.0.md) — 2026-08-12
- [0.3.0](docs/releases/0.3.0.md) — 2026-08-11
- [0.2.0](docs/releases/0.2.0.md) — 2026-08-10
- [0.1.0](docs/releases/0.1.0.md) — 2026-08-08
