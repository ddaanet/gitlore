## Open decisions

- The `commit` skill for `commit-memory.sh`, per `plans/2026-08-27-brief-commit-memory-missing-skill.md`. Three options: leave it (memory already covers standalone administration); add the standalone-administration sentence to the commit gate's own block message, which reaches an agent exactly when it is stuck and costs no per-session context (recommended); or ship `/gitlore:commit` and revise D16's scoping in `docs/references/commit-gate.md`, accepting that every session learns the standalone path. The brief's own recommendation was the third, and it is refused as written: the gate's trigger is deliberately kept out of general agent-facing instructions, and the proposed body cannot work anyway because that path goes through an intent file and a PostToolBatch hook precisely to sidestep the sandbox and the auto-mode classifier. `commit-gate.md` states that exclusion covers the block message too, so the second option revises a stated exclusion, not just a message.

- The memory index against Claude Code's ~24,985-byte loader cutoff, per `plans/2026-08-27-memory-index-budget-decision.md`. After retiring the three 4c lines the index is 27,025 B; the 4c arithmetic did not close it, as the brief predicted. Three sweeps agree curation cannot close it. Recommended: reorder composition so tier blocks come last, so this repo's own lines and the newest facts stop being the truncated tail, then take `ddaanet` sub-scoping as its own subproject. The third option is to accept the overage and push the cap back upstream. Reordering touches D29's layout rule, D36's layout rewrite and `gitlore_order_merge`'s hoist in `index-composition.md` — three places.

- Whether constrained generation (skill text read before drafting, the precompact placement) or unconstrained-then-review (the handoff placement and the FR11 gate) produces better memory facts — D47 leaves it open for `just evals`; a comparison has to control for the two flows differing in more than directive placement.

## Remaining

- Continue the ddaanet review pass from entry 5 of `plans/ddaanet-memory-review.md` (next-largest index lines).
- When the pass reaches the hook memories: 2c finding (2) — `updatedInput` alone defers to the full pipeline, `permissionDecision` settles it — has no owner; my human partner leans toward combining the hook-related facts rather than adding a fourth.
