## Remaining

- Rewrite gitlore's bats negatives per `brief-test-suite-negatives-rewrite.md`,
  and report where the paired-structure rule does not hold. The D21 suite is the
  first dogfooding: the rule caught a real vacuous negative, but only under
  mutation — the prose pairing claim did not.
- Add guardrails against snake_case and `name:`/filename drift, then normalise
  every memory `name:` and cross-link to kebab-case. The link parser must skip
  fenced code, or it will rewrite bash `[[ "$output" == ... ]]` conditionals;
  roughly two dozen links dangle, split between dropped type prefixes and
  cross-store targets that may legitimately live in another repo.
- Retire superseded memory facts to buy index headroom. `memory/MEMORY.md` is at
  ~24.1KB against the 24.4KB loader cutoff, past which the tail is silently
  truncated; merging is exhausted as a lever.
- Bump the plugin version and release, so the D21 detector reaches other repos.
- Explain the live pointer loss for gitlore's own memory store.
- Apply the five remaining root `brief-*.md` files — they were dropped here by
  sibling projects for handling in this repo.
- Migrate the `micro` tier (~40 facts) once a real memory remote is settled; it
  and `general` still point at a local `./.git/gitlore-placeholder`. Then
  `gitmoji` → `general` → `home` → `devddaanet` → `skills` → `candidature` →
  `edify` → `Emploi` → `cwd-safety`.