# Deliverable Review: batch-retry-approval-freshness

**Date:** 2026-09-26
**Methodology:** docs/references/deliverable-review.md

## Range

`edify-review-range.sh` printed `NO-PROVENANCE:`, so no range was inherited.
The range used is `533baa78..HEAD` — `4dd02bc^`, the commit before
`Item 1.1/1 — commit-memory bare mode commits on a fresh approval file` —
narrowed to the paths `design.md` §Work and `runbook.md` name. That span also
carries `16c15e9` (`a prepared merge outranks the summary screen on both
commit entry points`), a later change to the same two scripts and the same two
doc nodes; it is reviewed as part of the current truth of these deliverables,
and both Major findings sit on it.

## Inventory

| Type | File | +/- |
|---|---|---|
| Code | `scripts/cc-hooks/memory-commit-batch.sh` | +75 −18 |
| Code | `scripts/commit-memory.sh` | +24 −7 |
| Code | `scripts/lib/util.sh` | +24 −0 |
| Test | `tests/cc_hook_memory_commit_batch.bats` | +161 −1 |
| Test | `tests/commit_memory_approval.bats` | +155 −0 (new) |
| Test | `tests/commit_memory.bats` | +2 −11 |
| Human docs | `docs/references/commit-gate.md` | +144 −34 |
| Human docs | `docs/references/memory-entry-points.md` | +23 −11 |
| Human docs | `docs/decisions.md` | +18 −10 |
| Human docs | `docs/changelog/2026-09-24-…-approval-freshness.md` | +49 (new) |
| Human docs | `docs/changelog/2026-09-25-a-prepared-merge-….md` | +40 (new) |
| Human docs | `docs/changelog.md` | +35 |

**Design conformance.** Every In-scope item in `design.md` §Work is produced.
No missing deliverables. One unspecified deliverable —
`tests/commit_memory_approval.bats`, where §Work named `tests/commit_memory.bats`
— is explained in its own header (the approval-predicate cases split out;
`commit_memory.bats` is at 320 lines against the 400 cap), so it is acceptable
excess.

**Layer 1 delegation: skipped.** Plan-specific changed lines are ~640, inside
the 500–2000 band, but the surface is two scripts, three suites and three doc
nodes, and four delegated per-file reviews plus two corrector passes already
ran during execution (`reports/item-1-1-s*-code-review.md`,
`reports/phase-*-corrector.md`). Layer 2 was run in full — per-file axes and
cross-cutting — and both Majors come from reading the rule, the enforcer and
the consumer against one another, which is what delegation cannot reach.

**Verification run.** `shellcheck` clean on the three scripts.
`scripts/check-docs-links.py` clean (57 decisions, 140 files, 0 of every
counter). `scripts/run-bats.sh` over the three suites: 37 passed, 0 failed.
Both Major findings were confirmed by running the state through the real hook,
not by reading.

## Critical Findings

None.

## Major Findings

### M1 — A tier's prepared merge is answered with a re-approval request, and the merge directive is dropped

