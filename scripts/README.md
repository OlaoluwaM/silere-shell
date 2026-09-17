# Scripts

Validation, development probes, benchmarks, and manual-install tools. Run the
commands below from the repository root. Fork and deployment rules live in
[AGENTS.md](../AGENTS.md) and the [root README](../README.md).

## Usual checks

```sh
bash scripts/ci-lint.sh
nix develop . --command bash scripts/check.sh
```

`ci-lint.sh` checks source structure, shell syntax, module registrations,
settings coverage, and repository conventions. It also runs ShellCheck when
available and the portability regressions.

`check.sh` includes that lint pass, checks dependencies, compiles QML, runs
behavioral probes, starts disposable shell instances, and checks settings and
layout. The Nix development environment supplies the matching Quickshell and
Qt tools and makes missing QML prerequisites fail instead of skip. Run the full
check from a graphical session for its Wayland coverage. Temporary instances
can connect to desktop services; this is not an entirely headless suite.
The startup smoke case copies Silere's configuration into a private directory,
including materializing symlink targets. Copy failures fail that check. This
protects shell-owned settings and history from probe writes; configured external
commands and desktop services retain their usual effects.

Read the individual results as well as the exit status. Optional dependencies
and local configuration can produce warnings. A skipped check does not establish
that the corresponding behavior works.

## Focused checks

Run a single runner with `nix develop . --command bash scripts/<name>.sh`.
The full check already includes the runners below, directly or through
`test-logic.sh` or `ci-lint.sh`.

| Runner | Coverage |
| --- | --- |
| [test-qml-headless.sh](test-qml-headless.sh) | QML bytecode compilation and import checks |
| [test-logic.sh](test-logic.sh) | Service and widget logic, followed by the behavioral runners below |
| [test-bump-animation.sh](test-bump-animation.sh) | Bump animation lifecycle and restart continuity |
| [test-notification-reload.sh](test-notification-reload.sh) | Notification reload behavior |
| [test-niri-focus.sh](test-niri-focus.sh) | Niri focus handling using a mock compositor |
| [test-history-grouping.sh](test-history-grouping.sh) | Notification history grouping |
| [test-popup-lifecycle.sh](test-popup-lifecycle.sh) | Popup lifecycle under normal and reduced motion |
| [test-config-recovery.sh](test-config-recovery.sh) | Recovery from malformed configuration |
| [test-settings-migration.sh](test-settings-migration.sh) | Settings migration and write protection |
| [test-bar-hint-idle.sh](test-bar-hint-idle.sh) | Hint surface idle transitions; requires Wayland |
| [test-overlay-coordinator.sh](test-overlay-coordinator.sh) | Popup registration, exclusivity, tray relationships, cold IPC, anchor policies, disappearance, reload, and idle/overview blocking |
| [test-bluetooth-details.sh](test-bluetooth-details.sh) | Details selection and disconnect cleanup using synthetic devices |
| [test-upstream-services.sh](test-upstream-services.sh) | Selected upstream service regressions with controlled inputs |
| [test-notification-disk.sh](test-notification-disk.sh) | Private-bus process restart, settings order, deletes before disk restoration, immediate reload after clear, read-only future-format restoration, file protection, and failed-write recovery |
| [test-upstream-connectivity.sh](test-upstream-connectivity.sh) | Wi-Fi security classification and Bluetooth state helpers |
| [test-upstream-connectivity-paths.sh](test-upstream-connectivity-paths.sh) | Actual service and row paths with synthetic backend inputs; pairing guard, guarded forget, and identity during synchronous row replacement |
| [test-upstream-tray.sh](test-upstream-tray.sh) | Descendant hover-chain logic and confirmation-control transitions |
| [test-fullscreen-state.sh](test-fullscreen-state.sh) | Fullscreen demand and state through a mock compositor |
| [test-surfaces.sh](test-surfaces.sh) | Loading surfaces across settings and accessibility variants |
| [test-mutate.sh](test-mutate.sh) | Changing settings on already-created surfaces |
| [test-layout-fit.sh](test-layout-fit.sh) | Label fit across the supported text sizes |
| [test-portability.sh](test-portability.sh) | Shell helper and installation portability regressions |
| [test-smoke-config.sh](test-smoke-config.sh) | Private startup configuration copying, symlink isolation, failure handling, launcher wiring, and cleanup; included by the portability suite |

The Bluetooth regression does not pair or disconnect real hardware. Its fixture
replaces the Bluetooth service while exercising the real menu list. Hardware
discovery and connection behavior require a separate live test. The Niri mock
likewise does not establish behavior in a live Niri session.

## Benchmarks

Start a disposable checkout instance in a graphical session:

```sh
nix develop . --command qs -p shell.qml
```

Then, from another terminal at the repository root:

```sh
nix develop . --command bash scripts/bench.sh 10 --json --label baseline
```

[bench.sh](bench.sh) locates the instance whose config path is this checkout's
`shell.qml` and samples Linux process metrics for it and its helper processes.
Use `--help` for options. `--warm` opens and closes that instance's menu before
sampling; without it, the report describes the state it found. It does not
measure frame timing or prove interactive responsiveness.

## How the probes fit together

- `test-*.sh` files prepare temporary project/configuration directories, launch
  probes, inspect their logs, and stop the processes they started.
- `probe-*.qml` files contain the runtime assertions. Use their shell runners:
  the entry file's directory becomes Quickshell's project root, so launching
  a probe directly can leave its imports unresolved.
- [probe-lib.sh](probe-lib.sh) supplies shared project setup, process cleanup,
  sentinel waiting, and QML runtime-error detection. A success sentinel alone
  is insufficient because QML can report binding errors without exiting.
- `fixtures/` supplies synthetic inputs and replacement services for isolated
  tests. Production services remain intact.
- `lib/` contains shared shell UI, XDG-path, and QML-module helpers.
- [check-connections.py](check-connections.py) and
  [check-text-scale.py](check-text-scale.py), plus
  [check-internal-types.py](check-internal-types.py), are standalone source diagnostics.
  Run them with `python3 scripts/<name>.py` from the repository root; they are
  not substitutes for the full checks.

For a new probe, follow a nearby runner, reuse `probe-lib.sh`, check both its
sentinel and runtime errors, and register new QML files in their folder's
`qmldir`. Add the runner to the appropriate suite so the full check reaches it.
Keep routine generated logs and temporary instrumentation out of the committed
source. Deliberately retained investigation evidence belongs in
[.debug/](../.debug/README.md), with a report explaining its scope and results.

## Manual installation and repair

[install.sh](install.sh) and [uninstall.sh](uninstall.sh) manage a non-Nix
installation. They edit user configuration and installation files. This fork's
Nix deployment is managed by nixos-config; do not use those scripts there.

[repair.sh](repair.sh) previews checkout changes by default. `--apply` saves
local changes in a repair stash and restores shipped files; `--undo` restores
the latest repair stash. These are maintenance actions, not validation steps.
