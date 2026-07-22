## Current task

Active recall (FR16/D18) is built and green — `skills/recall/SKILL.md`,
`scripts/lib/recall.sh`, `recall-batch.sh` on PostToolBatch, `recall-reset.sh` on
SessionStart+PreCompact, 28 new cases, 410 total green. It has **not been
dogfooded**: CC freezes hook event registration at session start, and `PreCompact`
is a newly registered event, so the first real exercise is a fresh session — write
a `.claude/gitlore-recall` there and confirm the bodies actually arrive as
`additionalContext`.

Also landed this session: always-on directives moved from `memory/MEMORY.md` into
`CLAUDE.md` and a new path-scoped `.claude/rules/shell.md`; index trimmed to
keyword-dense routing lines (20,381 → 18,676 bytes).

Next planned slice remains **D17 3-iii `/gitlore:add-tier`** (mount an existing
tier + `--create`, both ending by editing `memory/.gitlore-tiers`), then
happy-path evals for the finished tier flow — which should now also cover the
recall round trip.

## Open decisions

- **Root `MEMORY.md` is still 18.7KB against a 24.4KB limit, and the trim barely
  moved it.** Measured: one project-state line is 3,288 bytes (18% of the index),
  the top five lines are 31%, and every behavioral directive line combined was a
  small fraction. The remaining curation is on the long state and reference lines,
  which is semantic work — decide whether to do it as its own focused session.
- **Does the index→frontmatter sync need a keyword-density validation?** The sync
  makes the index line canonical and overwrites each file's `description:`. Both
  feed CC's recall classifier, so a teaser-style index line ("the opt-out, and how
  to ask instead") silently degrades passive recall. Hit this live and rewrote 20
  lines keyword-dense. Nothing currently detects it — candidate fifth compose
  validation.
- **Presence-authority: is the file set or the index authoritative over a pointer
  line's presence?** Still gates coverage/prune/dedup. The recall ledger now
  produces the usage evidence that question was waiting on.
- **Tier divergence is detected but not resolvable** — the resolve continuation
  derives its store from `gitlore_memory_path` and cannot target a tier; the state
  file would need to carry the store path.
- **`/gitlore:resolve` does not compose** — an index merged by the resolve
  continuation composes only on the next batch or session.
- **`release` depending on a plugin-defined `prerelease`** — the fix belongs in
  `ddaanet/claude-plugin-dev`, not this repo's vendored copy; today releases go
  `just prerelease release`.
