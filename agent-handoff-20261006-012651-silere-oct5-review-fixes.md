# Handoff: silere-shell Oct 5 session — review fixes pending

## Goal
Finish hardening the Oct 5 work (two screencast fixes, the Oct 4 upstream batch, test-infra changes) by applying the
fixes from a 5-reviewer adversarial pass, then hand Olaolu a clean branch to merge/push himself.

## Mode and authority
- **Ship · Full** under `/orchestrate` (Olaolu opted in). Speak handoffs in one line; never commit without showing
  the diff and getting a nod (he has said "commit" per item each time).
- Approved roster tiers: Sonnet for implementers/adversarial reviewers, Haiku for 1-file mechanical ports.
  New roles or tier escalation need fresh approval.
- AWAITING APPROVAL: the 5-commit fix plan under "Next steps" (Olaolu answered with the branch move + handoff
  instead of a yes/no — re-ask before committing).
- Never: `git push`, tags, `nixos-rebuild`, `home-manager switch`, restarting the live shell, pkill/pattern kills.
- Mark residual risks "open" until Olaolu accepts them (memory: silere-no-self-accepted-risks).

## Workspace
- Repo `/home/olaolu/Desktop/dev/silere-shell`. **Checked out: `custom-branch-oct5`** at `2faca3e` (12 commits on
  top of `1fa15a6`, all unpushed). On 2026-10-06 Olaolu asked to move all session work off `custom-branch`;
  `custom-branch` was pointed back to `1fa15a6` (= `origin/custom-branch`). No history at/below origin changed.
- Commits on the branch (oldest first): `2fca53a` history-row overlap, `c2368d6` ConfirmButton under glass,
  `1877a3c` ledger: blur stays on Hyprland layer rule, `92c4607` smoke/probe isolation, `f9834a5` slider,
  `abe2d94` brightness, `526dcd7` scroll, `3ccf6b6` sysinfo, `e190514` close identity, `bbec7d5` malformed history,
  `2862066` record `docs/upstream-picks-2026-10-04.md` + README pointer, `2faca3e` idle-inhibit + lock check.
- **Uncommitted (mine): `scripts/probe-lib.sh` `_probe_stop` rewrite** fixing Codex's 3 findings (ppid ownership
  check, kill surviving group after reaped leader, `ps` failure under errexit). Lint + full `check.sh` passed on it
  BEFORE the round-2 findings below; it still has 2 known holes (see Next steps 1).
- No agent worktrees remain (`git worktree list` = main only). Scratch material:
  `/tmp/claude-1000/-home-olaolu-Desktop-dev-silere-shell/311a64ba-485a-4caa-9f7d-d5e6c2eda212/scratchpad/`
  (`gate.sh` = lint + check.sh wrapper; `orchestrate-plan.md` = full decisions/findings log; `patches/`).

## Evidence trail
- Gates: every committed item passed `bash scripts/ci-lint.sh` + `nix develop . --command bash scripts/check.sh`
  (0 failures, 4 known env warnings: powerprofilesctl, autostart, matugen tmpl/cfg). Final PROBE-LOGIC 554 checks.
- `ci-lint.sh` scans `.claude/worktrees/` — remove any agent worktree before gating.
- Notification-stack "flake" = hypridle `loginctl lock-session` at 600s (journal 20:34:06–20:35:36) → no frames to
  non-lock surfaces; fixed in `2faca3e` (systemd-inhibit re-exec in `scripts/check.sh:8-16`).
- Codex review: `/tmp/silere-adversarial-review-2faca3e.md`. Round-2 findings consolidated in
  `.../scratchpad/orchestrate-plan.md` ("Review round 2").
- Hyprland 0.56.2 `shouldBlur` (Renderer.cpp): a surface's background-effect region fully overrides layer-rule blur.

## Dead ends / ruled out
- `_probe_rm` retry-cleanup (symptom fix) → replaced by setsid + group kill (Olaolu's call).
- Lazy FontScan (upstream `07d23db`), forced-save guard (`afe4242` PersistedFile), menu preload expiry, protocol
  blur regions: all DECLINED by Olaolu — recorded in the record/ledger; don't relitigate.
- Amending `1877a3c` body typo (`995f262d`): not done (would rewrite 9+ commits; AGENTS.md forbids).

## Next steps (await Olaolu's go; one commit each, gate each)
1. `_probe_stop` holes: if `ps` yields nothing but `kill -0 "$1"` succeeds → old single-pid TERM/poll/KILL (repro:
   shadow `ps(){ return 1; }` with a TERM-ignoring setsid child → hangs rc 124); reject pid not `^[1-9][0-9]*$` or ≤1
   (`_probe_stop 0` would `kill -KILL -- -0` = own group). Verify: owned-process tests (normal group, reaped leader
   + child, ps failing, foreign pid, non-setsid, pid 0/""/abc) + gate. Commit with the uncommitted rewrite.
2. Brightness NaN/Infinity probe checks are vacuous (`controllable` false offscreen): force `Brightness.ready` for
   those checks (restore after); add a check for `lastError` reset on display switch. Verify: removing the
   `isFinite` guard in a scratch copy now fails probe-logic.
3. Slider `_posToVal`: return `max` at ratio ≥ 1, `min` at ≤ 0 (repro: min 0.2 max 0.9 step 0.3 → 0.8). Verify new
   probe check fails before / passes after.
4. Lock check `pgrep -u "$(id -u)" -x hyprlock`; check.sh re-exec with `"$BASH"`. Verify: fake-pgrep FAIL path +
   `systemd-inhibit --list` shows `silere-check` mid-run.
5. Docs: record — replace "random" flake text with lock cause; a2cff64 is the outside-click fix (not the split);
   slider bullet also skipped QuickSlider `_requestExpand` guard + GradientSlider min/max a11y; state untriaged
   remainder of afe4242/066b3c0/af8cde3. Ledger — check.sh bullet: group stop (not "only the child"), "probe windows
   stay unmapped" excludes the stack probe, logind-less runs unguarded; add setsid/group-stop entry; note the
   once-per-engine restore invariant behind skipping upstream's per-read writeAllowed reset. Verify: lint.
6. Then hand back: Olaolu decides merging `custom-branch-oct5` into `custom-branch`, push, nixos-config re-lock.

## Open questions / blockers
- Olaolu hasn't approved steps 1–5 yet.
- Untriaged Hyprland-relevant upstream hunks in `afe4242` `services/CompositorHyprland.qml` (dead event-socket
  restart, twin workspace events double rebuild, 0.57 string workspace address) — suggested as next triage.
- Informational, left as-is unless asked: hidden-page insert sizing (RecentPage reads `_body.visible`),
  NotificationCard sizes from Column implicitHeight, HistoryGrouping:61 TypeError on burst removal, unmapped smoke
  bars skip bar render, SIGKILLed runner orphans probe group, test coverage gaps (SysInfo onLoadFailed, Scroll reap,
  `!fromFuture` exemption).
- Incident: an infra reviewer ran `pkill -f "sleep 30[01]"` (rule break); impact unknown, disclosed to Olaolu.
- Live checks never done: trackpad scroll flick/reversal, brightness switch mid-write, slider a11y via AT, smoke
  run leaves no bar on screen.

## Suggested skills
`qt-development-skills:qt-qml` before QML edits; repo `.agents/skills/qt-qml-review` after; `consistency-check`
before commits; `orchestrate` if delegating; `debug` for any gate failure.
