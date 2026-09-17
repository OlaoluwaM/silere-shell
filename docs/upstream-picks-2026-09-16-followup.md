# Selective upstream follow-up: smoke isolation and pairing timeout

Status: implemented, validated, and independently reviewed. The maintainer
authorized two atomic commits after accepting the external review. Base:
`75aaef0018ab8fb950b974348f81f672da1efe03`.
The [earlier plan](upstream-picks-2026-09-16.md) records completed stages 1–9.
This follow-up covers two additional tasks. A full merge, deployment, and
changes to the other candidates below remain outside its scope.

## Review range and selection

A fresh upstream fetch found eight commits after the earlier review point
`1c01251d597ff7d3ff673a9669b2fe087ab42f72`. The reviewed tip is
`0ffa657ffbfb7caefc04f59c0e6bf7a9eed0760a`.

| Source commit | Disposition |
| --- | --- |
| [744044e2313f1113df91e93aced68fd820e64dd4](https://github.com/s3rven/silere-shell/commit/744044e2313f1113df91e93aced68fd820e64dd4) | Selected: isolate the startup smoke test's configuration. |
| [1a97c1b380172665e8821727910aba82cdb16e2f](https://github.com/s3rven/silere-shell/commit/1a97c1b380172665e8821727910aba82cdb16e2f) | Selected: bound the Bluetooth pairing guard. |
| `0ffa657ffbfb7caefc04f59c0e6bf7a9eed0760a` | Already covered: the fork's media seek control uses SliderTrack, which retains the pointer grab. |
| `534a9542719d64857579d1083b2c0fd3c6a24da4` | No pick: fork idle handling clears OSD entries and destroys their delegates; the upstream bump owner is absent here. |
| `3e1902416c40bb2031e79dce7c600800bf4f7906` | Separate simplification review: fork arrival and delayed-restore guards already protect reused notification IDs. Removing disk metadata needs its own history semantics review. |
| `aed5e041a2d34052ba8d54104d93e80652f35a55` | Deferred with automatic compositor-instance restart, which the fork has not adopted. |
| `f93047406fa3f6f62a467947c0aee8d646f9d54f` | Not selected: the motivating updater rollback path is removed here. A suite-wide notification stub remains optional defense. |
| `acd1d7f5f6e6acb74a54bb273ccb58628157aa37` | Deferred: adapt its missing-tools layout fixture separately, preserving the fork maintenance page and removed update page. |

Previously deferred `4fb1c1142aa7ce25ef38b7c3353a1b03c33deea8`
(hidden-setting dots) remains a smaller follow-up candidate. It is outside the
authorized two-task implementation.

## Task 10: smoke-test configuration isolation

Keep the fork's sequential smoke cases and shared `_run_shell_probe` launcher.
The startup case must run with a private copy of the real Silere configuration;
coverage and malformed-settings cases retain their own disposable roots.

The copy must preserve the settings being checked without retaining writable
symlinks into live state. Missing configuration permits an empty private root.
A failed copy must fail the startup check instead of quietly testing defaults.
Clean up the copy on success, error, and interruption. Use the existing XDG
resolution rule, including absolute-path handling and HOME fallback.

Acceptance uses disposable fixture sources: verify copied contents, unchanged
source bytes after test writes, symlink isolation, missing-source handling,
copy failure, and cleanup. This isolates shell-owned configuration writes.
It does not promise isolation of arbitrary configured commands, absolute paths,
or desktop-service connections.

## Task 11: bounded Bluetooth pairing guard

Preserve upstream's eight extensions of the 20-second attempt guard. Pairing
that never leaves its active state expires on the ninth interval. Every new
attempt gets a fresh extension budget. Ordinary connections retain their
existing timeout; successful pairing and cancellation retain their cleanup.

Keep the fork's 60-second adapter pairable timeout and restore only pairable
state owned by this service. That timeout bounds incoming pairing availability;
it is distinct from tracking an attempt already in progress. Do not change
forget guards, device identity handling, radio controls, or real devices.

Acceptance extends the existing production-service fixture with a shortened
timer: active pairing survives its first interval, a stuck attempt eventually
fails, success before the bound still works, a later attempt gets a fresh
budget, and adapter cleanup preserves state owned by another actor.

## Execution and review

The maintainer approved two implementation ICs at gpt-5.6-terra/medium, one
per task. Each must review specification compliance and code quality before
returning. The lead owns architecture, shared documentation, integration,
independent inspection, and final judgment. A conditional gpt-5.6-sol/high
adversarial reviewer is approved if the resulting changes warrant it.

Run targeted fixture regressions first. After reviewing smoke isolation, run
`bash scripts/ci-lint.sh` and `nix develop . --command bash scripts/check.sh`.
Keep the 53-key settings contract unchanged. Fixture results do not establish
live Bluetooth behavior; prior live acceptance limits remain in the earlier
plan. Commit each task separately with its corresponding divergence entry.

## Results

Both ICs completed their changes and self-review at the approved
gpt-5.6-terra/medium tier. The lead reviewed both diffs, extended the smoke
fixture requirements to cover launch gating, and corrected the pairable-timeout
comment against BlueZ's adapter documentation. The approved gpt-5.6-sol/high
reviewer independently checked copy failures, cleanup, and pairing lifecycle
boundaries and found no introduced defects. It also passed both focused
fixtures, shell syntax checks, and `git diff --check`. The lead accepted the
changes with no unresolved findings.

The smoke helper copies configuration into a disposable XDG root, materializes
symlinks, and blocks startup when preparation fails. Its fixture runs through
`test-portability.sh`, so both repository gates exercise it. The Bluetooth
service resets its extension counter on every attempt and expires active
pairing after eight extensions, preserving the fork's adapter ownership rules.

Validation completed on 2026-09-16:

- `bash scripts/test-smoke-config.sh`: passed, exit 0.
- `bash scripts/ci-lint.sh`: passed, exit 0.
- `nix develop . --command bash scripts/check.sh`: passed, exit 0, zero failures
  and four existing environment warnings. These concern optional
  `powerprofilesctl`, autostart, and two missing Matugen configuration entries.
- The full suite passed all 22 connectivity-path fixture checks, 248 popup
  lifecycle checks, startup/off-path/malformed-settings probes, surface builds,
  165 live settings states over 55 test surfaces, and layout-fit checks.
- Bluetooth `qmllint` with the repository's import roots and `--json -`:
  passed, exit 0, zero diagnostics. Source hashes confirmed no file mutation.
- The IC's disposable unbounded-timer regression failed at its watchdog as
  expected, establishing that the fixture detects the original pairing bug.
- GeneratedDefaults, ShellSettings references, and the Nix module still have
  53 matching setting names and types. No settings schema changed.
- All six changed code files retained their hashes throughout the lead's
  final gates. `git diff --check` passed.

One IC validation command mistakenly supplied `services/Bluetooth.qml` as
`qmllint --json`'s output filename and overwrote it. That result was discarded.
The IC restored the previously clean file from the base commit and reapplied
the intended patch. The lead inspected the restored diff; the focused fixture,
corrected type check, and full suite then passed. No user edits were lost.

Bluetooth validation uses fixture devices and a shortened production timer.
It does not establish live-device pairing behavior. Runtime shell checks used
throwaway instances; the production shell was not restarted. The small service
change received IC, lead, and independent review; it did not rerun stage 9's
six-mission QML review.

## External review

Claude (Fable 5.1) independently reviewed the same base and ten changed files
on 2026-09-16 and reported no confirmed introduced defects. Its report is
`/tmp/silere-upstream-followup-claude-review-2026-09-16.md`. Claude compared both
upstream patches and passed the smoke fixture, repository lint, all 22
connectivity-path checks, and `git diff --check`. It did not repeat the full
suite or type check. The lead confirmed that all six changed code files still
match the previously validated hashes.

Claude identified one intentional consequence: a dangling symlink anywhere
under the source Silere configuration fails the private copy and startup check.
This includes unrelated stale hook links. Retain the strict failure policy;
silently skipping startup would allow a passing gate without validating the
maintainer's actual configuration. Fix the local link when this occurs. No
code changes or additional tests were needed to accept this review.
