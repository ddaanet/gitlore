# Split: tests/cc_hook_index_compose.bats

## Final partition

### `tests/cc_hook_index_compose.bats` — 192 lines, 12 tests
Kept as the "one cohesive group": hook registration and the base
trigger-protocol filter (baseline stamping, no-op paths, the
additionalContext/empty-context-half producer contract, the unparseable-jq
fallback, the Bash-applied edit, manifest-touching recompose, already-composed
silence). Local helper `shim_plugin_root` (single-file user) stays above its
first caller, unchanged from the original.

- the hook is executable and registered on PostToolBatch
- no-op for a batch that touched neither the index nor the manifest
- no-op for a batch that left no baseline behind
- no-op when a watched call named the index but moved nothing
- an index-touching batch composes and reports on both channels
- index-compose.sh omits additionalContext when the context half is empty
- relay-drain.sh omits additionalContext when the context half is empty
- both hooks carry additionalContext when the context half is not empty
- an unparseable payload still composes on the unkeyed baseline (fallback proof)
- a Bash-applied index edit composes, though it named no file
- a manifest-touching batch recomposes
- an already-composed store reports nothing

### `tests/cc_hook_index_compose_relay.bats` — 354 lines, 12 tests
Per-agent baselines, concurrency, and relay-write failure handling.

- a main-thread compose baseline survives a subagent's compose hook
- a subagent's compose consumes its own baseline, not the main thread's
- a keyed compose run writes a marker and still emits its own json
- an unkeyed compose run leaves a marker in place
- concurrency: both reporting hooks reach relay-drain.sh exactly once per keyed batch
- relay-drain.sh delivers with no baseline (M2); a keyed run exits 0 silently and leaves the files
- relay-drain.sh with session S1 leaves an S2 file standing
- a failed relay write leaves the subagent's own report intact
- a failed relay write tells the subagent it was not staged
- a validation failure reports on both channels and exits 0
- a dangling pointer is reported even when nothing was composed
- a dangling report never rewrites or deletes anything

### `tests/cc_hook_index_compose_notices.bats` — 135 lines, 8 tests
The post-mount triage nudge and the no-root-index notice.

- an index-only batch composes but emits no triage directive
- a manifest-touching batch emits a triage directive naming the active tier's scope
- no triage directive when the manifest changes to zero active tiers
- a store with no root index says composition and the index checks are off
- the no-root-index notice fires once per session
- a compaction re-arms the no-root-index notice
- a subagent's no-root-index notice is staged for the parent
- no-op outside a gitlore repo

### `tests/helpers/cc-hook-index-compose.bash` — 97 lines
New helper, one function per line below (bodies are the original's, moved
verbatim except where noted in Deviations):
- `HOOK`/`PRE`/`POST`/`DRAIN` file-level path variables (depend on `$PLUGIN_ROOT`, set by `helpers/setup`)
- `setup()` — `setup_tmp_repo`; export `CLAUDE_PLUGIN_ROOT`; `make_parent_with_memory`; `make_tier_in_memory ddaanet`; `set_tier_manifest ddaanet`
- `teardown()` — `teardown_tmp_repo`
- `pre()` — drives index-sync-pre.sh with an Edit or Bash payload, optional agent id
- `feed()` — drives index-compose.sh, optional agent id
- `sync_feed()` — drives index-sync-post.sh, optional agent id
- `drain_feed()` — drives relay-drain.sh, optional agent id and session id
- `seed_root_fact()` — seeds a root index bullet plus the file it names

All four hook-driver functions and `seed_root_fact` are called from more than
one resulting file, so they moved to the helper per the rule; `shim_plugin_root`
is used only within `cc_hook_index_compose.bats` and stayed there.

## Deviations from the proposed partition

None to the cut points — the proposed line ranges (101–288, 289–616, 617–738)
matched section/test boundaries exactly and produced files at 192/354/135
lines, all under 380, so no further cut was needed.

Two content deviations, both required by the split rather than optional:
- The original file-header comment ("...at the three bare `feed >/dev/null`
  sites...") named an exact count specific to the single original file. Each
  split file now has its own count (1, 2, and 1 respectively), so each file's
  header comment says "at the bare ... sites" instead of naming a number.
- The helper's copies of the `feed`/`sync_feed` doc comments dropped the
  phrases "in this file" / "per the file header" that made sense only when
  `pre`/`feed`/`sync_feed`/`drain_feed` and their explanatory header lived
  together in one file. The `main-thread compose baseline` test's comment in
  `cc_hook_index_compose_relay.bats` still says "per the file header" — that
  now refers to `tests/helpers/cc-hook-index-compose.bash`'s header, which
  carries the agent_type-decoy explanation the original file's header gave.

## References updated

- `scripts/cc-hooks/index-compose.sh:35` — "the agent_type decoy every payload
  in tests/cc_hook_index_compose.bats carries" now names
  `tests/helpers/cc-hook-index-compose.bash`, where `pre()`/`feed()` (the
  payload builders) now live.
- `tests/helpers/triggers.bash:23` — pinned the "a manifest-touching batch
  emits a triage directive naming the active tier's scope" test, which moved
  to `tests/cc_hook_index_compose_notices.bats`; updated the file name.

No hits in `docs/design.md`, `docs/decisions.md`, `docs/references`, the
`justfile`, `scripts/run-bats.sh`, `tests/justfile_gates.bats`,
`tests/plugin_distribution.bats`, or `docs/references/testing.md` — none of
them enumerate this suite by name. `plans/` hits (many, all historical run
reports/specs) are out of scope per the brief and left untouched.

## Verification

1. Test names preserved:
   ```
   $ diff <(grep '^@test' "$TMPDIR/cc_hook_index_compose.orig.bats" | sort) \
          <(cat tests/cc_hook_index_compose.bats tests/cc_hook_index_compose_relay.bats tests/cc_hook_index_compose_notices.bats | grep -h '^@test' | sort)
   (no output)
   ```
2. No line lost (only the deliberate rewording noted above survives the filter):
   ```
   $ diff <(sort "$TMPDIR/cc_hook_index_compose.orig.bats") \
          <(cat tests/cc_hook_index_compose.bats tests/cc_hook_index_compose_relay.bats tests/cc_hook_index_compose_notices.bats tests/helpers/cc-hook-index-compose.bash | sort) | grep '^<'
   < # batch.
   < # call), which is what SC2119/SC2120 flag as suspicious at the three bare
   < # carrying the session is enough. The concurrency case is the one in this
   < # file that needs the sync hook, alongside the compose hook, in the same
   ```
   All four lines are the wrapped remnants of the two deliberate comment edits
   described above (the "three bare" count and the "in this file" phrasing).
3. `wc -l` of every resulting file:
   ```
   $ wc -l tests/cc_hook_index_compose.bats tests/cc_hook_index_compose_relay.bats tests/cc_hook_index_compose_notices.bats tests/helpers/cc-hook-index-compose.bash
     192 tests/cc_hook_index_compose.bats
     354 tests/cc_hook_index_compose_relay.bats
     135 tests/cc_hook_index_compose_notices.bats
      97 tests/helpers/cc-hook-index-compose.bash
   ```
4. `scripts/run-bats.sh` pass count equals the original's `@test` count (32):
   ```
   $ scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_index_compose_relay.bats tests/cc_hook_index_compose_notices.bats
   bats: 32 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.5YEIPL
   ```
5. `just lint` — run once at the end of both suite splits (see report 10).
6. `just test-unit` not run, per brief step 6 — the main session runs it.
