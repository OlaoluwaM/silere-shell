# ADR 0004: Adapt Glass Thickness to a Sampled Wallpaper Region

- **Status:** Accepted
- **Date:** 2026-10-24

## Context

Every glass surface in the shell paints one fixed alpha over the compositor's
blur: the bar at `barOpacity`, the popups and the menu pane at `glassOpacity`.
The tint under that alpha is the matugen background sunk toward black. On a dark
wallpaper the region behind the bar is already near black, so a dark tint at
64% leaves nothing to show through and the frost reads as a flat strip. On a
bright wallpaper the same alpha lets the picture overpower the text.

The maintainer's collection makes the spread concrete. Measured under the bar
after cover-fitting to the panel, the 403 wallpapers run the whole luminance
range: 142 sit below 0.2, 131 above 0.5, and 91 are noisy enough (standard
deviation above 0.2) that legibility depends on texture as much as brightness.
No single alpha serves that collection.

Three places could adapt, and two of them cannot:

- **The compositor.** Hyprland's blur parameters (size, passes, brightness,
  contrast, vibrancy, noise) are global. A layer rule can only switch blur on,
  set an ignore-alpha threshold, or xray. Nothing there varies per wallpaper
  without pushing `hyprctl keyword` values that a reload silently drops.
- **The matugen palette.** Its dark-scheme background is tone-fixed near
  `#131412` for every wallpaper, so the palette carries hue but no brightness
  signal. The shell already reads it and it would have been the cheap source.
- **The shell's own paint.** Alpha and tint are plain `Theme` tokens, and the
  shell already consumes one wallpaper-derived file (the palette) through a
  watched `FileView` with a central source animation (ADR 0001).

Prior art splits the same way. Apple's Liquid Glass adapts each layer of the
material to the content behind it and never paints solid; its older materials
are a thickness ladder from ultra-thin to thick. GNOME's unmerged panel work
classified the wallpaper region under the panel as dark, bright or noisy. KDE
and Blur my Shell adapt to windows, not wallpaper, and go opaque. Windows Mica
samples the wallpaper once into an opaque tint. The Quickshell shells looked at
(Noctalia, Caelestia, DankMaterialShell) use fixed opacities. The maintainer's
constraint was explicit: the glass must stay glass, never a solid colour.

## Decision

The wallpaper command samples the wallpaper and the shell derives the glass
from that sample.

`wallpaper-set` (owned by the deploying nixos-config) cover-fits the chosen
image to the focused monitor, measures the top strip, the bottom strip and the
whole picture, and writes mean luminance, standard deviation and a one-pixel
tone for each to `~/.config/silere-shell/glass.json`, version 1, after the
matugen retint and guarded so a sampling failure cannot abort the retint.

`config/GlassSample.qml` watches that file the way `MatugenPalette` watches the
palette: a malformed write keeps the last good values, a missing file reports
`usingFallback`, and the nine exposed values (luminance, noise and tone for
the top strip, the bottom strip and the whole picture) are plain animated
properties gated on the first load, so a swap eases once at the source and
every derived token follows. `Theme` picks the bar's edge downstream of the two
edges' Behaviors by bar position, so a position flip snaps while only a
wallpaper change eases. `ColorFade` gains a second gate on `GlassSample.transitioning`
for the same reason the palette has one.

`Theme` moves every glass surface along one continuous thickness ladder:

```
t     = clamp((L − 0.10) / 0.50, 0, 1)
n     = clamp((σ − 0.12) / 0.20, 0, 1)
alpha = clamp(base − 0.18 + 0.26·t + 0.08·n, 0.30, 0.95)
lift  = 0.10 · (1 − t)
tint  = mix(mix(paletteBackground, text, lift), tone, 0.10)   // 0 under neutralTheme
```

The bar reads the strip it sits on with `barOpacity` as its base; popups and
the menu pane read the whole picture with `glassOpacity` as theirs, so the two
packaged options keep their roles and the bar keeps its step above the popups.
The lift replaces the depth sink under adaptive glass: real frosted glass is
lighter than what sits behind it, and a dark tint over a dark region can only
darken. The compositor blur itself never changes; its constants are retuned
once, declaratively, in nixos-config.

A `glassAdaptive` setting gates all of it. The fork's stock default is off,
because an installation without the sampler has nothing to follow; the Nix
deployment turns it on. High contrast already disables glass and is untouched.

## Consequences

**Positive**

- Dark wallpapers get thin, lifted glass that shows the frost; bright ones get
  thick, dark glass that holds the text; noisy ones get a step thicker. The
  ladder is continuous, so there are no class boundaries to flicker across.
- One sheet of glass: the bar, the menu pane, notifications, calendar, tray
  menu, quick actions, keybinds and the OSD all move together, through the
  tokens they already read. No consumer changed.
- Nothing ever paints solid. The thickest rung is still a blur.
- A wallpaper change morphs the glass alongside the awww transition instead of
  snapping after it, by reusing ADR 0001's source-animation pattern.
- The packaged `barOpacity` and `glassOpacity` keep meaning something: they are
  the centre of each ladder, and the settings readouts report the effective
  value.

**Negative / trade-offs**

- A second file contract between nixos-config and the shell, beside the
  palette. The sample shares the palette's failure mode: a wallpaper set
  outside `wallpaper-set` leaves it stale and the shell keeps the last values.
  Nothing on the deploying machine writes the stable wallpaper path without
  running the script, so the exposure is the same as today's.
- The sample lands a beat after the palette, since the script writes it last.
  Two 400 ms source animations overlap inside awww's 2 s grow. Judged
  invisible, but it is two easings where there was one.
- The strip is measured once at the focused monitor's mode. A second display
  with a different aspect gets an approximation of its own edge.
- Small transient surfaces that paint opaque by doctrine (the bar hint, the
  rail tooltips) take the adaptive tint but not the alpha, so they may read
  heavier next to thin glass. Left for a live look.
- Theme bindings now depend on nine animated sources in addition to the
  palette's eight. The fan-out is the same set of tokens the palette already
  drives, so the per-frame cost during a swap is of the same order, not a new
  class of work.

**Data/product implications**

- `glass.json` is versioned (`version: 1`). A shape change bumps the version
  and the reader rejects what it does not know, keeping the last good sample.
- Adding `glassAdaptive` ties the fork commit to the nixos-config render of
  `GeneratedDefaults.qml`; both must reach the machine in one rebuild.
- An adaptive compositor brightness push was considered and deferred:
  brightness multiplies the blurred colour and cannot lift near-black, the
  value is global and lost on reload, and it would adapt on a different clock
  from the shell. If the dark band still looks flat after living with the
  ladder, it can be added from the same sample.

## Related

- [ADR 0001](0001-animate-wallpaper-driven-palette-changes-centrally-with-a-leaf-fade-gate.md): the central source animation and leaf-fade gate this reuses for the sample's nine values.
