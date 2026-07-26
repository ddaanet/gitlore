## Remaining

- Finish the gate rework per the task file: scrub the false phantom-dotfile
  premise everywhere, delete `scripts/run-gate.sh` + `tests/gate_sentinel.bats`
  + `memory/ddaanet/reference_gate_hash_sandbox.md`, inline ghmem's
  `gate-inputs-hash`/`check-sentinel`, and split the inputs into a precommit set
  and a wider evals set.
- Commit the parent and push: memory is at `7044112` with local `live` advanced,
  but the parent has not recorded the gitlink. `just precommit` first.
- Watch `memory/MEMORY.md`'s size — 95% of the 25600-byte budget against a
  24.4KB read limit. Deleting the gate-hash line buys ~450 bytes; a full
  compaction pass needs an adversarial audit, not an opportunistic trim.
- Make the silent-trigger case audible: `memory-commit-batch.sh` exits 0 with no
  message when the trigger is absent under `CLAUDE_PROJECT_DIR`, while the memory
  probe computes the IPC paths from cwd, so a trigger written against a different
  cwd is ignored without a trace. Either emit when a trigger exists in the session
  cwd but not the project root, or resolve both ends the same way.
- Explain the live pointer loss and tag 0.4.2, with `just evals` (`03-add-tier`,
  `04-tier-write`) on the same investigation. The `resolve_compose` red that was
  meant to be the way in does not reproduce — `just precommit` has now gone green
  across six consecutive full runs, so a green suite must not be read as closing
  this.
- Migrate `handoff` onto the `ddaanet` tier (highest distinct yield: ~42 portable
  facts, and it owns the canonical `display-popup` and handoff-file-management
  wording).
- Migrate `micro` (~40 portable) — settle a real memory remote first; it and
  `general` still point at a local `./.git/gitlore-placeholder`.
- Then, in order: `gitmoji` → `general` (placeholder remote too) → `home` →
  `devddaanet` → `skills` → `candidature` → `edify` → `Emploi` → `cwd-safety`.
- Land `onekeys`' parent commit — its mount and 3-fact promotion were dogfooded
  2026-07-24 but the FR11 gate was left open in that repo.
- Harden `judge.sh`'s verdict parse: a delimited `VERDICT:` or a structured enum,
  fail-closed when absent. Fail-closed noise today, so not urgent.
- Consider consolidating the three recall-related memories
  (`feedback_memory_retrieval_in_practice`, `reference_cc_memory_retrieval_agentic`,
  `feedback_recall_checkpoints`) the way the three directive memories were folded
  this session — they overlap but were not examined closely.