`scripts/cc-hooks/memory-commit-batch.sh:152` tests `gitlore_store_mid_merge
"$mempath"` — the root store only. `gitlore_sync_tiers_to_live` prepares a
head-vs-live merge **in the tier's gitdir**
(`scripts/lib/resolve-sync-tiers.sh:90`, "The merge lands in the tier's
gitdir") and returns without restamping the approval, so the root is not
mid-merge while the merge checkout has written newer content into
`$mempath/$tier/`. Freshness therefore reads `no` and the arm at
`memory-commit-batch.sh:164` fires, which deliberately drops `$out`.

Confirmed by running the state through the hook: tier `MERGE_HEAD` set, root
mid-merge `no`, freshness `no`, and the emitted messages are

- systemMessage: `gitlore: memory commit deferred — the approved summary no
  longer covers the store, approval needed again`
- additionalContext: the re-approval text plus the approval clause, and
  nothing else.

The dropped `$out` is the `gitlore: memory merge prepared (flavor=head-vs-live)
in store: …` directive — including the `gitlore:memory-merger` dispatch and the
`resolve.sh continue-after-merge` command. That string is also the trigger in
the `gitlore:resolve` skill description, so the skill does not self-invoke.

**Impact.** The user is asked to re-approve a summary for a state no summary
fixes, and the additionalContext's `the commit then completes on its own` is
false. After the agent obeys, the *next* batch does surface the directive (the
tier guard refuses again with freshness now `yes`, so the deferred arm carries
`$out`) — so it self-heals, at the cost of one wasted user approval turn and
one batch of delay on a required dispatch.

The arm's own comment and `docs/references/commit-gate.md:58-85` justify
dropping `$out` on the ground that it "is the sync's 'no approved commit
summary', which reads wrong next to a file that exists". That premise does not
hold for this state.

**Fix shape.** Make the mid-merge test tier-aware, the way
`gitlore_sync_memory_to_live`'s own `fresh != yes` branch already is
(`scripts/lib/resolve-sync-memory.sh:42-47` loops `gitlore_tier_paths`), or
order the freshness arm behind a check that `$out` does not already carry a
merge directive.

### M2 — The pre-run no-summary screen fires on a store whose tier is mid-merge

Same root cause, the other screen. `memory-commit-batch.sh:96` sets
`mid_merge` from `gitlore_store_mid_merge "$mempath"`, and the bypass at line
100 therefore does not apply when the merge is in a tier. With a tier
mid-merge and no approval on disk, the run never happens and the hook emits
the summary-request pair.

Confirmed by running it: additionalContext is `gitlore: a memory commit is
pending, but no approved summary exists yet. Summarize the pending memory
changes …  The commit then completes on its own — do not re-trigger it.`

**Impact.** This is precisely the D49 shape the line-87-94 comment block exists
to prevent — a merge both of whose sides the user already approved put in front
of them as a summary to draft — reached one level down. The closing promise is
false: a summary written in response still meets the tier guard.

`docs/references/commit-gate.md:94-101` states the bypass as "**A prepared
merge outranks that screen**, on both entry points", with no tier
qualification, so the node over-claims what the code does. The same root-only
gap is in `scripts/commit-memory.sh:72`, though there the sync's own tier loop
covers the stale-approval path.

`tests/cc_hook_memory_commit_batch.bats` has no test with a tier at all, which
is why both arms are green over these states.

## Minor Findings

**Documentation / usability**

1. `scripts/commit-memory.sh:28` — the usage string is still
   `usage: commit-memory.sh [-m <summary> | -F <file> | -F -]`. The bare
   invocation is now a documented first-class mode (header comment lines 9-10,
   `memory-entry-points.md`), and is the form the batch hook uses, but a
   mis-invocation prints a usage line that does not list it.
2. `docs/references/commit-gate.md:94` — "A prepared merge outranks that
   screen, on both entry points" and line 71's "A store **mid-merge**" both
   read as covering a tier's merge. They cover the root store only. Wording to
   be corrected with M1/M2, not independently.

## Gap Analysis

| Design requirement | Status |
|---|---|
| FR11 — approval covers what is committed, on the batch path | covered — `cc_hook_memory_commit_batch.bats:249` |
| D16 — `-m`/`-F`/`-F -` kept, bare mode additive | covered — `commit_memory_approval.bats`, `commit_memory.bats` |
| Design pt 1 — bare commits on the approval on disk, judged by freshness | covered — `commit-memory.sh:53-83` |
| Design pt 2 — the hook invokes `commit-memory.sh` bare | covered — `memory-commit-batch.sh:128` |
| Design pt 3 — failure message read off the store, never off a reported status | covered for the root store; **M1** for a tier |
| Design pt 3 — "no summary" means absent or blank, on both entry points | covered — `gitlore_approval_present` in `util.sh`, screened on both |
| Design pt 3 — the consumed-approval state tested ahead of freshness | covered — `memory-commit-batch.sh:143`, test at line 142 |
| Rejected alternatives recorded by name | covered — `decisions.md:45-52`, `commit-gate.md:366-382` |
| Docs: commit-gate mechanism, D16 bare mode, D56 line, changelog + index | covered; wording gap in **Minor 2** |
| Residual — agent writes memory after the message file in one batch | accepted in design, untested — acceptable |

## Summary

Critical 0 · Major 2 · Minor 2.

The plan's own defect is closed and the closure is well evidenced: the
three-batch test at `cc_hook_memory_commit_batch.bats:249` pins HEAD, both IPC
files, the approval's bytes *and* its mtime, and discriminates the branch by a
phrase the neighbouring arms do not carry. Both Majors are one root cause —
merge detection in the batch hook is root-only where the sync it wraps is
tier-aware — and both sit on `16c15e9` rather than on the plan's own two items.
Neither loses an approval or commits anything wrong; each costs a spurious user
round trip and delays a required `/gitlore:resolve` dispatch by one batch,
under a message that promises the commit will complete on its own.

`reports/tdd-audit.md` flagged four items for whoever closes Phase 2; three
have landed (`design.md`'s third state, the clean-branch wording, the
blank-approval predicate now in `util.sh`). The fourth — "a prepared merge met
with a request for approval" — landed for the root store only, which is M2.
