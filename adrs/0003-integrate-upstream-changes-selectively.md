# ADR 0003: Integrate Upstream Changes Selectively

- **Status:** Accepted
- **Date:** 2026-09-09

## Context

The fork has independent audio, workspace, notification, media, and palette
behavior, and deliberately removes upstream distribution and update features.
The v1.0.0 integration required decisions across those areas and follow-up
fixes for settings migration backups, idle tooltips, and workspace menu access.
Full release merges concentrate many unrelated compatibility decisions into
one integration, even when only some upstream changes benefit the fork.

The September 4 selective imports provide a local precedent for taking useful
changes into retained fork implementations. Those imports also needed
corrections, so smaller scope does not replace dependency review or behavioral
validation. Continuing full release merges would retain upstream ancestry and
bring changes together, at the cost of repeatedly reconciling deliberate
divergences. Selective integration accepts responsibility for choosing and
maintaining the changes the fork takes.

## Decision

Use selective upstream integration as the default. Treat releases as review
checkpoints; select applicable fixes and wanted improvements from exact
released or development commits. Integrate one coherent change and its
necessary dependencies at a time, using direct picks where compatible and
adapting behavior where the fork has redesigned the implementation.

Retain source provenance and the divergence ledger protections introduced by
ADR 0002: deliberate removals, shared-file contracts, fork behavior taking
precedence, and explicit judgment for feature collisions. Update affected
entries with the integration that changes them. Full release merges remain
an exception requiring an explicit maintainer reassessment.

README.md owns the operating procedure, including selection, provenance,
upstream review records, and exceptional merge recovery. AGENTS.md owns agent
boundaries and commit gates; the divergence ledger owns standing resolutions.
Existing history and historical integration records remain intact.

## Consequences

**Positive**

- Each import has a bounded purpose and a smaller set of fork behaviors to
  review, test, and recover if it fails.
- Unwanted upstream features and redesigns stay outside the integration scope.
- Source provenance supports later fix reviews and dependency analysis.

**Negative / trade-offs**

- The maintainer owns periodic upstream triage; useful fixes can be missed.
- Later upstream changes may depend on skipped refactors, increasing the cost
  of adaptation or making an otherwise useful import impractical.
- Selective imports do not advance upstream ancestry. Any future full merge
  must reconcile earlier picks and adaptations, and comparison tools must
  distinguish ancestry from actual tree differences.
- Small imports can still carry incorrect assumptions. Repository gates and
  targeted runtime checks remain necessary.

## Related

- [ADR 0002](0002-record-standing-merge-resolutions-in-a-divergence-ledger-with-fork-code-superseding-upstream.md):
  superseded; its ledger protections continue under selective integration.
- [v1.0.0 integration record](../docs/upstream-merge-v1.0.0.md): evidence of
  reconciliation scope and follow-up fixes.
- [September 4 integration record](../docs/upstream-picks-2026-09-04.md):
  precedent for selective imports and their validation limits.
