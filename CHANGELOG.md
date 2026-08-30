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

- Hovering a bar widget shows its click, alternate-button and wheel controls, and the full
  text of a window title too long to fit. Widgets › Indicators › Bar tooltips turns it off.
- Notification popups accept inline replies from applications that offer them.
- Bar › Spacing › Center between widgets balances the middle zone against both sides.
- A Bluetooth widget shows the connected device and its battery. Widgets › Show & order turns it on.
- Theme › Balance accent gives a wallpaper accent the strength of a hand-picked one.
- Widgets › Workspaces turns off the marker pulse that plays when the menu opens.

### Changed

#### Bar

- The window title is a bar widget: put it in any zone, where it takes that zone's alignment,
  padding and dividers, and reorder it like the rest.
- The window title drops a track name the media widget in its zone already shows, and app
  branding its own app name repeats.
- The window title stops widening past a readable span on a wide screen.
- Titles from background windows update on a slower pass than the focused one.
- Dragging a bar widget outlines the slot it will drop into.
- The bar underline takes the accent colour.
- Bar effects stop animating after four minutes without input.
- The clock eases in and out as it is switched on and off.
- Hovering the active workspace before clicking it opens the menu without a first-time pause.

#### Menu and settings

- System › Maintenance opens with a health summary and keeps settings recovery at the end.
- Opening a settings dropdown folds the one already open.
- Reset in Widgets › Show & order uses the same confirm button as the rest of the menu.
- Settings says what Reduce motion pauses, the audio visualiser included.
- The power mode control follows a profile set from outside Silere.
- Theme says when the loaded palette carries no accent colour of its own.
- Widgets › Indicators › App name says where the name appears.
- Wi-Fi rows hold still while the signal drifts inside the tier their icon shows.
- Long Bluetooth, package and release-note lists scroll without hitching.

#### Notifications

- Runs of notifications from one app share a single header, and each card sizes to its own text.
- Hovering a notification in the menu swaps its timestamp for the remove button; removing one slides it out.
- A notification with more text than it shows carries a chevron.
- Notifications older than today show a clock time.
- A notification that updates in place, such as a progress bar, leaves the rest of the popup stack alone.
- Clear all in a notification popup uses the same button as the notification list.
- A long notification history scrolls smoothly.

#### Media

- A track playing from a private browser tab shows the browser instead of the hidden details.

#### Scripting and hooks

- Hooks run at most four at a time, and one still going after 30 seconds is stopped along with anything it started.
- An event that repeats while its turn is pending keeps only its newest arguments.
- `menu settings <page>` and `settings <key>` over IPC match a name without case.

#### Install and updates

- Silere requires Quickshell 0.3.1 or newer, and `bash scripts/check.sh` fails on anything older.
- `bash scripts/check.sh` reports whether Silere is set to start on login, from the compositor config or a systemd user unit.
- Removing the AUR package names the autostart line and Matugen block it cannot clean up itself.
- The README covers a first run; optional tools, scripting, hooks, performance and troubleshooting each moved to a page under `docs/`.

### Fixed

#### Bar fixes

- The window title updates in place while a window keeps its identity, and crossfades when the window changes.
- The window title appears when a title arrives for a window that reported none.
- The window title shows on the focused monitor when the compositor names no output for a window.
- A long window title no longer stretches a narrowed bar, and the widgets beside it ease rather than twitch as it changes length.
- Widgets › Indicators › App name off keeps the app name hidden for a window that reports no title.
- A divider no longer sits beside a window title that has faded out.
- The underline sweep centres on a widget placed in the centre zone.
- Centre-zone widgets keep clear of a crowded side of the bar.
- Bar › Layout keeps the roundness slider reachable while the bar is docked, and stops it where the bar stops rounding.
- Turning off Widgets › Workspaces › Urgent window pulse also stops the off-page urgent dot pulsing.
- Workspace marker and page effects settle when their bar sleeps, the session goes idle, or their setting is turned off.
- The workspace marker keeps its place when a compositor event arrives while the bar is rebuilding.
- Clock digits and the bar's readouts hold still behind the overview and through an idle screen.
- The 12h clock counts one to twelve, with midnight and noon both reading twelve.
- On niri, a workspace counts as occupied whenever it holds windows.
- Bar readings reach a screen reader even where the bar holds values back until hover, and volume says when it is muted.
- The window title reaches a screen reader.

#### Menu and settings fixes

- A double-click no longer confirms a reset or an update install in one gesture.
- Restore defaults leaves settings unchanged when its safety backup cannot be written.
- Font and display-routing settings ease into the panel when device discovery makes them available.
- Feedback › Notifications says when a quiet-hours range starts and ends on the same hour.
- Widgets › Show & order lines its drag handles up in one column.
- System › Maintenance points at a package to install only when one is missing.
- Settings sliders line up with their row label.
- Accent and Base swatches say which setting they belong to.
- A row scrolled back into a long Bluetooth or update list no longer fades in from the row it replaced.

#### Notification fixes

- A notification stays expanded while the pointer rests on it.
- A notification body with no spaces, such as a long path or URL, wraps and expands.
- Notification icons fall back to the app's own icon, including on the first notification of a session.
- A notification popup older than an hour stamps its time in the chosen clock format.
- Notification history restamps its times when the clock format changes.
- Scrolling notification history no longer carries one entry's urgency colour onto another.

#### System fixes

- A background command stopped at its time limit takes its own child processes with it.
- Every background command Silere runs has a time limit, and the optional tool scan reports when it gives up.
- Configuration, palette, update and visualiser paths keep significant whitespace in an
  absolute XDG directory.
- CPU temperature warnings clear if their sensor disappears or starts returning invalid data.
- The disk tile reads filesystems with long or whitespace-containing device names.
- Malformed timezone coordinates no longer corrupt the night light's solar estimate.
- A removed `nmcli` no longer leaves a stale VPN indicator behind.
- The night light temperature set by hand is kept while Follow sun position is on, and returns when it is turned off.
- The power mode control offers only the profiles the machine supports.
- The battery percentage recovers on hardware that reports charge ambiguously, instead of staying wrong for the session.
- Bluetooth limits a pairing window to one minute even if the shell stops during an attempt.

#### Install and update fixes

- A fresh install finishes on the latest signed release.
- `bash scripts/check.sh` stops reporting failure on an install that is not a Git checkout.
- `bash scripts/check.sh` finds user services through the same XDG data fallback as the updater.
- Setting a bar widget order over IPC keeps each widget in one zone.
- A stalled update check or install cannot leave the update lock held after it exits.
- Installing an update refuses a newer release than the one shown on the confirmation screen.

### Security

- Notification icons, images and album art no longer follow a filesystem path chosen by the
  sender. Inline images, local art files, web covers and installed application icons still work.

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
