## Remaining

- Cross-cutting memory cleanup: normalize `name:` frontmatter to the
  filename stem across the whole store (confirmed drift example:
  `memory/reference_nested_submodule_tier.md`'s `name:` was
  `nested-submodule-tier-mechanics` before that file was deleted this
  session — the pattern likely recurs elsewhere), and re-audit dangling
  `[[...]]` links store-wide (beyond the ones this session's deletions
  caused, which are already fixed).
- Compact the `MEMORY.md` index. At 20.8KB / 83% of the 25600-byte budget,
  harness-flagged twice as approaching the read-truncation limit. Needs
  an adversarial audit of the diff per `feedback_index_compaction_triggers`
  — don't trim solo.
- Make the test suite faster. Precommit's body is ~600s over 605 cases,
  and the input-hash sentinel lands that cost exactly when a change is in
  flight (`docs/design.md` NFR 10). `bats -T` gives the per-test breakdown
  free on the next full run.
- Explain the live pointer loss and tag gitlore's own 0.4.2. The eval half
  of this (`just evals` on `03-add-tier`, `04-tier-write`) is done — both
  passed at EVAL_K=1 against the new judge.sh; the pointer investigation
  and the tag are not.
- Migrate `micro` (~40 facts) — settle a real memory remote first; it and
  `general` still point at a local `./.git/gitlore-placeholder`. Then
  `gitmoji` → `general` → `home` → `devddaanet` → `skills` → `candidature`
  → `edify` → `Emploi` → `cwd-safety`.
