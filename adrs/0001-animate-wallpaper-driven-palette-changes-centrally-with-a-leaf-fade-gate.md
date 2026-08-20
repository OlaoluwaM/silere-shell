# ADR 0001: Animate Wallpaper-Driven Palette Changes Centrally with a Leaf-Fade Gate

- **Status:** Accepted
- **Date:** 2026-08-20

## Context

When the wallpaper changes, `wallpaper-set` runs Matugen, which rewrites
`~/.config/matugen/silere-shell.json`. `MatugenPalette.qml` watches that file and
replaces its eight source colors in one logical update. Today the visual result is
incoherent: the ~60 `ColorFade` Behaviors scattered across leaf controls (hover
fills, focus outlines) ease to the new colors over 150 ms, while every large
structural surface — the bar fill, popup cards, menu panes, settings cards, text,
hairlines, outlines — binds directly to `Theme` colors and snaps. The recolor is
ambient and system-initiated, which is exactly what makes the snap jarring; the
2-second awww grow transition happening behind it makes the mismatch worse.

Three approaches were considered:

- **A. Leaf-level additions** — add `ColorFade` to every surface that snaps.
  Individually safe, but coverage is never finished: text, gradients, badges, and
  every future color binding must remember to opt in, and anything missed snaps
  forever. Dozens of files now plus a permanent maintenance tax.
- **B. Central source animation only** — put Behaviors on `MatugenPalette`'s eight
  colors and leave the leaf fades running. Full coverage in one file, but every
  leaf `ColorFade` is retargeted on every animation frame (a Qt `Behavior` fires
  on each value change of the tracked property, including binding re-evaluations),
  producing double easing with a trailing tail and per-frame animation-restart
  churn across ~60 Behaviors.
- **C. Central source animation plus a global leaf-fade gate** — B, with
  `ColorFade.qml` defaulting its `MotionBehavior` gate off while the palette is
  transitioning, so leaf Behaviors pass writes straight through and the central
  animation is the sole easing authority.

Two facts of this codebase make C cheap: `ColorFade.qml` is the single definition
of every leaf color Behavior (all call sites are bare `ColorFade on color {}`),
and `MotionBehavior` already exposes a `gate` property that carries the
reduce-motion cut-off. `Theme.qml` also already animates a non-readonly singleton
property (`surfaceRadius`), so the central pattern has precedent.

A separate scoping question: `Theme` colors also change when settings flip —
neutral theme, base tone, Matugen depth, accent role, glass, high contrast. Those
paths restructure `Theme`'s derivations rather than flowing through the eight
Matugen sources, so a source-level fade does not cover them.

## Decision

Approach C. Wallpaper-driven Matugen palette changes animate centrally; leaf
color fades are suspended for the duration; settings-driven theme changes keep
snapping.

Concretely:

- `config/MatugenPalette.qml` drops `readonly` on its eight exposed colors and
  gives each a `MotionBehavior` + `ColorAnimation` with `duration: Motion.palette`
  and `gate: _everLoaded`. These source Behaviors must **not** use `ColorFade` —
  ColorFade's new default gate would disable them the moment the transition
  started. The `_palette` data update itself stays immediate and atomic.
- A `transitioning` flag is driven by a restartable `Timer` (interval =
  `Motion.palette`) armed inside `_load`, and **only when the parsed palette
  actually differs** from the current one — a byte-identical rewrite (same
  wallpaper re-applied) must not suppress hover fades for nothing.
- `config/ColorFade.qml` defaults `gate: !MatugenTheme.transitioning`. ColorFade
  remains the leaf-only primitive.
- `config/Motion.qml` gains `palette` (400 ms, ease-out, 0 under reduce-motion).
  The fade deliberately ends inside awww's 2-second grow rather than matching it:
  finished colors over a finishing wallpaper reads as intent; two animations
  ending together reads as lag, and a 2-second fade drags text through muddy
  intermediate contrast.
- Scope is wallpaper-driven changes only. Settings flips are user-initiated at
  the control, where instant feedback reads as responsiveness — and high contrast
  in particular must stay instant, since an accessibility mode that eases in is a
  worse accessibility mode.
- No guard is added to `wallpaper-set.sh`. The script is stateless (the stable
  path holds a converted PNG, so there is nothing to compare against), and
  re-applying the current wallpaper stays available as a repair action when awww
  or the palette file is in a bad state. The differ-check in `_load` is the
  single dedupe, and it defends against all writers of the JSON, not just the
  script.
- Startup snaps: the `_everLoaded` gate means the shell never cross-fades from
  the built-in fallback palette to the on-disk one during launch.

Files changed: `config/MatugenPalette.qml`, `config/ColorFade.qml`,
`config/Motion.qml`. Nothing changes in the Nix integration.

## Consequences

**Positive**

- Full coverage from one choke point: text, borders, hairlines, gradient stops,
  glass tint, and every derived `Theme` color sit downstream of the eight sources
  and inherit the fade with zero per-callsite edits. No stragglers, no audit, no
  opt-in burden on future bindings.
- Single easing authority during the transition — no double easing, no per-frame
  Behavior retargeting churn.
- Reduce-motion is correct for free: `Motion.palette` collapses to 0 and
  `MotionBehavior` disables, so palette changes snap and the gate never arms.
- Rapid consecutive wallpaper changes stay consistent: `Wallpapers.apply` already
  serializes latest-wins, and a new palette landing mid-fade retargets all eight
  source Behaviors in the same frame from their current interpolated values, so
  they converge together on the last file contents.

**Negative / trade-offs**

- `MatugenPalette`'s colors lose `readonly`, opening a theoretical door to an
  imperative write clobbering the bindings. Convention (and the `surfaceRadius`
  precedent) is the only guard.
- Every `ColorFade` in the shell now carries a global dependency on
  `MatugenTheme.transitioning`. The suspension window means hover and focus fades
  snap during the ~400 ms after a wallpaper change — judged imperceptible, but it
  is a real behavior change in a shared primitive.
- Settings-driven theme changes (neutral↔matugen toggle, base tone, depth) still
  snap. Deliberate, but if that snap ever grates, covering it means animating at
  `Theme`'s ~30 outputs — several of which are functions that cannot carry
  Behaviors — which is a substantially harder follow-up.
- During the fade, every downstream binding re-evaluates per frame, including
  `Theme`'s LCH math (gamut bisection in `lchColor`, `tintKeepingChroma`).
  Bounded and desktop-cheap, but it is per-frame work that did not exist before.
- The `transitioning` Timer approximates the animation window rather than
  tracking the Behaviors' actual running state. A deliberate simplicity trade:
  wiring into eight animation objects is the kind of cleverness
  `MotionBehavior.qml`'s own history comment warns against.
