## Current task

Nothing is in flight. The dangling-pointer report — the last thing
presence-authority left open — is built, dogfooded and green (509).

The shape worth carrying: it is a **separate pass**
(`gitlore_compose_dangling`) that both compose triggers call *after*
`gitlore_compose` returns, not a fifth rule inside
`gitlore_compose_check`. The check's contract is "refuse and write
nothing"; compose's return value is the list of what it *wrote*. The
byte-idempotence test's `[ -z "$output" ]` is what proved they are
different channels — folding dangling lines into compose's output breaks
it. Running after also means it speaks when nothing was written, so a
stale line still surfaces on the next index edit. It scans every MOUNTED
carrier as well as the root, because a dormant tier's bullets never reach
the root.

## Open decisions

- **The push backlog.** `main` carries the memory and tier commits that
  one parent push publishes in lockstep via `pre-push`. Not deferred for
  a technical reason — it is outward-facing, so it waits to be asked for.
  Raised five times now; stop raising it unprompted.
- **`/gitlore:resolve` does not compose** — an index merged by the
  resolve continuation composes only on the next batch or session.
- **Index→frontmatter sync has no keyword-density validation.** The index
  line is canonical and overwrites each file's `description:`; both feed
  CC's recall classifier, so a teaser-style line silently degrades
  passive recall.
- **`release` depends on a plugin-defined `prerelease`** — the fix
  belongs in `ddaanet/claude-plugin-dev`, not this repo's vendored copy;
  today releases go `just prerelease release`.
- **`just prerelease` has never run against the three new eval
  scenarios.** They have only ever run at `EVAL_K=1`; the real gate is
  `pass^5`, slow and paid.
