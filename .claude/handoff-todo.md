## Remaining

- Bump the plugin version and release. Until then a session elsewhere that
  invokes recall gets the old body, instructing it to write an IPC file whose
  hook no longer exists — and the D21 detector still does not reach other repos.
- Compact `memory/MEMORY.md`: 22KB against Claude Code's 24.4KB loader cutoff,
  so the tail is one growth spurt away from silently not loading.
- Add guardrails against snake_case and `name:`/filename drift, plus the six
  dangling wikilinks — `ghmem-project`, `micro-colwrap-project`,
  `auto-memory-directory`, `worktree-handoff-root`, `links`, `some-project` —
  some of which may legitimately target another store.
- Explain the live pointer loss for gitlore's own memory store.
- Apply the root-inbox briefs: `brief-hook-exec-and-compose-revert.md`,
  `brief-memory-index-glued-bullets.md`, `brief-merge-dispatch-authorization.md`,
  `brief-memory-name-drift.md`, `brief-handoff-integration-evals.md`.
- Propose the plan-escalation rule as a patch to `superpowers:executing-plans`,
  which is another repo and stays read-only.
- Migrate the `micro` tier (~40 facts) once a real memory remote is settled; it
  and `general` still point at a local `./.git/gitlore-placeholder`. Then
  `gitmoji` → `general` → `home` → `devddaanet` → `skills` → `candidature` →
  `edify` → `Emploi` → `cwd-safety`.