# Changelog

Notable changes to Silere Shell, following
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/). Versions follow
[Semantic Versioning](https://semver.org/) loosely while in `0.x`: minor versions
change features, patch versions fix them. The updater follows signed stable tags;
the settings file carries its own `__version` and migrates separately.

Only work since the latest release is listed here. Completed notes move to
[`docs/releases`](docs/releases/) and stay linked below.

## [Unreleased]

### Changed

- Hooks run at most four at a time, and one still going after 30 seconds is stopped. An event that repeats while its turn is pending keeps only its newest arguments.
- `bash scripts/check.sh` fails when the installed Quickshell is older than the version Silere requires.
- The README keeps to what a first run needs; optional tools, scripting, hooks, performance and troubleshooting each moved to a page under `docs/`.
- A track playing from a private browser tab shows the browser instead of the hidden details.
- The visualiser and the scrolling title settle after four minutes without input rather than ten.
- The low-battery and hot-CPU glows settle on the same four-minute mark.
- `menu settings <page>` and `settings <key>` over IPC match a name without case.

### Fixed

- Notification icons fall back to the app's own icon, including on the first notification of a session.
- Bar › Layout keeps the roundness slider reachable while the bar is docked.
- Feedback › Notifications says when a quiet-hours range starts and ends on the same hour.
- Widgets › Show & order lines its drag handles up in one column.
- System › Maintenance points at a package to install only when one is missing.
- Setting a bar widget order over IPC keeps each widget in one zone.

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
