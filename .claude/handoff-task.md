## Current task

Nothing is in flight. Three open decisions were taken up and closed this
session: presence-authority, the recall refusal text, and tier divergence
resolution. All three are built, tested (500 green) and recorded in
`docs/design.md` and the project memory.

The load-bearing correction, worth carrying: **tier divergence was never a
missing mechanism, only a missing line.** The whole merge path was already
parameterized by store, and `gitlore_merge_state_file` resolves `--git-path`
inside whichever store it is handed — so each tier already had its own state
file in its own gitdir. Only `load_continuation_state` derived its store from
`gitlore_memory_path`. Reaching that took three rounds of over-complicated
answers about trigger placement (SessionStart vs UserPromptSubmit vs
PreToolUse) before David's framing landed it: one branch policy, two gates, and
nesting changes nothing.

## Open decisions

- **The 32-commit push backlog.** `main` is 32 commits ahead of `origin/main`
  (at `4d54f52`), carrying 21 memory and 4 tier commits; one parent push
  publishes all three in lockstep via `pre-push`. Not deferred for a technical
  reason — it is outward-facing, so it waits to be asked for. Raised four times
  now; stop raising it unprompted.
- **The dangling-pointer report, unbuilt.** Presence-authority (index
  authoritative, non-destructive) closed coverage/prune/dedup for good, but left
  room for a fifth compose validation naming a bullet whose target file is
  absent. It should *report*, not refuse like the other four: a dangling line
  does not make the composed output wrong, and refusing would block every later
  write over a stale line the agent can fix in one edit.
- **`/gitlore:resolve` does not compose** — an index merged by the resolve
  continuation composes only on the next batch or session.
- **Index→frontmatter sync has no keyword-density validation.** The index line
  is canonical and overwrites each file's `description:`; both feed CC's recall
  classifier, so a teaser-style line silently degrades passive recall.
- **`release` depends on a plugin-defined `prerelease`** — the fix belongs in
  `ddaanet/claude-plugin-dev`, not this repo's vendored copy; today releases go
  `just prerelease release`.
- **`just prerelease` has never run against the three new eval scenarios.**
  They have only ever run at `EVAL_K=1`; the real gate is `pass^5`, slow and
  paid.
