# Agent instructions

Working rules for agents in this repository. What the fork *is* (branches,
upstream integration policy, the nixos-config re-lock ritual) is in
[README.md](README.md).
How to change the shell (new settings, new bar widgets, renames) is
upstream's [docs/forking.md](docs/forking.md). Each fact lives in exactly
one of the three files, so follow the pointers instead of restating.

## Boundaries

- Agents never run `git push`, `git tag`, `nixos-rebuild`, or
  `home-manager switch`. The maintainer runs those, always.
- Never restart the running shell. Test in a throwaway dev instance
  instead: `nix develop . --command qs -p shell.qml`. Quickshell
  hot-reloads the checkout when a file saves.
- Import upstream changes only when the maintainer authorizes the selected
  scope. Read-only inspection needs no approval. Follow README.md's selective
  integration policy and its separate authorization rule for full merges.

## Compositor priority

- Hyprland is the maintainer's primary desktop. Prioritize its behavior,
  implementation, and live desktop validation.
- Niri support is secondary but retained for possible future use. Preserve
  its backend and the shared compositor boundary; do not discard support
  or replace production behavior with stubs merely to simplify a task.
- Niri checks may use mocks, fixtures, or static inspection as appropriate.
  A live Niri session is not required to complete Hyprland-focused work.
  Label that coverage accurately; mocks do not establish compositor-level
  behavior. Do not pursue full Niri parity unless the maintainer asks.

## Git discipline

- `custom-branch` history is never rewritten: no amend, no rebase, no
  force-push. Nothing at or below origin gets rewritten either.
- One commit per task item. Subjects are short, lowercase, and imperative,
  like the ones already in `git log`. No Co-Authored-By and no
  AI-attribution trailer of any kind.
- A commit that creates, changes, or resolves a divergence from upstream
  updates [docs/upstream-divergences.md](docs/upstream-divergences.md) in
  the same commit. What counts as a divergence and when entries retire is
  defined in that file, not here.
- Code comments explain why, in the voice of the file they sit in. They
  never narrate what the change did.

## Gates before every commit

- New code is cohesive with the codebase around it: it follows the existing
  patterns, style, idioms, and architecture, and reaches for an existing
  abstraction before inventing a bespoke one. Any deviation carries a
  comment explaining why it was necessary.
- When a task has no precedent in the codebase to copy or work from, rely
  on standard QML best practices, patterns, and idioms before reaching for
  something clever or bespoke.
- `bash scripts/ci-lint.sh` passes.
- `nix develop . --command bash scripts/check.sh` reports zero failures. A
  small, stable set of environmental warnings is normal; investigate when
  the count changes, not because warnings exist. One known member: the
  deploy machine has no JetBrainsMono Nerd Font, and Qt's per-glyph
  fallback to Symbols Nerd Font is identical for Text and TextMetrics, so
  the ink-centering math still holds.
- The settings contract holds:
  `grep -c 'property' config/GeneratedDefaults.qml` equals
  `grep -c 'GeneratedDefaults\.' services/ShellSettings.qml`, and both
  match what nixos-config's silere module renders. Adding or removing a
  settings key ties the commit to nixos-config; README.md explains the
  ordering.
- The checked-in `config/GeneratedDefaults.qml` stays identical to
  upstream's defaults, so someone running the fork without Nix sees a
  stock shell. The deploying configuration swaps in its own render at
  build time. Never edit it to carry local preferences.

## QML work

- Load `qt-qml` (Claude plugin: `qt-development-skills:qt-qml`) before
  editing QML. Run the repository-local
  [qt-qml-review](.agents/skills/qt-qml-review/SKILL.md) to completion after
  substantial QML changes. Its references resolve relative to its skill folder.
  If `qt-qml` is unavailable, install it and reload skill discovery. The review
  skill is checked into this repository; do not install a global copy.
- Colors come from `Theme` tokens only; no hex in widgets. Motion goes
  through `Motion`/`MotionBehavior`, never a bare `Behavior`. Row heights
  come from `Metrics.rowHeightFor()`. The lint scripts enforce all three.
- The look is rounded rectangles, not pills, and text-driven minimalism.
  Extend the design system that's there; don't invent one-off styles.
- Minimalism is the design. Less is more unless specified otherwise
- Every new QML file needs a line in its folder's `qmldir`.
- Keep the `silere-*` layer-shell namespaces. The compositor's blur and
  animation rules match those exact strings.
