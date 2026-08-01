## Remaining

- Add guardrails against snake_case and `name:`/filename drift, then normalise
  every memory `name:` and cross-link to kebab-case, per
  `brief-memory-name-drift.md`. The link parser must skip fenced code, or it
  will rewrite bash `[[ "$output" == ... ]]` conditionals; roughly two dozen
  links dangle, split between dropped type prefixes and cross-store targets that
  may legitimately live in another repo.
- Retire superseded memory facts to buy index headroom. `memory/MEMORY.md` is at
  ~24.1KB against the 24.4KB loader cutoff, past which the tail is silently
  truncated; merging is exhausted as a lever.
- Bump the plugin version and release, so the D21 detector reaches other repos.
- Explain the live pointer loss for gitlore's own memory store.
- Apply the three remaining root briefs that have no line of their own here:
  `brief-hook-exec-and-compose-revert.md`, `brief-memory-index-glued-bullets.md`
  and `brief-merge-dispatch-authorization.md`.
- Migrate the `micro` tier (~40 facts) once a real memory remote is settled; it
  and `general` still point at a local `./.git/gitlore-placeholder`. Then
  `gitmoji` → `general` → `home` → `devddaanet` → `skills` → `candidature` →
  `edify` → `Emploi` → `cwd-safety`.