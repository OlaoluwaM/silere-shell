# Selective upstream integration: the October 4 fixes

Status: implemented and gated; the live checks under
[Not yet verified live](#not-yet-verified-live) are pending. Base:
`1fa15a699eb70857a98ab3aedb30d0b5fe839e1b`.

## Review range

The review covers the 12 upstream commits after
`ada88891b980df92b8739aa3824f41c70d7b7bf5` through
`1b20ece42dae1dc7693b16fe139732d224e720e9` on `upstream/main`, all dated
October 4. Sources are from <https://github.com/s3rven/silere-shell>. The
upstream commits bundle unrelated work, so each fork commit takes only the
hunks for one fix.

## Selected

| Commit | Subject | Upstream source |
| --- | --- | --- |
| `92c4607` | test: isolate smoke and probe shells from the live desktop | 21ced09, 066b3c0, 466bec2 |
| `f9834a5` | fix(controls): keep slider bounds reachable off the step grid | 066b3c0 |
| `abe2d94` | fix(brightness): ignore a write result from a display no longer selected | afe4242 |
| `526dcd7` | fix(scroll): detect reversal after an exact notch and drop capped backlog | 066b3c0 |
| `3ccf6b6` | fix(sysinfo): clear cpu and memory readings a bad sample leaves stale | afe4242 |
| `e190514` | fix(notifications): leave a reused id alone when a stale object closes | 066b3c0 |
| `bbec7d5` | fix(notifications): refuse a history file whose history is not a list | 066b3c0 |

`1877a3c` records the declined protocol blur in the divergence ledger.

## Material adaptations

- Test isolation: smoke and probe shells get a private cache, a disabled QML
  disk cache and unmapped bars; the fork's smoke runner stays sequential. A
  private cache leaves fontconfig cold, and a probe's `fc-list` outlived the
  probe and raced its cleanup, so probes now run in their own process group
  and stop as one. Upstream's probe teardown has the same race, hidden by its
  lazy font scan.
- Brightness: switching display also clears the old display's error, as
  upstream does in the device-switch reset.
- Malformed history: upstream's per-read write-permission reset is not
  ported. The fork restores `notifications.json` once per engine, and every
  exit from that restore already sets the permission.
- Slider: upstream's `QuickSlider` chevron accessibility hunks, its
  `_requestExpand` guard and `GradientSlider`'s minimum and maximum
  accessibility values are separate changes and were not taken.

## Declined, deferred and skipped

- Declined by the maintainer:
  - The protocol blur chain and every region hunk later commits carry
    (ledger entry). The Hyprland layer rule already frosts every `silere-*`
    surface.
  - The forced-save guard (`afe4242`, `config/PersistedFile.qml`). It guards
    an external settings edit during teardown, which this desktop rarely
    sees, and opens a 1–5 ms window at teardown in which the writer's own
    save echo blocks the final save and drops a pending edit.
  - Lazy font scanning (`07d23db`, deferred since September 16) again. It
    saves one ~25 ms off-thread `fc-list` at startup and gives up startup
    validation of the configured font.
  - Menu preload expiry consolidation (`a4a5cc2`, `147b8c7`): the fork's
    workspace timer already expires the preload.
- Deferred: Bluetooth discovery ownership (`afe4242`), tray rendering and
  fallback (`af8cde3`), dropdown virtualization (`a4a5cc2`), the inline reply
  focus change (`738523a`), the popup window split (`066b3c0`), the
  outside-click close for popups (`a2cff64`), and the remote-art disk cache
  (`afe4242`). The split, if taken, keeps the layer rule. Battery status, CPU
  sensor rediscovery and the Bluetooth `wpctl` volume path remain candidates
  for a later review.
- Untriaged: the remaining hunks of `afe4242`, `066b3c0` and `af8cde3`
  outside the fixes above. The Hyprland-relevant ones sit in
  `services/CompositorHyprland.qml`: a restart when the event socket dies,
  one rebuild for the twin workspace events, and the string workspace
  address Hyprland 0.57 sends. The rest touch `NightLight`,
  `PwVolumeControl`, `Network`, `OsdBarState` and the workspace and bar
  widgets.
- Not ported: the rest of `466bec2`'s suite, including the parallel smoke
  runner and checks for absent features.

## Validation

Each commit passed `bash scripts/ci-lint.sh` and
`nix develop . --command bash scripts/check.sh` with zero failures and the
four known environmental warnings. Every port first added probe checks that
failed on the unfixed code; the brightness checks fail there because the
routing helper they call does not exist yet. An adversarial review of the
notification and persistence ports found no blocking defects; reverting each
fix with its tests kept fails them.

`scripts/test-notification-stack.sh` draws on the live compositor. Its
"initial slot did not settle in one step" failures during this work were the
session idle-locking mid-run: a locked session gives no other surface frames.
`check.sh` now holds idle off for its run and the stack runner fails by name
on a locked session (`2faca3e`); a host without logind access still runs
unguarded.

## Not yet verified live

- Scroll: a trackpad flick over the volume or brightness widget, then a
  reversal right after a full step.
- Brightness: a display switch while a write is in flight.
- Slider accessibility values through an assistive technology.
- A smoke run of `check.sh` leaves no bar or exclusive zone on screen.
