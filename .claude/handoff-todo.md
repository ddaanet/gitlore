## Remaining

- Repoint `.claude/rules/shell.md:26` and `:32` at
  `memory/ddaanet/no-stderr-suppression.md` and
  `memory/ddaanet/git-hook-env-leak.md`. Line 18's target was retired into
  `shared-claude.md`, which states the rule inline directly above the pointer
  — drop that pointer rather than repointing it.
- Decide what `scripts/lib/index-sync.sh:128` should cite, then clear it.
- Wire the checker into `just precommit`, and add `python3 --version` to the
  justfile's `gate-inputs-hash` — it becomes a gate tool.
- Review the 42 deictic and 3 dangling-wikilink warnings. They never block,
  so the value is the report rather than a clean run.
- Fix `/gitlore:push` misreading a *behind* store as diverged, dying at
  `scripts/lib/resolve.sh`. Brief at
  `plans/brief-push-misreads-behind-as-diverged.md`, filed against 0.4.5; the
  file is byte-identical in 0.5.0, so the defect is in the shipped release.
- Run Sweep B: ownership audit over the 99 ddaanet facts, classify only,
  output the verdict table.
- Compact `memory/MEMORY.md` — strategy waits on Sweep B.
- Class A prose deletions from `shared-claude.md` and `CLAUDE.md`: the
  memory-commit rule stated three times, the `.gitignore` line, the
  conventional-commit prefixes. Blocked until the `prohibitions@ddaanet`
  hooks exist and are verified.
- Add a gitlore SessionStart pairing check: warn when the ddaanet tier is
  mounted but `prohibitions@ddaanet` is absent from `enabledPlugins`.
- Apply the briefs under `plans/`: hook-exec-and-compose-revert,
  memory-index-glued-bullets, merge-dispatch-authorization,
  handoff-integration-evals. Also the two unfiled at the repo root:
  `brief-plugin-dev-0.5.2.md` and
  `brief-stale-plugin-root-detector-confirmed.md`.
- Propose the memory-submodule carve-out to `ddaa:preflight`'s clean-tree and
  submodule checks — another repo, proposal only.
- Propose the plan-escalation rule as a patch to
  `superpowers:executing-plans`, likewise read-only.
- Migrate the `micro` tier (~40 facts) once a real memory remote is settled;
  it and `general` still point at `./.git/gitlore-placeholder`. Then
  `gitmoji` -> `general` -> `home` -> `devddaanet` -> `skills` ->
  `candidature` -> `edify` -> `Emploi` -> `cwd-safety`.