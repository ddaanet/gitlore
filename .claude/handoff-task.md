# Task — 2026-07-22 14:04:36 +0200

## Current task

**Next slice: D17 3-iii `/gitlore:add-tier`** — mount an existing tier plus
`--create`, both ending by editing `memory/.gitlore-tiers` (which now triggers the
live 3-ii recompose). Then happy-path evals for the finished tier flow, which
should also cover the recall round trip.

Nothing is in flight. Tree was clean at `263922f` when this session started; the
only working-tree changes are the two memory edits described below.

### Done this session

**Active recall (FR16/D18) dogfooded live and green.** This was the outstanding
verification from the previous session — CC freezes hook event registration at
session start, so a fresh session was required. Four paths confirmed against the
real store:

- mid-batch trigger → bodies arrive inline as `additionalContext`
- one-shot consumption — the request file is removed whether served or refused
- ledger dedup — a re-request named the two already-read entries as skipped and
  fetched only the third
- refusal — named the unresolved path, read nothing, consumed the request

Mechanism: agent writes `.claude/gitlore-recall` (gitignored, one memory-relative
path per line, or the literal `no match`); `scripts/cc-hooks/recall-batch.sh` on
PostToolBatch reads the bodies and injects them. The ledger lives in the memory
gitdir keyed by session, records `<hash> <relpath>` so an edited memory re-fetches,
and is fed from `.tool_calls[]` Reads so it also catches CC's own native recall.

**Still unverified:** the `PreCompact` reset. It is a newly registered event that
cannot be triggered on demand — the compaction this handoff arms is the first real
exercise of it. After compacting, a fresh recall request for a body that was in
context *before* the compaction should re-fetch it (not report it as already
present); if it reports "already in this context", the reset did not fire.

Native recall landing in the ledger also went unexercised — no "Recalled N
memories" fired this session.

### Uncommitted memory edits

Two edits, both recording the above; the index→frontmatter sync already
propagated the changed hook. They ride the next parent commit.

- `memory/project_gitlore_global_memory.md` — new ACTIVE RECALL paragraph
- `memory/MEMORY.md` — its index line retitled: 3-ii now `DONE`, recall added,
  `Seq:` updated to `3-iii /add-tier → happy-path evals`

## Open decisions

- **Index→frontmatter sync has no keyword-density validation.** The sync makes the
  index line canonical and overwrites each file's `description:`, and both feed
  CC's recall classifier — so a teaser-style line ("the opt-out, and how to ask
  instead") silently degrades passive recall. Hit live last session, 20 lines
  rewritten by hand. Candidate fifth compose validation.
- **Root `MEMORY.md` ~18.7KB against a 24.4KB limit.** The trim barely moved it:
  one project-state line is ~3.3KB (18% of the index), top five are 31%. What
  remains is semantic curation of long state/reference lines — probably its own
  focused session.
- **Presence-authority — file set or index authoritative over a pointer line's
  presence?** Still gates coverage/prune/dedup. The recall ledger now produces the
  usage evidence that question was waiting on.
- **Tier divergence is detected but not resolvable** — the resolve continuation
  derives its store from `gitlore_memory_path` and cannot target a tier; the state
  file would need to carry the store path.
- **`/gitlore:resolve` does not compose** — an index merged by the resolve
  continuation composes only on the next batch or session.
- **`release` depends on a plugin-defined `prerelease`** — the fix belongs in
  `ddaanet/claude-plugin-dev`, not this repo's vendored copy; today releases go
  `just prerelease release`.

## Deferred nit

The live refusal text reads "REFUSED — nothing was read. the request names entries
that do not resolve. Nothing was read." — the phrase twice, plus a lowercase
sentence start. Left alone because the exact string is likely asserted in the bats
suite; fix message and tests together when touching `recall-batch.sh`.
