# ADR 0005: Tune the Menu Glass and Secondary Text to the Menu's Own Corner

- **Status:** Accepted
- **Date:** 2026-10-30

## Context

ADR 0004 moves every glass surface along one thickness ladder. The bar reads
the strip it sits on; the popups and the menu pane read the whole picture. That
whole-picture sample is the wrong number for the menu. The menu opens under the
workspaces widget in one corner, and a wallpaper's brightness is rarely spread
evenly enough for the mean of the frame to describe one corner of it.

`battle-with-dragon.jpg` made it concrete. The whole frame measures luminance
0.27, so the menu pane sat at alpha 0.54 (`glassOpacity` 0.60). The menu's
corner measures 0.48 on average and 0.71 at its brightest tenth, because a lit
sky fills the top of it. Over that sky the light text reached 3.7:1 and the
secondary text 1.7:1; lower down, over the dark field, the same pane read at
roughly 7:1 and 3:1.

The secondary text made it worse. `_subtextBase` sinks `on_surface_variant`
toward the background so it sits a step below primary text. On dark glass that
sink is the hierarchy. On glass that the backdrop has turned bright, it moves
the secondary text toward the backdrop's own luminance, and the text vanishes.

The options weighed:

- **Flip to dark text on bright wallpapers.** Every token derives from `text`,
  so this is a second, light theme switched per wallpaper, with the accent and
  states re-solved for it. One flip for the whole pane still fails on a split
  wallpaper like this one. Rejected.
- **Solve alpha for a contrast floor.** A guarantee instead of a tuned curve,
  but Theme would have to model what Hyprland's blur brightness and vibrancy do
  to the backdrop, and the floor would drift silently when compositor.nix
  changes. Not taken; still available if the ladder proves too loose.
- **Feed the existing ladder the right region, and give secondary text some of
  its step back on bright glass.** Taken.

## Decision

`wallpaper-set` also measures the corner the menu opens into, under a top bar
and under a bottom bar: the menu's compact width (400 logical px, scaled by the
focused monitor) by its height cap (72% of the screen), at the left edge where
the workspaces widget leads the bar. Each corner carries the usual luminance,
noise and tone plus `peak`, the 90th-percentile luminance over 32×32 cells that
stand in for the compositor's blur. They land in `glass.json` as optional
`menuTop` and `menuBottom` regions; the version stays 1.

`GlassSample` exposes peak, noise and tone for both corners as animated values
under the same first-load gate as the other nine. A sample without the corners
(one written before the sampler measured them) still loads, and the corner
values follow the whole picture. A corner that is present but malformed rejects
the whole sample, as any malformed region already does.

`Theme` picks the corner by bar position, the way it picks the bar's strip, and
runs it through the unchanged ladder at its peak rather than its mean:

```
menuOpacity = ladder(glassOpacity, peak, noise)
menuPane    = withAlpha(adaptiveTint(peak, tone), menuOpacity)
inkLift     = 0.35 · t(peak)
subtext     = mix(subtextBase, text, inkLift)
```

The other popups keep the whole picture. The Glass opacity readout in Settings
reports `menuOpacity`, because the slider is read on the menu's own pane.

## Consequences

**Positive**

- On the motivating wallpaper the pane rises to about alpha 0.71: primary text
  over the sky goes from 3.7:1 to about 6.5:1, and secondary text, with the
  lift, from 1.7:1 to about 4:1.
- The ladder, its constants and its probes are unchanged; only its input moved.
- The file contract grows without a version bump, so either side of the
  nixos-config and fork pair can land first without stranding the glass.

**Negative / trade-offs**

- The peak is the worst case, so over a corner that is bright only at the top
  the darker rest of the pane wears more glass than it needs and shows less
  frost.
- `subtext` is shared. The bar and the other popups take the menu's lift even
  when their own backdrop is dark, which narrows their hierarchy. It never
  costs legibility, which is why one shared lift was preferred to splitting the
  token.
- The corner's geometry is copied from `MenuWindow` (`_compactW`, the 0.72 cap)
  and from the bar layout (the launcher on the left). Moving the launcher,
  widening the compact menu or opening a wider tab leaves the sample describing
  a slightly different area than the pane covers.
- The opaque fills that stand in for a wash over the pane (`_controlSolid`,
  and through it `controlFill`, and `menuHint`) still mix from the
  whole-picture tint, because the bar and the other popups share them. Inside
  the menu they now sit on a pane tinted from its corner, a little less lifted
  and with the corner's hue. The step is small; whether it shows is left open
  for a live look, and the fix would be menu-specific variants.
- Six more animated sources in `GlassSample`, fifteen in all.

**Data/product implications**

- `glass.json` regions are now either required (`top`, `bottom`, `field`) or
  optional (`menuTop`, `menuBottom`). An optional region is additive: older
  readers ignore it, and newer readers fall back without it. A change that
  older readers would misread still bumps the version.

## Related

- [ADR 0004](0004-adapt-glass-thickness-to-a-sampled-wallpaper-region.md): the ladder, the sample contract and the gate this extends.
