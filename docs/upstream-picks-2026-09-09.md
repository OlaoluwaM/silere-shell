# Selective upstream integration: 2026-09-09

## Scope and provenance

The maintainer selected the animation consolidation from
[`13acda023b7fc02bfbc4399afcb3123bb991656a`](https://github.com/s3rven/silere-shell/commit/13acda023b7fc02bfbc4399afcb3123bb991656a)
in `s3rven/silere-shell`. The fork fixed point is
`c50ed8f82685ea52ab4ee37566a4f3903d9990fd`.

This is a scoped port into the fork's existing implementations. It does not
import upstream ancestry or claim to include all changes through that SHA.
The separate concurrent-smoke-test commit
`5b68d7b04e53ec9246e2c2f62cc8716189d46a22` was reviewed and not selected.

## Adaptation

The shared `BumpAnimation` owns the rise and return to rest, with timing from
`Motion.bumpRise` and `Motion.bumpSettle`. Applicable workspace and bar OSD
callers retain their amplitudes and use the shared cleanup path.

The special-entry pulse changes from 90/185 ms with OutCubic/OutQuart easing
to 70/140 ms with OutQuad/OutCubic easing (275 ms to 210 ms total).
The two marker color transitions change from 150 ms to `Motion.color`'s
160 ms. Both changes follow the selected upstream commit.

The fork preserves continuous retriggering. Upstream's stop handler resets the
target to rest during `restart()`, causing a jump when marker gestures arrive
midflight. An isolated comparison probe confirmed the discontinuity, and the
maintainer selected the old behavior: restarting rises from the current value.
Explicit `retire()` handles gate cleanup and restores rest even when already
stopped; bare `stop()` preserves the current value. Natural completion still
lands at rest. Visual acceptance has not been performed.
Structural lint identifies bump IDs in each production QML file and rejects
direct `.stop()` calls on them, so cleanup must use `retire()`.

The fork also retires a bump when reduced motion is enabled during playback.
The upstream helper only changes its duration bindings; the regression probe
showed that Qt keeps the in-flight timing, leaving the bar OSD animating until
completion. Helper-level retirement makes that behavior consistent across
callers.

The fork's workspace entry animation remains separate. Upstream's slot-swap
fade is absent here, so the port does not add it. The floating OSD retains
its height and slide transitions; upstream's floating OSD bump is not added.
The fork-deleted changelog and palette helper remain absent.

The related hyprsunset scheduler fix belongs to `nixos-config`'s package
configuration and is independent of this import.

## Validation

- `bash scripts/ci-lint.sh`: passed.
- `nix develop . --command bash scripts/check.sh`: passed with zero failures
  and five environment warnings (optional cava/powerprofilesctl, compositor
  autostart detection, and two matugen setup checks). The deployed shell uses
  a systemd user service, which the autostart check does not detect.
- The focused real-helper probe passed 15 checks, including continuous
  retriggering during rise and settle, explicit retirement, completion,
  repeated retirement, and enabling reduced motion midflight. Both continuity
  assertions failed before the reset-on-stop handler was removed.
- Headless QML checks loaded 198 files; the existing logic suite passed 386
  checks plus companion probes. Surface checks and mutation checks passed
  across 174 settings states and 55 surfaces.
- The settings contract remains identical across the checked-in defaults,
  `ShellSettings`, and the Nix render: 52 matching keys. Defaults are unchanged.
- All six QML review missions completed for the initial port. The subsequent
  retrigger correction received IC self-review and a focused lead review of
  the helper, tests, and all five production cleanup paths. Lead review found
  no blocking correctness issues. Python lint's three new generic style/type diagnostics
  follow the existing animation-helper and test-callback conventions;
  `qmllint` reported only four unchanged dynamic-object warnings.

These are isolated runtime and static checks, not a visible desktop acceptance
test. No production shell restart, deployment, or live Niri session was used.
