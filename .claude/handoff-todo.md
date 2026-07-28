## Remaining

- Cross-cutting memory cleanup: normalize `name:` frontmatter to the
  filename stem across the whole store (confirmed drift example:
  `memory/reference_nested_submodule_tier.md`'s `name:` was
  `nested-submodule-tier-mechanics` before that file was deleted last
  session — the pattern likely recurs elsewhere), and re-audit dangling
  `[[...]]` links store-wide.
- Compact the `MEMORY.md` index. At ~21KB / 83%+ of the 25600-byte
  budget, harness-flagged repeatedly as approaching the read-truncation
  limit. Needs an adversarial audit of the diff per
  `feedback_index_compaction_triggers` — don't trim solo.
- Make the test suite faster. Precommit's body is ~600s over 605+ cases
  (confirmed again this session — a 10-minute Bash timeout killed a
  `just release` run mid-precommit). `bats -T` gives the per-test
  breakdown free on the next full run.
- Explain the live pointer loss for gitlore's own memory store — the
  0.4.2 plugin tag itself is done, but the pointer-loss investigation
  behind that todo item is not.
- Migrate `micro` (~40 facts) — settle a real memory remote first; it and
  `general` still point at a local `./.git/gitlore-placeholder`. Then
  `gitmoji` → `general` → `home` → `devddaanet` → `skills` → `candidature`
  → `edify` → `Emploi` → `cwd-safety`.
