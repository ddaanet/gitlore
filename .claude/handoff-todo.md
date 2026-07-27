## Remaining

**The proof pass, items 9-16** — eight local files, in presentation order:

- `reference_submodule_config_visibility.md` — hooks firing inside the submodule
  read its own config; check whether `docs/design.md` owns the mirroring rule.
- `reference_auto_memory_directory.md` — near-certainly category 2: the
  `autoMemoryDirectory` wiring is design, and install plus the session-start hook
  are its implementation.
- `reference_nested_submodule_tier.md` — the largest local index line; several
  distinct claims, so expect a split rather than a single verdict.
- `reference_own_hooks_json_sandbox_erofs.md` — an environment fact about
  gitlore's own tree; it reproduced again this session (a mutation write to
  `hooks/hooks.json` failed EROFS under the sandbox).
- `reference_cc_memory_retrieval_agentic.md`, then
  `feedback_memory_retrieval_in_practice.md`, `feedback_recall_checkpoints.md` —
  all three about recall, and `CLAUDE.md` already carries the checkpoint rule.
  Consider one merged fact, or none.
- `feedback_memory_before_root_commit.md` — lockstep is stated in `CLAUDE.md` and
  in `docs/design.md` NFR 5; expect delete.

Then, cross-cutting: normalize `name:` frontmatter to the filename stem, and
re-audit dangling `[[...]]` links across the whole store.

**Standing work, from before this pass**

- Delete or upstream `scripts/check-version.sh`. `plugin-dev/release.just`
  already bumps, commits and pushes `marketplace.json` and synthesizes a missing
  entry, so a release cannot produce the drift it detects; `version-guard.sh`
  (wired at `.claude/settings.json:9`) blocks the hand-edit path. It guards a
  hole closed at both ends and costs a `just precommit` dependency. Its header
  comment still says "Run via `make check-version`" — stale either way.
- Give compose a way to record which base it merged; dig the vanished-pointer
  drop. A green suite must not be read as closing this.
- Explain the live pointer loss and tag 0.4.2, with `just evals` (`03-add-tier`,
  `04-tier-write`) on the same investigation.
- Migrate `micro` (~40) — settle a real memory remote first; it and `general`
  still point at a local `./.git/gitlore-placeholder`.
- Then: `gitmoji` → `general` → `home` → `devddaanet` → `skills` →
  `candidature` → `edify` → `Emploi` → `cwd-safety`.
- Land `onekeys`' parent commit — mount and 3-fact promotion dogfooded
  2026-07-24, FR11 gate left open in that repo.
- Harden `judge.sh`'s verdict parse: a delimited `VERDICT:` or a structured
  enum, fail-closed when absent. Fail-closed noise today, so not urgent. It has
  no mention in `docs/design.md`; record it there or in a code comment.
- Compact the memory index — 89% of the 25600-byte budget, and the hook nags on
  every index write. Largest: `ddaanet/reference_git_stderr_and_parsing` 456 B,
  `reference_nested_submodule_tier` 451 B,
  `ddaanet/feedback_classifier_denied_self_config` 449 B. Trimming needs an
  adversarial audit of the diff (`feedback_index_compaction_triggers`).

**Handed to David, awaiting his edit (untracked briefs in his repos)**

- `/Users/david/code/skills/docs/plans/2026-07-27-preflight-generic-scope-brief.md`
- `/Users/david/code/gitmoji/docs/2026-07-27-sessionstart-message-brief.md`
