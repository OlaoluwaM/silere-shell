# Validation evidence

Retained investigation and review artifacts from September 10, 2026. These
records describe the source and machine state at each checkpoint; statements
such as "not committed" or "untested" refer to that checkpoint. Later results
are linked from the earlier reports.

| Directory | Start here | Scope |
| --- | --- | --- |
| `bluetooth-discovery-20260910/` | [Results](bluetooth-discovery-20260910/RESULTS.md) | Adapter discovery failure and recovery after reboot |
| `bluetooth-hardware-20260910/` | [Results](bluetooth-hardware-20260910/RESULTS.md) | Live pairing, connection, removal, and the original details-loop finding |
| `bluetooth-details-fix-20260910/` | [Results](bluetooth-details-fix-20260910/RESULTS.md) | Synthetic regression and live verification of the binding-loop fix |
| `consistency-check-20260910/` | [Review](consistency-check-20260910/REVIEW.md) | Working-tree cohesion check and cleanup |
| `commit-review-20260910/` | [Commits](commit-review-20260910/COMMITS.md) | Final QML review, gates, and commit boundaries |

Raw logs preserve both failures and successful retries. Use the reports to
interpret them; a linter's exit code alone does not describe its findings.
Source hashes refer to the snapshot tested, including any comments present at
that time. Hardware addresses are redacted.

Recorded commands can reference temporary paths or this machine's checkout.
The controller-recovery script was prepared during diagnosis and never run;
reboot subsequently restored discovery. These artifacts are historical evidence,
not current recovery instructions. Use the maintained runners in
[scripts/](../scripts/README.md) for repeatable checks.
