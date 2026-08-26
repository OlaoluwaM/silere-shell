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

- Widgets › Workspaces turns off the marker pulse that plays when the menu opens.

### Changed

#### Bar

- The bar underline takes the accent colour instead of a flat grey.
- The window title is a bar widget: place it in any zone and reorder it like the rest.
- Dragging a bar widget outlines the slot it will drop into.
- Hovering the active workspace prepares the menu between frames, then releases it if no click follows.
- The low-battery and hot-CPU glows settle on the same four-minute mark.

#### Menu and settings

- Maintenance leads with one clear health summary, separates real attention items from optional add-ons, and keeps settings recovery last.
- Opening a settings dropdown folds the one already open.
- Reset in Widgets › Show & order uses the same confirm button as the rest of the menu.
- Settings explains when Reduce motion pauses animated effects such as the audio visualiser.

#### Notifications

- Clear all in a notification popup uses the same button as the notification list.
- Notification history reuses off-screen rows and shares one time snapshot per refresh while scrolling.

#### Media

- A track playing from a private browser tab shows the browser instead of the hidden details.
- The visualiser and the scrolling title settle after four minutes without input rather than ten.

#### Scripting and hooks

- Hooks run at most four at a time, and one still going after 30 seconds is stopped along with anything it started.
- An event that repeats while its turn is pending keeps only its newest arguments.
- `menu settings <page>` and `settings <key>` over IPC match a name without case.

#### Install and updates

- Silere requires Quickshell 0.3.1 or newer.
- `bash scripts/check.sh` fails when the installed Quickshell is older than the version Silere requires.
- `bash scripts/check.sh` reports whether Silere is set to start on login, from the compositor config or a systemd user unit.
- Removing the AUR package names the autostart line and Matugen block it cannot clean up itself.
- The README keeps to what a first run needs; optional tools, scripting, hooks, performance and troubleshooting each moved to a page under `docs/`.

### Fixed

#### Bar fixes

- Bar widgets ease instead of twitching when the window title changes length.
- Bar › Layout keeps the roundness slider reachable while the bar is docked.
- Bar › Layout roundness ends where the bar stops rounding.
- Turning off Widgets › Workspaces › Urgent window pulse also stops the off-page urgent dot pulsing.
- Workspace marker and page effects settle when their bar sleeps, the session goes idle, or their setting is turned off.
- The workspace marker keeps its place when a compositor event arrives while the bar is rebuilding.
- Bar readings reach a screen reader even when the bar holds values back until hover, and volume says when it is muted.
- The 12h clock counts one to twelve, with midnight and noon both reading twelve.

#### Menu and settings fixes

- A double-click no longer confirms a reset or an update install in one gesture.
- Restore defaults leaves settings unchanged when its safety backup cannot be written.
- Font and display-routing settings ease into the panel when device discovery makes them available.
- Feedback › Notifications says when a quiet-hours range starts and ends on the same hour.
- Widgets › Show & order lines its drag handles up in one column.
- System › Maintenance points at a package to install only when one is missing.
- Settings sliders line up with their row label.
- Accent and Base swatches say which setting they belong to.

#### Notification fixes

- A notification stays expanded while the pointer rests on it.
- A notification body with no spaces, such as a long path or URL, wraps and expands.
- Notification icons fall back to the app's own icon, including on the first notification of a session.
- A notification popup older than an hour stamps its time in the chosen clock format.

#### System fixes

- The night light temperature set by hand is kept while Follow sun position is on, and returns when it is turned off.
- The power mode control offers only the profiles the machine supports.
- The battery percentage recovers on hardware that reports charge ambiguously, instead of staying wrong for the session.
- Bluetooth limits a pairing window to one minute even if the shell stops during an attempt.

#### Install and update fixes

- A fresh install finishes on the latest signed release.
- `bash scripts/check.sh` stops reporting failure on an install that is not a Git checkout.
- Setting a bar widget order over IPC keeps each widget in one zone.
- A stalled update check or install cannot leave the update lock held after it exits.
- Installing an update refuses a newer release than the one shown on the confirmation screen.

### Removed

- The "Center between widgets" setting. The window title takes its place from the zone it sits in.

### Security

- Notification images and icons no longer open filesystem paths supplied by a sender. Inline images and installed application icons still work.

## Releases

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
