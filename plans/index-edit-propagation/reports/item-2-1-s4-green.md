# Item 2.1 slice 4 — GREEN

## Implementation

### `scripts/cc-hooks/index-compose.sh`

The hook previously drained the payload unread (`cat >/dev/null`) and resolved
the compose stamp under the bare name only. Changed to capture the payload and
read `agent_id` from it, mirroring `index-sync-pre.sh`/`-post.sh` (slices 2-3):

```sh
payload=$(cat)   # the contents are still drained, not acted on; only agent_id below steers us
...
agent_id=$(jq -r '.agent_id // empty' <<<"$payload")
stamp=$(gitlore_compose_stamp_file "$mempath" "$agent_id")
[ -f "$stamp" ] || exit 0   # no baseline → no watched call this batch, for THIS agent
```

**No fallback to `.agent_type`** — `.agent_id // empty` only, per the runbook
and slices 2-3's settled contract.

The file has exactly one resolution site for the compose stamp, and the later
`rm -f "$stamp"` (line 50 pre-edit) already reads the same `$stamp` variable —
so keying the lookup keys the removal too, with no second edit needed. Confirmed
by
`grep -n 'gitlore_compose_stamp_file\|"\$stamp"' scripts/cc-hooks/index-compose.sh`:
one assignment, one `[ -f ]` guard, one `rm -f`, all on `$stamp`.

### `scripts/cc-hooks/add-tier-batch.sh`

Two changes:

1. The payload drain changed from `cat >/dev/null || true` to the runbook's
   prescribed form, now that the payload's content is read:

   ```sh
   payload=$(cat || true)   # drain stdin; the intent file, not the payload, drives us
   agent_id=$(jq -r '.agent_id // empty' <<<"$payload")
   ```

2. The `rm -f` that drops this batch's own compose baseline after a successful
   mount now targets the keyed name:

   ```sh
   rm -f "$(gitlore_compose_stamp_file "$mempath" "$agent_id")"
   ```

   This is the only site in the file that resolves the compose stamp (the intent
   file uses a separate helper, `gitlore_add_tier_file`, untouched). The
   surrounding comment block explaining *why* this `rm -f` exists (racing safely
   against either hook ordering, idempotent under genuine concurrency) needed no
   edit: it already speaks about "index-compose.sh's baseline" without asserting
   which name, and the claim stays true — it is now this batch's own keyed
   baseline, which is the correct one for this batch's own agent id.

## Traps addressed

- **Key the removal, not just the lookup** — both hooks now hold exactly one
  variable/expression for the stamp path, read by both the guard and the
  `rm -f`, so there is no way for one to key and the other to stay bare (the
  M3/M5 mutation shape the test review named).
- **A subagent's compose hook must still compose** — no early-exit gated on
  `[ -n "$agent_id" ]` anywhere; the hook proceeds identically for main-thread
  and subagent batches, differing only in which stamp name it resolves and
  removes (rules out M4).
- **No `agent_type` fallback** — both hooks read `.agent_id // empty` only,
  never `// .agent_type` (rules out M2). `add-tier-batch.sh`'s `agent_id` read
  now has a genuine use (the `rm -f` above), so no `SC2034` unused-var warning.
- **`payload=$(cat || true)` in `add-tier-batch.sh`** — used verbatim as the
  test review's M1 prescribed, under `set -euo pipefail`. `cat`'s own
  ordinary-EOF exit is 0, so `|| true` is a no-op in the success case and only
  guards a genuinely failing read.
- **`tests/cc_hook_add_tier.bats:155`** (the empty-id-stays-bare regression
  guard) still passes: verified individually below, not just as part of the
  full-suite count.

## Test results

Targeted suites:

```
$ scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats
bats: 28 passed, 0 failed
```

All three previously-red cases now pass:
- `a main-thread compose baseline survives a subagent's compose hook`
- `a subagent's compose consumes its own baseline, not the main thread's`
- `add-tier hook: drops the compose baseline for its own agent, leaves the bare one`

The pre-existing regression guard named in the dispatch, run individually to
confirm it stayed green rather than inferring it from the aggregate count:

```
$ bats -f "a main-thread batch drops the bare compose baseline, not an agent_type-keyed one" tests/cc_hook_add_tier.bats
ok 1 add-tier hook: a main-thread batch drops the bare compose baseline, not an agent_type-keyed one
```

Regression sweep on the slice 1-3 suite, unchanged at 71:

```
$ scripts/run-bats.sh tests/index_sync.bats
bats: 71 passed, 0 failed
```

Lint:

```
$ just lint
lint-shell: 137 files clean
```

`git status --porcelain -- scripts/ tests/` before staging:
`M scripts/cc-hooks/add-tier-batch.sh`, `M scripts/cc-hooks/index-compose.sh`,
plus the two test files already modified by the test-review dispatch (not
touched further here).

## Files touched

- `scripts/cc-hooks/index-compose.sh` — payload captured, `agent_id` read,
  compose-stamp lookup and removal keyed.
- `scripts/cc-hooks/add-tier-batch.sh` — payload drain changed to
  `payload=$(cat || true)`, `agent_id` read, compose-stamp removal keyed.

Nothing else edited. `tests/cc_hook_index_compose.bats` and
`tests/cc_hook_add_tier.bats` were not touched by this dispatch (already
reviewed and settled by the test-review pass).

## Out of scope, untouched

- `scripts/lib/index-sync.sh` — slice 1's, read only.
- `scripts/cc-hooks/index-sync-pre.sh` (slice 2) and `index-sync-post.sh` (slice
  3) — both closed, read only, mirrored but not modified.
- `tests/index_sync.bats` — read only, regression-swept above.
- `docs/`, `memory/`, and everything under `plans/` other than this report.

## Gate verdict

Left for the orchestrating session — not run here per the dispatch.

## Commit

Left for the orchestrating session — not made here per the dispatch.
