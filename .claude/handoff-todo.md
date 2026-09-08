## Open decisions

- Whether to add a slice 4 to Item 1.1 covering the defect its slice-3 code review found and fixed (`plans/index-edit-propagation/reports/item-1-1-s3-code-review.md`, Major 1). The rc-2 abort preserved the approved summary file but not its freshness: whatever the partial compose wrote is newer than the msgfile, so `gitlore_commit_msg_freshness` reads it stale and the retry takes the FR11 refusal for a change the summary already covers. The fix — `touch "$msgfile"` before `return 1` — has no regression test; it was proven with a throwaway probe the reviewer then deleted, the shape `CLAUDE.md` §Testing forbids. The induction is fully described in that report: hook path, two tiers, root disagreeing with both carriers, `chmod a-w` on the *second* tier's directory, first `bash "$HOOK"` aborts, second commits with no new summary; needs the `[ "$(id -u)" -eq 0 ] && skip` guard. Recommended: run it as slice 4 (RED → test review → GREEN → code review) before the Phase 1 checkpoint; the alternative is folding the case in at the checkpoint, which skips the red. The same report lists two further unasserted surfaces to fold in or waive: the user arm of both messages (both slice-3 cases set `CLAUDECODE=1`, so only the agent text is pinned), and the `*)` arm, unreachable without stubbing `gitlore_compose` and reasonable to leave uncovered.

- Whether a memory commit should adopt an off-pin tier gitlink at all (same report, Major 2 — flagged and deliberately not fixed). The rc-1 refusal fires once, the commit's own `add -A` then stages the tier's moved gitlink and removes the condition that made it fire, and the next compose projects root's older text over the carrier without refusing — the D31/D36 destruction of approved upstream facts, delayed by one commit. Measured, and not a regression: the adoption predates change B. Fixing it means either aborting on a pin-mismatch rc 1, which contradicts the runbook's explicit "commit proceeds", or excluding refused tiers from the memory `add -A`, which is structural and touches the staging the `GIT_INDEX_FILE` handoff depends on. Default: carry it into the Phase 1 boundary checkpoint and record it as a decision or known residual rather than patch it there.

- The memory index against Claude Code's ~24,985-byte loader cutoff, per `plans/2026-08-27-memory-index-budget-decision.md`. The root index reports 102% of budget and is truncating. `plans/2026-09-02-ddaanet-design-moment-facts.md` frees ~4,600 by relocation and merges, and the three dropped briefs a further ~10,400. Decide: run curation first and re-measure, or still do the composition reorder (D29 layout rule, D36 rewrite, `gitlore_order_merge` in `index-composition.md`). `sandbox-effects` holds 988 bytes of the overshoot and retires as sandbox-lies phase 4, which changes the arithmetic.

- Which gitlore-side tier merges from `plans/2026-09-02-ddaanet-design-moment-facts.md` to execute: `plan-writing` (7 facts to 1), `guard-design` (3 to 1), folding `test-the-invocation-path` into `green-is-not-evidence`, `imperative-form-scope` into `skill-description-purpose-first`, `markdown-formatter-choice` into `claude-plugin-dev`, `bash-prolog-common-foundations` into `justfile-gotchas`, `no-transition-special-cases` into `remove-cleanly-no-vestigial`; and whether `loose-generation` gets a trigger or is retired. Several are brief-bound, so order matters: merge then convert, or convert then merge.

- Whether the guard and validation design facts go to `craft` (current default) or to `prohibitions`.

- Whether the toolkit release-and-vendoring skill belongs in `plugin-craft` or in `claude-plugin-dev`'s own `toolkit/README.md`, which already ships with the vendored files.

- `reconstructable-two-categories` is a handoff-design lesson: whether to drop a note in the handoff repo proposing it move to handoff's own store.

- Whether a one- or two-line phantom-dotfile prohibition (never delete, commit or report one) goes into `memory/ddaanet/shared-claude.md`. No hook fires on the `` !`cmd` `` expansion path, so prose is the only mechanism that covers the `/commit` `## Context` case. The orchestrate skill's `verify-step.sh` exits 1 on a tree whose only dirt is those phantoms — seen again at the end of Item 1.1, where every listed path was a phantom and the real work was fully committed — so a mechanical gate already misreads them as uncommitted work.

- Whether `2026-09-02-bang-expansion-hook-decompile.md` belonged in the move to sandbox-lies. Its finding — no hook dispatches on the `` !`cmd` `` path — matters to gitlore independently as a hook-heavy plugin.

- The recall-size hook fires on `memory/ddaanet/shared-claude.md` demanding it be cut under 2.8KB, but that file is imported whole by `CLAUDE.md` and is never a recall target, and it has been well past 4KB for a long time. Decide whether the hook should exempt the tier conventions file or whether the warning is doing something the exemption would lose.

## Remaining

- Narrow `test-unit`'s gate inputs to exclude `tests/integration_*` once the split has run a while; all three gates share `precommit_inputs` for now, which is why `test-unit` and `test-integration` carry the same input hash.

- Triage `inbox/brief-add-tier-index-budget-advisory.md`: `/gitlore:add-tier` composes the root index but cannot warn that the result overflows the loader cutoff, and the mount is the one operation that adds tens of KB in a single step.

- Split the oversized token-keyed facts so recall reaches them: `hook-output-channels` (23% reachable), `bats-shellcheck-gotchas` (40%), `stale-plugin-code` (45%), `design-doc-writing` (over 4KB, and being cut into a craft skill — check before splitting). Hub under 4KB carrying the symptom table, siblings beside it. `subagent-hook-output-confined` is a natural sibling of `hook-output-channels` once the hub exists.

- Extend the memory-writing skill's index-line guidance to both axes: a design-moment trigger needs a symptom-shaped hook or a home at a skill checkpoint, and a body past 4096 bytes is unreachable beyond that point whatever its trigger.

- Rerun `plans/2026-09-02-recall-log-analysis.py` once a week or two of native-recall attachments exist; report the harness class and selector precision.

- Continue the ddaanet review pass from the queue in `plans/ddaanet-memory-review.md` (entry 5, `hook-output-channels`).

- Check the bang-expansion decompile report's verbatim excerpts against the CC 2.1.258 bundle before trusting its verdict; it lives at `sandbox-lies/plans/2026-09-02-bang-expansion-hook-decompile.md`.