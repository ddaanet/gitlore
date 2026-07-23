## Current task

Nothing is in flight. The merge continuation now composes — the last
uncomposed write path into a memory store — built, green (513) and
documented.

The shape worth carrying: composition is anchored at the memory **root**,
kept apart from the `store` the merge-state file names, because it spans
the whole tree while a merge sits in exactly one store. So it can write a
store *other* than the one being committed (the root index when a tier
merged, a carrier when memory did); those writes stay dirty and ride the
next FR11 commit, the same float SessionStart's recompose produces. And a
refusal reports without blocking: compose writes nothing when it refuses,
and by then the merge is synthesized and approved, so stranding it
half-landed over a duplicate pointer line the agent fixes in one edit is
the worse outcome. Staging is `git add -A` in the merge store — the call
the merger sub-agent already makes.

## Open decisions

- **The push backlog.** `main` carries the memory and tier commits that
  one parent push publishes in lockstep via `pre-push`. Not deferred for
  a technical reason — it is outward-facing, so it waits to be asked for.
  Raised repeatedly; stop raising it unprompted.
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
