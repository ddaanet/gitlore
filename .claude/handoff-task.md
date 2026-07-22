## Current task

D17 slice 3-ii (tier index composition) is built and dogfooded — `index-compose.sh`
library + PostToolBatch hook + SessionStart pass, splice-up of active tiers and
mirror-down into every mounted tier, four fail-safe validations, byte-idempotent.
Next slice is **3-iii `/gitlore:add-tier`** (mount an existing tier + `--create` a
new one, both ending by editing `memory/.gitlore-tiers`, which triggers the
recompose built in 3-ii). After 3-iii: **happy-path evals for the finished tier
flow** (the standing instruction to write them once nested memory is done).

The 3-ii composition hook does not self-fire in the session that wrote it — CC
freezes hook event-registration at session start — so a fresh session is what
first exercises the PostToolBatch trigger end-to-end; worth watching on the next
memory edit.

## Open decisions

- **Root `MEMORY.md` is ~19.7KB, nearing the 24.4KB always-loaded read limit.**
  A hook now warns on every edit. Compacting means one line per entry, detail
  pushed into topic files, stale entries merged or dropped — a semantic curation
  pass over ~65 pointers, not a mechanical one. Decide whether to do it as its
  own focused session before it forces itself.
- **Presence-authority: is the file set or the index authoritative over a pointer
  line's presence?** Still gates coverage/prune/dedup. 3-ii was built not to
  prejudge it (mirror-down unconditional). Needs log evidence of how presence
  actually drifts.
- **Tier divergence is detected but not resolvable** — the resolve continuation
  derives its store from `gitlore_memory_path` and cannot target a tier; the state
  file would need to carry the store path.
- **`/gitlore:resolve` does not compose** — an index merged by the resolve
  continuation composes only on the next batch or session.
- **`release` depending on a plugin-defined `prerelease`** — the fix belongs in
  `ddaanet/claude-plugin-dev`, not this repo's vendored copy; today releases go
  `just prerelease release`.
