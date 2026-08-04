## Current task

No thread is mid-flight. The distribution-checks brief is applied:
`check-distribution` gates `tests/plugin_distribution.bats` behind its own
sentinel and hangs off `precommit`, so `agents/`, `commands/` and `skills/` can
no longer change while the gate reports cached. Its coverage was proven
empirically on each of the three directories rather than reasoned about, and
`tests/justfile_gates.bats` asserts both dependency edges via
`just --dump --dump-format json`, since dropping either would restore the blind
spot without failing anything else.

The brief's claim that the hole was live at v0.4.5 did not hold — both commits
since v0.4.4 that touched those directories also touched `scripts/` and
`tests/`, so the hash moved and the suite ran.

## Open decisions

- `memory/ddaanet/shared-claude.md` states "refer to the user as 'my human
  partner', never by name" and its own final section says "get David's call".
  Correcting it is a shared-tier edit that changes what every mounting repo
  loads, so it is my human partner's to make.
- Whether gitlore's recall replaces `additionalContext` injection with an
  instruction to batch-Read the memory files not yet in context. Injection
  truncates past ~2KB into a spill file and does not satisfy the Read
  requirement, so a memory just shown still needs a Read before it can be
  edited; a Read-based recall primes the update path and simplifies the ledger.
  What it gives up is unconditional delivery, since an instruction can be
  deferred mid-task — which is the condition recall exists for. Needs a
  `docs/design.md` entry stating what happens on non-compliance.