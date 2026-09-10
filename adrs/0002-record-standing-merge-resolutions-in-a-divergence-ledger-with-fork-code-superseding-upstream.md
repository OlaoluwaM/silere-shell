# ADR 0002: Record Standing Merge Resolutions in a Divergence Ledger with Fork Code Superseding Upstream

- **Status:** Superseded by [ADR 0003](0003-integrate-upstream-changes-selectively.md)
- **Date:** 2026-08-25

## Context

This fork takes upstream by merge, only at release tags, and never rewrites
`custom-branch` (README.md owns that ritual). At the time of this decision
the fork sits ~131 commits past the last merge-base with several upstream
releases pending, and it has begun diverging by *removal* as well as by
addition: the package-updates feature, the AUR packaging, the release
machinery, and the GitHub Actions workflows are all deleted here while
upstream keeps shipping them. Each merge so far has re-derived the same
intent from commit archaeology — which deletions are deliberate, which
shared files must end up as unions, whose version wins a contested hunk —
and the worst failure mode produces no conflict at all: upstream adding a
*new* file under a feature the fork removed merges in clean and quietly
resurrects the feature until a lint or the settings contract trips.

Three approaches were considered:

- **A. Status quo** — resolve each merge from scratch, trusting commit
  messages and memory. Free until merge day, then every deliberate
  divergence is re-litigated under conflict-marker fatigue, and the
  no-conflict resurrection case has no defense at all.
- **B. Git-native machinery only** — `rerere` plus `.gitattributes`
  `merge=ours` drivers. `rerere` genuinely helps repeated or aborted
  attempts, but it is textual, per-clone, expiring, and silent about
  resurrections. Merge drivers were rejected outright: no path here
  qualifies — deleted paths aren't covered by drivers, and the shared
  contract files need "upstream's version plus our additions", not
  "ours" — and a blanket `ours` silently discards upstream fixes.
- **C. A standing-resolutions ledger, with rerere as a complement** — a
  short document of invariant resolution policies (not a per-commit
  changelog), a one-direction lint check, and `rerere` enabled per clone
  for retry cheapness.

Approach C was chosen and its semantics were settled in a grill session,
which sharpened four rules: entry criteria (removals, shared-file
policies, and one blanket collision rule — never per-feature entries for
fork-only additions), retirement (only in the commit that moots an entry,
found by a mandatory post-resolve walk), the merge-day workflow
(mechanical resolutions in-merge; a conflict needing real judgment pauses
the merge and is decided cold), and scope (fork repo only; nixos-config's
coupling stays a README pointer). The docs policy that governs this repo —
each fact in exactly one file, invariants not snapshots — is what rules
out a diff-dump ledger: it would rot immediately, and drift is this
document's whole failure mode.

## Decision

Upstream merges are resolved from `docs/upstream-divergences.md`, which is
the single owner of the standing resolutions and of the rules for its own
entries. The doctrine it encodes: **fork code supersedes upstream**, with
one exception — when upstream implements a feature similar to something
the fork already built, the resolution is a case-by-case review that
pauses the merge rather than being decided mid-conflict.

Concretely:

- The ledger holds only invariants: keep-deleted paths, shared-file union
  policies with their contracts, and the collision default. Fork-only
  features get no entries.
- ci-lint enforces the keep-deleted block in one direction: a listed path
  that exists fails the gate, so a deliberate resurrection must retire its
  entry in the same commit.
- Ledger updates ride the commit that changes the divergence — including
  retirements inside the merge commit itself, via the post-resolve walk
  README's merge section prescribes.
- `rerere` is enabled per clone (README says how) so aborted or repeated
  merge attempts replay already-resolved hunks.

This record preserves the rationale; the ledger file, README's merge
section, and AGENTS.md's same-commit rule are the operating authorities
and are not restated here.

## Consequences

**Positive**

- Merge effort concentrates on genuinely new conflicts. Deliberate
  divergences resolve mechanically from the ledger instead of being
  re-derived from history every time.
- The conflict-free resurrection case — the one no git mechanism can
  catch — now has a named defense: the keep-deleted lint and the ledger
  walk.
- Judgment calls are structurally kept out of conflict-marker fatigue: the
  pause rule means the fork-supersedes default never hardens a decision
  that deserved review.
- Half of retirement is self-enforcing (lint fails on resurrection); the
  document cannot drift from the tree in that direction.

**Negative / trade-offs**

- The other half of retirement — upstream converging on a fork deletion,
  which produces no conflict and no lint failure — is caught only by the
  merge-day walk. That is human discipline, and a skipped walk leaves
  stale entries.
- Fork-supersedes is a default that can keep worse code: an upstream bug
  fix landing inside a contested hunk gets resolved "ours" mechanically
  unless the merger notices. The doctrine trades occasional lost fixes for
  predictable resolution.
- Nothing can *detect* a feature collision; the case-by-case exception
  fires only if the merger recognizes the similarity. The ledger names the
  rule but cannot trigger it.
- The full-sweep deletions this ledger protects (release machinery,
  workflows) grow delete/modify friction with every upstream touch of
  those paths; that cost was named and accepted when the sweep was chosen.
- One more document participates in the one-fact-one-file policy; every
  future rule addition must decide its single home (ledger vs README vs
  AGENTS) or drift returns by the back door.
