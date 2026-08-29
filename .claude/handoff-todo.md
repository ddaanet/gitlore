## Open decisions

- The `commit` skill for `commit-memory.sh`, per `plans/2026-08-27-brief-commit-memory-missing-skill.md`. Three options: leave it (memory already covers standalone administration); add the standalone-administration sentence to the commit gate's own block message, which reaches an agent exactly when it is stuck and costs no per-session context (recommended); or ship `/gitlore:commit` and revise D16's scoping in `docs/references/commit-gate.md`, accepting that every session learns the standalone path. The brief's own recommendation was the third, and it is refused as written: the gate's trigger is deliberately kept out of general agent-facing instructions, and the proposed body cannot work anyway because that path goes through an intent file and a PostToolBatch hook precisely to sidestep the sandbox and the auto-mode classifier. `commit-gate.md` states that exclusion covers the block message too, so the second option revises a stated exclusion, not just a message.

- The memory index against Claude Code's ~24,985-byte loader cutoff, per `plans/2026-08-27-memory-index-budget-decision.md`. The index sits over both the 25,600-byte gitlore budget and the loader cap, and the restored ddaanet routing clauses added to it; three sweeps agree curation cannot close the gap. Recommended: reorder composition so tier blocks come last, so this repo's own lines and the newest facts stop being the truncated tail, then take `ddaanet` sub-scoping as its own subproject. The third option is to accept the overage and push the cap back upstream. Reordering touches D29's layout rule, D36's layout rewrite and `gitlore_order_merge`'s hoist in `index-composition.md` — three places.

- Whether constrained generation (skill text read before drafting) or unconstrained-then-review produces better memory facts — D47 leaves it open for `just evals`. D48 adds three review-side placements to compare against, and a comparison still has to control for the flows differing in more than directive placement.

- Whether D48's install- and gate-side triggers earn an eval scenario. The bats suites hold that each site names the skill; whether the agent invokes it on being told to is agent behaviour, and grading that needs transcript inspection rather than the black-box repo-state asserts the eval harness uses today.

- Whether a tier merge adopting a *shorter* upstream index line should be allowed to trim the frontmatter description unreviewed. The D17 sync fires at the `PostToolBatch` after the merge commit, so the trim lands outside the merge the sub-agent synthesized and outside FR11's approval of it; that is how an upstream index-tightening pass silently cut three routing clauses out of this repo's ddaanet files. Options: leave it (the index is canonical by design), have the merge report descriptions it is about to shorten, or fold the post-merge sync into the merge commit itself.

## Remaining

- Analyze the fixture-template race in `plans/2026-08-28-brief-fixture-template-copy-race.md` and decide whether to fix the cache, the unchecked `cp -a`, or both.
- Continue the ddaanet review pass from entry 5 of `plans/ddaanet-memory-review.md` (next-largest index lines).
- When the pass reaches the hook memories: 2c finding (2) — `updatedInput` alone defers to the full pipeline, `permissionDecision` settles it — has no owner; my human partner leans toward combining the hook-related facts rather than adding a fourth.
- `docs/design.md` is at exactly the 400-line cap, so the next hub addition needs a split decision rather than another trim.
