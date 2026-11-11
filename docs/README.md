# Documents

An index of the documents under `docs/` and the decision records under
`adrs/`. [README.md](../README.md) says what the fork is and how it takes
upstream changes, and [AGENTS.md](../AGENTS.md) holds the working rules for
agents.

## Living documents

- [forking.md](forking.md): forking Silere, and how to change the shell.
- [upstream-divergences.md](upstream-divergences.md): the standing
  differences between this fork and upstream, each with the action an
  integration takes when they collide.
- [debugging.md](debugging.md): finding the shell's logs in the journal,
  and debugging the lock, notifications, network, caffeine and night light.
- [lock-screen-plan.md](lock-screen-plan.md): the lock screen's design and
  plan, shipped and kept for its rationale.
- [lock-screen-qa.md](lock-screen-qa.md): the hand-run checklist for the lock
  screen.

## Decision records

- [ADR 0001](../adrs/0001-animate-wallpaper-driven-palette-changes-centrally-with-a-leaf-fade-gate.md):
  animate wallpaper-driven palette changes centrally with a leaf-fade gate.
- [ADR 0002](../adrs/0002-record-standing-merge-resolutions-in-a-divergence-ledger-with-fork-code-superseding-upstream.md):
  record standing merge resolutions in a divergence ledger with fork code
  superseding upstream. Superseded by ADR 0003.
- [ADR 0003](../adrs/0003-integrate-upstream-changes-selectively.md):
  integrate upstream changes selectively.
- [ADR 0004](../adrs/0004-adapt-glass-thickness-to-a-sampled-wallpaper-region.md):
  adapt glass thickness to a sampled wallpaper region.
- [ADR 0005](../adrs/0005-tune-the-menu-glass-and-secondary-text-to-the-menus-own-corner.md):
  tune the menu glass and secondary text to the menu's own corner.

## Integration records

### Historical integrations

The [v0.9.0 resolution record](upstream-merge-v0.9.0.md),
[September 4 selective integration record](upstream-picks-2026-09-04.md),
[September 9 selective integration record](upstream-picks-2026-09-09.md),
and [v1.0.0 resolution record](upstream-merge-v1.0.0.md) describe work
under the previous release-tag policy. Their historical approvals do not
authorize new imports. Upstream's `v1.0.0` and the older fork tag with that
name identify different commits; the v1.0.0 record gives the exact source.

### Selective integrations

The [September 16 staged integration plan](upstream-picks-2026-09-16.md)
records the post-v1.0.0 picks, confirmed decisions, and acceptance checks.
Stages 1–8 supply the reviewed integration baseline. Stage 9 consolidates
common popup state while retaining the confirmed placement policies.
The [follow-up record](upstream-picks-2026-09-16-followup.md) covers
startup smoke-test isolation and the bounded Bluetooth pairing guard.
The [September 18 record](upstream-picks-2026-09-18.md) covers calendar
write protection, fullscreen detection, notification stack motion, and panel
construction checks.
The [October 1 record](upstream-picks-2026-10-01.md) covers the v1.2.0
review: notification, tray, Hyprland, settings and IPC fixes, the calendar
week settings, log out, and motion timing.
The [October 4 record](upstream-picks-2026-10-04.md) covers test-shell
isolation and the slider, brightness, scroll, system-reading and notification
fixes, and records the declined protocol blur.
The [October 10 record](upstream-picks-2026-10-10.md) covers the 1.3.0
and 1.4.0 review: the lock screen launch, Hyprland workspace snapshots,
notification, battery, audio, Wi-Fi and media fixes, slider grabs and the
calendar's locale labels.
The [October 16 record](upstream-picks-2026-10-16.md) covers the 1.4.1
and 1.4.2 review: clock-step deadlines, helper timeouts, hidden controls,
night light, brightness, Wi-Fi, Niri and notification fixes.
