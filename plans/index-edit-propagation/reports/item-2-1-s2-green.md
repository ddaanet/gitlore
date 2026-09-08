# Item 2.1 slice 2 — GREEN

## Implementation

`scripts/cc-hooks/index-sync-pre.sh` already held the full hook payload in
`$payload` (line 18). Added one line reading the agent id from it:

```sh
agent_id=$(jq -r '.agent_id // empty' <<<"$payload")
```

**No fallback.** The test review's mutation matrix
(`item-2-1-s2-test-review.md`) proves both `(.agent_id // .agent_type)` and
`(.agent_type // .agent_id)` are rejected by the slice's cases — `agent_type`
also appears on the main thread of an `--agent` session
(`memory/ddaanet/hook-input-schema.md`), so falling back to it would key the
parent's own batch as if it were a subagent's, the opposite of FR-C. Absent
`agent_id` yields empty via `// empty`, and empty reproduces today's
unsuffixed bare-path behaviour through `_gitlore_agent_suffix`'s existing
empty-string short circuit.

`$agent_id` is now passed as the second argument to both
`gitlore_index_preimage_file "$mempath" "$agent_id"` and
`gitlore_compose_stamp_file "$mempath" "$agent_id"` — no other call site in
the file changed.

## Comment rewrite

`index-sync-pre.sh:43-47`'s "First index-touching call..." comment asserted
"an existing one here always belongs to the batch in flight," which this
change falsifies (a parent batch ending mid-subagent used to consume the
subagent's baseline; that's the desync the item text names). Rewrote it to
state the new invariant: the baselines are keyed per agent, so an existing
file belongs to the batch in flight *of this agent*, and a parent batch
ending mid-subagent no longer collides with it.

## Test results

Targeted run:

```
$ bats -f "stamps the keyed path|stamps the bare path|cannot leave the gitdir" tests/index_sync.bats
1..3
ok 1 pre: a payload carrying agent_id stamps the keyed path, not the bare one
ok 2 pre: a payload with no agent_id stamps the bare path
ok 3 an agent id outside [A-Za-z0-9-] cannot leave the gitdir
```

Full slice file:

```
$ scripts/run-bats.sh tests/index_sync.bats
bats: 69 passed, 0 failed
```

(68 pre-slice plus this slice's 1 previously-red case flipped; the 2
already-passing cases stay green.)

`shellcheck -s bash scripts/cc-hooks/index-sync-pre.sh` — exit 0.
`scripts/lint-shell.sh` — `lint-shell: 137 files clean`.

## Gate verdict

The first `just precommit` (dispatched with `run_in_background: true`)
straddled two trees — some gated input was edited and reverted mid-run, so
`lint` sentinel-hashed the tree before the mid-run edit while `test-unit` and
`test-integration` sentinel-hashed the tree during it, leaving `lint` at
`339038738 1081257` and the two suites at `337876578 1081255` when the team
lead flagged the mismatch. **That first run is not reported as a pass.**

Per the team lead's correction: made no further edit, then re-ran
`just test-unit` and `just test-integration` sequentially in the foreground
(never together — this box has ~2GB RAM).

- `just test-unit` — `bats: 791 passed, 0 failed`.
- `just test-integration` — `bats: 72 passed, 0 failed`.

Sentinel verdict read directly after both re-runs, all agreeing:

- `.git/gitlore/gates/lint` → `339038738 1081257`
- `.git/gitlore/gates/test-unit` → `339038738 1081257`
- `.git/gitlore/gates/test-integration` → `339038738 1081257`
- `.git/gitlore/gates/check-distribution` → `2398497780 495654` (separate
  input set from the three above, as it was at dispatch baseline too)

No second oscillation — the three `precommit_inputs`-sharing gates now carry
one hash, all newer than the pre-edit baseline `2540869285 1077572`.

## Commit

`b76a253` — subject `Item 2.1/2 — the pre-hook writes to the keyed path`
(gitmoji hook prefixed `feat` to `✨` on commit). Carries
`scripts/cc-hooks/index-sync-pre.sh`,
`tests/index_sync.bats`, this report, `item-2-1-s2-red.md`,
`item-2-1-s2-test-review.md`, and `plans/index-edit-propagation/runbook.md`
(a `format-docs` rewrap of already-committed prose, diff-checked to contain
no content change beyond line-wrap width).

## Consumers not touched

`scripts/lib/index-sync.sh` (slice 1's, unmodified), `index-sync-post.sh`
(slice 3), `index-compose.sh` and `add-tier-batch.sh` (slice 4) — including
their header comments. `tests/cc_hook_index_compose.bats` and
`tests/cc_hook_add_tier.bats` untouched.
