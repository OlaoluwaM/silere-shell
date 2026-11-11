# ADR 0006: Stop Reconciling with Upstream and Take Only Chosen Cherry-Picks

- **Status:** Accepted
- **Date:** 2026-11-11

## Context

This project began as a fork of
[s3rven/silere-shell](https://github.com/s3rven/silere-shell) and was kept
reconcilable with it. ADR 0002 set up a divergence ledger,
`docs/upstream-divergences.md`: the standing resolutions an integration applies
where this code and upstream collide, a keep-deleted list of paths the fork
removed on purpose, and the rules for the ledger's own entries. ADR 0003
replaced routine full release merges with selective integration, but kept the
ledger's protections and left a full merge open as an exception the maintainer
could approve.

Keeping that path open cost something on ordinary commits, not only on
integration days. AGENTS.md required every commit that created, changed or
resolved a divergence from upstream to update the ledger in the same commit,
and ci-lint failed whenever a keep-deleted path existed again. The standing
resolutions were written as instructions for imports: what an import of a
given file must keep, re-apply or convert. At the commit before this ADR's
(`ea94bddb`) the ledger ran to 770 lines, with 33 keep-deleted paths and 84
standing resolutions, and 172 commits had touched it since it was added on
2026-08-25. ADR 0003's own consequences name the rest of the cost: selective
imports never advance upstream ancestry, so a later full merge would have to
reconcile every earlier pick and adaptation; later upstream changes can depend
on refactors the fork skipped; and the maintainer owned periodic upstream
triage.

On 2026-11-11 the maintainer decided that the project goes in a direction of
his own choosing from here on, with no reconciliation with upstream at any
point. He may still cherry-pick ideas and commits from upstream. He asked for
the ledger to be dropped, since git history keeps it if it is ever needed.

## Decision

This project is developed in its own direction. There is no reconciliation
with upstream, at any point, and no full merge of upstream, routine or
exceptional.

An upstream idea or commit comes in only as an individual cherry-pick that the
maintainer chooses, adapted to this code. A pick records its source as
README.md describes: the commit message names the upstream repository and the
full source SHA.

The divergence ledger is dropped. `docs/upstream-divergences.md` is deleted,
together with the ci-lint check of its keep-deleted paths and the AGENTS.md
rule that a commit changing a divergence updates the ledger in the same commit.

This supersedes ADR 0003 and the ledger that ADR 0002 set up and ADR 0003
kept. From ADR 0003 it ends releases as review checkpoints, the full-merge
exception and the retained ledger protections. ADR 0003's practice for a
single change carries over to cherry-picks: one coherent change with its
necessary dependencies, a direct pick where it fits and an adaptation where
this code has been redesigned, with its provenance recorded.

## Consequences

**Positive**

- Merge cost stops constraining design and naming. A change no longer has to
  weigh how a later merge would reconcile it, and a rename, removal or
  redesign leaves no ledger entry to write or retire.
- Ordinary commits carry less bookkeeping: no same-commit ledger update and no
  keep-deleted check.

**Negative / trade-offs**

- Upstream fixes no longer arrive unless they are picked. A fix to code the
  two projects still share can be missed.
- Picks get harder over time. As this code moves away from upstream, fewer
  upstream commits apply cleanly, more need adapting, and some will not be
  worth taking.
- The standing resolutions the ledger held are no longer maintained. They live
  only in git history; recover the file from the commit before this ADR's,
  `ea94bddb`, with `git show ea94bddb:docs/upstream-divergences.md`. A pick
  into an area the ledger covered has no current note of what this code does
  differently, beyond commit messages and code comments.
- Nothing checks the keep-deleted paths any more. A pick can bring back a path
  the fork removed on purpose, such as the updater or the release machinery,
  and only the review of that pick will notice.
- Code comments that tell a reader to keep a behaviour on an import or to
  re-apply it on a merge stay in place. They still record why the code is as
  it is; as instructions they are moot.
- The dated integration records under `docs/` stay as history. Their
  approvals and procedures do not apply to new work, and their links to the
  ledger now name this ADR instead.

## Related

- [ADR 0002](0002-record-standing-merge-resolutions-in-a-divergence-ledger-with-fork-code-superseding-upstream.md):
  set up the divergence ledger this drops.
- [ADR 0003](0003-integrate-upstream-changes-selectively.md): selective
  integration, which this supersedes; its practice for a single change carries
  over to cherry-picks.
