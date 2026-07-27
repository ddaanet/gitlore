## Current task

Completed the memory proof pass, items 9-16 (using `ddaa:proof`): deleted 5
facts now redundant with `docs/design.md`/`CLAUDE.md` (submodule config
mirroring, stale `autoMemoryDirectory` mechanism, nested-tier gitdir
mechanics, recall checkpoints, lockstep-before-commit); moved the CC
recall-classifier research to `docs/references/cc-memory-retrieval.md`;
merged the `hooks.json` sandbox EROFS gotcha and the index byte-budget
corollary into existing `ddaanet` topic files (`reference_sandbox_effects.md`,
`feedback_index_compaction_triggers.md`); repointed every `[[...]]` link left
dangling by the deletions; added `ddaanet/feedback_tier_routing_plugin_shaped.md`
from a mid-pass correction (route an operational gotcha to the ddaanet tier
when its mechanism depends on the repo being plugin-shaped, not on this
repo's own content). Also fixed a stale "apply bottom-to-top" instruction in
the `ddaa:proof` skill itself (source: `/Users/david/code/skills/plugins/ddaa/skills/proof/`)
— uncommitted edits in that separate repo, not gitlore's.

Memory committed (gitlore memory HEAD `a927655`, "Memory proof pass on
gitlore's own store (items 9-16)...").

## Open decisions

- Push gitlore's `main` to `origin`, or hold — several commits ahead of
  `origin/main`, most pre-existing from before this session.
- `MEMORY.md` is 20.8KB (83% of the 25600-byte budget) even after this
  pass's net -6 lines; the harness has twice flagged it as "approaching
  the read limit, compact to 17.1KB now." Deliberately deferred rather
  than rushed — full compaction is flagged (by `feedback_index_compaction_triggers`)
  as needing an adversarial audit of the diff, which this turn didn't do.
