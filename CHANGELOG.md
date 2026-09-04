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

- `silere doctor`, `status`, `update`, `repair`, `version`, and `uninstall` make the
  existing maintenance paths discoverable from one command; `install.sh --check` runs
  the same read-only doctor.
- Signed releases carry a compatibility manifest, and the updater rejects a release that
  needs a newer Quickshell or does not support the active compositor before changing the checkout.
- The Updates page shows categorized release notes first and keeps raw commits under
  Technical details.
- Package-managed installs identify their owner in Updates instead of hiding the Silere installation state.
- `scripts/install.sh --dry-run` lists the files an install would create or edit and the autostart line it would add, then exits without writing.
- `scripts/bench.sh --warm` samples after one menu cycle.
- `scripts/bench.sh --json` writes one machine-readable object, and `--label` tags a run.
- The bench report names the state it sampled, the interface font, the machine and the Quickshell version.
- The bench report gives per-second median and worst CPU, and marks a sample taken during input as noisy.
- The bench report names the widgets that were drawing, and says when another Quickshell instance shared memory with the sample.
- `docs/perf-history.md` records per-release numbers against named reference machines.
- The volume control in the menu expands to Output, Input and Apps: choose a microphone, set its level, and set the level of each app playing sound.
- A microphone widget appears while an app is listening and mutes the input on click. It stays out of the way of apps recording system output; Widgets › Show & order turns it off.
- The expanded volume control names the apps holding the microphone open, and carries a row that opens Sound settings.
- Right-clicking the volume or microphone widget opens Sound settings; middle-clicking the volume widget moves to the next output.
- Night light runs on `wlsunset` where `hyprsunset` cannot. System › Maintenance chooses between them.
- Feedback › Notifications › Let critical through decides whether urgent alerts ignore do not disturb.
- System › Maintenance chooses the lock program: hyprlock, swaylock, gtklock, or a command of your own.
- The Bluetooth row in the menu shows the icon of the device that is connected.
- Workspaces › Dynamic workspaces lists only the workspaces in use, growing and shrinking
  as they come and go. A trailing slot opens the next empty one, and middle-clicking it
  moves the focused window there.
- `silere update --apply` validates a signed release in an isolated copy of the checkout
  before it changes anything live.
- Updates names the installation as a managed release or a development checkout, and
  disables self-update controls on a development checkout instead of failing when pressed.
- Settings older than the current schema migrate through explicit, ordered steps instead
  of one-off compatibility checks.
- The installer records a receipt of what it created; uninstall reads it before falling
  back to searching for its own files.

### Changed

- `silere run` is the single launch path for source, compositor, and package installs. It
  applies the memory and GPU defaults at every start, and refuses a duplicate instance.
- A wallpaper palette change crosses the whole interface on one curve instead of each element easing on its own. The approach is adapted from Flawedexa's fork.
- The volume widget shows a headphone glyph while output is on a headset.
- The volume control's tabs move in the direction of the choice, and the tab row holds still while its contents change.
- Hovering the volume or microphone widget names the device in use alongside the controls that are not obvious.
- The lock program chosen automatically follows the compositor: hyprlock leads on Hyprland, swaylock elsewhere.
- The installer closes by naming the check script to run when a surface does not appear.
- The installer's optional-tool list names fontconfig, which the font picker and font checks need.
- Feedback › OSD names its choices in words.
- Sliders and switches drop their white fills: the handle takes the accent, the switch knob reads as a dark cap, and a filled track sits deeper into its card. High contrast keeps the brighter fills.
- The media card drops its seek row: position is a bar along the card's bottom edge, with the elapsed and total times beside the controls. Dragging the bar still scrubs.
- Media controls lose their boxes. The glyphs are the buttons, with play carrying the accent.
- The calendar header runs the width of the card, with today's date at one end and the week number at the other. The month name now sits over the days it names.
- Releasing a version records cold and warm performance rows before the tag.
- Settings opens with every category expanded. Interface › Keep groups open still returns to one group at a time.
- The category groups in the settings rail are set as headings over their pages rather than rows beside them.
- The active workspace marker starts as the dot, and holds still when the menu opens.
- Restore defaults no longer writes a settings backup first.

### Fixed

- Cover art that will not load falls through to the other covers a track offers, including a cover file beside a local track.
- An update interrupted mid-apply no longer leaves an ambiguous checkout. The next run
  keeps a release that finished validating, or restores the previous revision.
- The bar returns to full width after a widget is moved between zones, instead of staying compact.
- The workspace button opens the menu where the compositor reports no workspaces of its own.
- Tray icons render for apps that ship their own icon directory.
- The Bluetooth widget keeps its generic glyph while the volume widget is already showing the connected device.
- Settings and calendar marks that could not be written are saved once their folder is reachable again.
- The installer recognises a JetBrainsMono Nerd Font that is already there instead of offering to download it again.
- A downloaded font that fontconfig does not list is reported rather than counted as installed.
- A failed settings-folder creation or permission check is no longer mistaken for a successful one.
- Settings category names keep their full width in the rail at the top of the interface scale range.
- The package list drops what it was showing and checks again when the package manager or AUR helper behind it changes.
- Package checks preserve their last result when an AUR helper fails, reject canceled results after a quick off/on toggle, and defer automatic retries while the session is idle.
- The Silere updater surfaces unattended timer failures in Settings, says how long ago one happened, and reloads its cache and checkout state after timeouts.
- A successful Silere install queues its own service restart without blocking inside the process tree being restarted.
- The temperature readout finds its sensor after being switched off and straight back on.
- A Bluetooth speaker shows a speaker rather than headphones, and more device types carry their own icon.
- The Bluetooth widget stays out of the bar on a machine with no Bluetooth adapter.
- Battery percentages stay bounded while their backend scale is detected, and a direct jump to critical sends one alert instead of two.
- Timed-out Matugen repairs remain failures when their process later exits.
- Deleting an old notification-history row no longer erases state for a live notification that reused its id.
- Notification ids reused after a server restart no longer replace unrelated persisted history.
- Night Light refreshes externally changed `hyprsunset` state when a control surface opens, without letting a stale probe undo a user toggle.
- Option buttons in settings keep their padding at the largest interface scale.
- One-shot UI motion now settles when the display blanks instead of animating behind the lock screen.
- Popups, media art, workspace effects, and notification exits land cleanly when their animation is interrupted.
- Attention pulses no longer age out while idle or reduced motion has paused them.
- Notifications in the menu, and the button that removes one, reach a screen reader.

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
