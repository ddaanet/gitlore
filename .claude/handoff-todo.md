## Remaining

- Memory proof pass, items 9-16, in presentation order:
  `reference_submodule_config_visibility` (does `docs/design.md` own the
  mirroring rule?), `reference_auto_memory_directory` (near-certainly a
  delete — the wiring is design, install plus the session-start hook its
  implementation), `reference_nested_submodule_tier` (several distinct
  claims; expect a split, not one verdict),
  `reference_own_hooks_json_sandbox_erofs` (reproduced again),
  `reference_cc_memory_retrieval_agentic` +
  `feedback_memory_retrieval_in_practice` + `feedback_recall_checkpoints`
  (all three about recall, and `CLAUDE.md` already carries the checkpoint
  rule — consider one merged fact, or none), `feedback_memory_before_root_commit`
  (lockstep is in `CLAUDE.md` and design NFR 5; expect delete).
- Cross-cutting after the proof pass: normalize `name:` frontmatter to the
  filename stem, re-audit dangling `[[...]]` links across the whole store.
- Make the test suite faster. Precommit's body is ~600 s over 605 cases, and
  the input-hash sentinel lands that cost exactly when a change is in flight
  (`docs/design.md` NFR 10). `bats -T` gives the per-test breakdown free on
  the next full run.
- Explain the live pointer loss and tag 0.4.2, with `just evals`
  (`03-add-tier`, `04-tier-write`) on the same investigation.
- Migrate `micro` (~40 facts) — settle a real memory remote first; it and
  `general` still point at a local `./.git/gitlore-placeholder`. Then
  `gitmoji` → `general` → `home` → `devddaanet` → `skills` → `candidature` →
  `edify` → `Emploi` → `cwd-safety`.
- Harden `judge.sh`'s verdict parse: a delimited `VERDICT:` or a structured
  enum, fail-closed when absent. Fail-closed noise today, so not urgent. It
  has no mention in `docs/design.md`; record it there or in a code comment.
- Compact the memory index — 89% of the 25600-byte budget, and the hook nags
  on every index write. Largest: `ddaanet/reference_git_stderr_and_parsing`
  456 B, `reference_nested_submodule_tier` 451 B,
  `ddaanet/feedback_classifier_denied_self_config` 449 B. Trimming needs an
  adversarial audit of the diff (`feedback_index_compaction_triggers`).
