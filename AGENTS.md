# Agent instructions

Working rules for agents in this repository. What the fork *is* — its
branch model, merge policy, and the nixos-config re-lock ritual — lives in
[README.md](README.md). The mechanics of changing the shell — new settings,
new bar widgets, renaming — are upstream's
[docs/forking.md](docs/forking.md). Each fact lives in exactly one of the
three files; follow the pointers rather than restating.

## Boundaries

- Agents never run `git push`, `git tag`, `nixos-rebuild`, or
  `home-manager switch`. The maintainer runs those, always.
- Never restart the running shell instance. Verify changes in a throwaway
  dev instance instead — `nix develop . --command qs -p shell.qml` —
  Quickshell hot-reloads the checkout on file save.
- An upstream merge starts only on the maintainer's explicit go, never on
  inference from context.

## Git discipline

- `custom-branch` is never rewritten: no amend, no rebase, no force-push,
  and nothing at or below origin is ever rewritten.
- One commit per task item. Subjects are short, lowercase, and imperative,
  matching `git log`. Never add Co-Authored-By or any AI-attribution
  trailer.
- Code comments are maintainer why-comments in the voice of the file they
  sit in, never narration of the change.

## Gates before every commit

- `bash scripts/ci-lint.sh` passes.
- `nix develop . --command bash scripts/check.sh` reports zero failures. A
  small, stable set of environmental warnings is the baseline — investigate
  a change in the warning count, not its existence. One known member:
  JetBrainsMono Nerd Font is absent on the deploy machine, and Qt's
  per-glyph fallback to Symbols Nerd Font is identical for Text and
  TextMetrics, so ink-centering math holds.
- The settings contract holds:
  `grep -c 'property' config/GeneratedDefaults.qml` equals
  `grep -c 'GeneratedDefaults\.' services/ShellSettings.qml`, and both
  match what nixos-config's silere module renders. Adding or removing a
  settings key couples a commit to nixos-config; README.md describes the
  ordering.
- `config/GeneratedDefaults.qml` stays upstream-identical in the checked-in
  tree, so non-Nix users see stock defaults; the deploying configuration
  substitutes its own render at build time. Never edit it to carry local
  preferences.

## QML work

- Load the `qt-development-skills:qt-qml` skill before editing QML; run
  `qt-development-skills:qt-qml-review` to completion after substantial QML
  changes.
- Colors come from `Theme` tokens only — no hex in widgets. Motion goes
  through `Motion`/`MotionBehavior`, never a bare `Behavior`. Row heights
  come from `Metrics.rowHeightFor()`. The lint scripts enforce all three.
- The visual language is rounded rectangles, not pills, and text-driven
  minimalism. Extend the existing design system; do not add one-off styles.
- Every new QML file needs a `qmldir` entry in its folder.
- Keep the `silere-*` layer-shell namespaces: compositor blur and animation
  rules match those strings.
