## Remaining

- Run Sweep A per `plans/memory-hygiene-sweep.md`: build the checker, clear the violations it finds, then wire it into `just precommit`. Confirm it flags the three pre-rename `memory/feedback_*.md` paths cited in `.claude/rules/shell.md`.
- Run Sweep B: ownership audit over the 99 ddaanet facts, classify only, output the verdict table — root `memory/MEMORY.md` has only ~503B of headroom left before Claude Code's 24.4KB loader cutoff, so the retirement call this sweep feeds is close to forced by the next memory write.
- Compact `memory/MEMORY.md` — strategy waits on Sweep B.
- Class A prose deletions from `shared-claude.md` and `CLAUDE.md`: the memory-commit rule stated three times, the `.gitignore` line, the conventional-commit prefixes. Blocked until the `prohibitions@ddaanet` hooks exist and are verified.
- gitlore SessionStart pairing check: warn when the ddaanet tier is mounted but `prohibitions@ddaanet` is absent from `enabledPlugins`.
- Apply the briefs under `plans/`: hook-exec-and-compose-revert, memory-index-glued-bullets, merge-dispatch-authorization, handoff-integration-evals. The memory-name-drift brief is subsumed by Sweep A.
- Propose the memory-submodule carve-out to `ddaa:preflight`'s clean-tree and submodule checks — another repo, proposal only.
- Propose the plan-escalation rule as a patch to `superpowers:executing-plans`, likewise read-only.
- Migrate the `micro` tier (~40 facts) once a real memory remote is settled; it and `general` still point at a local `./.git/gitlore-placeholder`. Then `gitmoji` → `general` → `home` → `devddaanet` → `skills` → `candidature` → `edify` → `Emploi` → `cwd-safety`.