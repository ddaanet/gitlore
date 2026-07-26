## Remaining

- Make the silent-trigger case audible: `memory-commit-batch.sh` exits 0 with no
  message when the trigger is absent under `CLAUDE_PROJECT_DIR`, while the memory
  probe computes the IPC paths from cwd, so a trigger written against a different
  cwd is ignored without a trace. Either emit when a trigger exists in the session
  cwd but not the project root, or resolve both ends the same way.
- Explain the live pointer loss and tag 0.4.2, with `just evals` (`03-add-tier`,
  `04-tier-write`) on the same investigation. The `resolve_compose` red that was
  meant to be the way in no longer reproduces — see `handoff-task.md`.
- Compact `memory/MEMORY.md` — 24.9KB against CC's 24.4KB read limit, so the tail
  is already being dropped at load. Target under 17.1KB. Trim the longest hooks —
  `project_gitlore_global_memory` (822 B),
  `ddaanet/feedback_posttooluse_print_mode` (623 B),
  `reference_nested_submodule_tier` (540 B) — without gutting what makes a line
  match; move detail into the file bodies. Reconcile the 21 pointers naming absent
  files in the same pass.
- Migrate `handoff` onto the `ddaanet` tier (highest distinct yield: ~42 portable
  facts, and it owns the canonical `display-popup` and handoff-file-management
  wording).
- Migrate `micro` (~40 portable) — settle a real memory remote first.
- Then, in order: `gitmoji` → `general` (placeholder remote too) → `home` →
  `devddaanet` → `skills` → `candidature` → `edify` → `Emploi` → `cwd-safety`.
- Land `onekeys`' parent commit — its mount and 3-fact promotion were dogfooded
  2026-07-24 but the FR11 gate was left open in that repo.
- Harden `judge.sh`'s verdict parse: a delimited `VERDICT:` or a structured enum,
  fail-closed when absent. Fail-closed noise today, so not urgent.
