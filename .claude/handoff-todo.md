## Remaining

- Get `just precommit` green again: `tests/resolve_compose.bats` test 1 fails
  only in the full unit run, dropping a tier line from a composed root index —
  the same symptom as the live loss. Bisect the leaking predecessor first.
- Then explain the live pointer loss and tag 0.4.2. `just evals` (`03-add-tier`,
  `04-tier-write`) is owed on the same investigation, since the loss sits in the
  agent/shell seam bats cannot see.
- Compact `memory/MEMORY.md` from 23.4KB to under 17.1KB. It is under CC's hard
  25000-byte read limit again, but only just, and every index edit re-approaches
  it. Trim the longest hooks — `project_gitlore_global_memory` (822 B),
  `ddaanet/feedback_posttooluse_print_mode` (623 B),
  `reference_nested_submodule_tier` (540 B) — without gutting what makes a line
  match; move detail into the file bodies.
- Migrate `handoff` onto the `ddaanet` tier (highest distinct yield: ~42
  portable facts, and it owns the canonical `display-popup` and
  handoff-file-management wording).
- Migrate `micro` (~40 portable) — settle a real memory remote first.
- Then, in order: `gitmoji` → `general` (placeholder remote too) → `home` →
  `devddaanet` → `skills` → `candidature` → `edify` → `Emploi` →
  `cwd-safety`.
- Land `onekeys`' parent commit — its mount and 3-fact promotion were
  dogfooded 2026-07-24 but the FR11 gate was left open in that repo.
- Harden `judge.sh`'s verdict parse: a delimited `VERDICT:` or a structured
  enum, fail-closed when absent. Fail-closed noise today, so not urgent.
