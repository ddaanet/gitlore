# Item 2.1 slice 4 — RED

Two cases added, one in `tests/cc_hook_index_compose.bats`, one in
`tests/cc_hook_add_tier.bats`. Both suites' shared-payload helpers gained an
optional trailing agent id, following the absent/empty-vs-non-empty contract
`tests/index_sync.bats` already uses for `gitlore_index_preimage_file` /
`gitlore_compose_stamp_file` and their own `pre_stdin`/`batch_payload` helpers.
`scripts/lib/index-sync.sh` was read only, unchanged.

## Command

```
scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats
```

```
not ok 9 a main-thread compose baseline survives a subagent's compose hook
# (in test file tests/cc_hook_index_compose.bats, line 173)
#   `[ -z "$output" ]' failed
not ok 23 add-tier hook: drops the compose baseline for its own agent, leaves the bare one
# (in test file tests/cc_hook_add_tier.bats, line 147)
#   `[ ! -f "$keyed" ]' failed

bats: 24 passed, 2 failed — full log: /tmp/claude-1000/gitlore-bats.PiI2fm
```

24 passed = 15 pre-existing compose cases + 9 pre-existing add-tier cases, both
untouched. 2 failed = this slice's two new cases, both genuine reds, no
collateral damage elsewhere.

## Helper changes

### `tests/cc_hook_index_compose.bats`

- `pre()` (`:27`, was file-name-only) gains a second, optional agent id argument
  — absent/empty omits `agent_id`; non-empty adds it. Every call also stamps
  `agent_type:"general-purpose"`, the decoy: a real `--agent`-session
  main-thread payload carries `agent_type` but never `agent_id`, so a hook that
  falls back to `agent_type` must still fail the no-agent-id case.
  `index-sync-pre.sh` (unchanged, from slice 2) reads only `agent_id`, so this
  decoy is inert for the file's 15 pre-existing calls — verified by the
  full-suite run above showing no regression.
- `feed()` (`:36`, was a literal `{}`) gains the same optional agent id argument
  and the same decoy. Its old comment ("The payload is drained and ignored; an
  empty object is a faithful stand-in") is gone — the payload's *contents* are
  still ignored by index-compose.sh today, but the whole point of the new
  argument is to make the agent id matter once GREEN reads it.
- File header gained `# shellcheck disable=SC2119,SC2120` (with a one-line
  rationale) — shellcheck flags `pre()`/`feed()` calls that omit the now-
  optional argument, which is intentional here.

### `tests/cc_hook_add_tier.bats`

- `run_batch()` (`:23`, was a fixed literal payload) gains the same optional
  trailing agent id and the same `agent_type` decoy, same contract.
- Same `# shellcheck disable=SC2119,SC2120` addition, for the same reason.

## Per case

### 1. `a main-thread compose baseline survives a subagent's compose hook` (`tests/cc_hook_index_compose.bats`)

**FAILED on its assertion, genuinely.** `pre "$PWD/memory/MEMORY.md"` (no agent
id) establishes the bare compose stamp — a main-thread call. `feed a1` then
drives `index-compose.sh` as if from inside a subagent's own PostToolBatch.
`index-compose.sh` today (`scripts/cc-hooks/index-compose.sh:23`) still
`cat >/dev/null`s the payload and resolves only
`gitlore_compose_stamp_file "$mempath"` — the bare name, unconditionally — so it
finds the parent's stamp, composes against it, reports on both channels, and
consumes (removes) it. Death is on `[ -z "$output" ]`
(`tests/cc_hook_index_compose.bats:173`): the run produces a non-empty
systemMessage/additionalContext instead of staying silent.

**Both remaining assertions independently discriminate**, checked by swapping
assertion order in a scratch copy (`tests/scratch_compose.bats`, removed after)
and re-running:

```
$ bats -f "a main-thread compose baseline survives a subagent's compose hook" tests/scratch_compose.bats
1..1
not ok 1 a main-thread compose baseline survives a subagent's compose hook
# (in test file tests/scratch_compose.bats, line 173)
#   `[ -f "$(gitlore_compose_stamp_file memory)" ]' failed
```

So the bare stamp is genuinely consumed (not merely readable-but-untouched) by
the current code — either assertion alone would catch the bug, matching the
shape slice 3's case 1 mutation check used.

### 2. `add-tier hook: drops the compose baseline for its own agent, leaves the bare one` (`tests/cc_hook_add_tier.bats`)

**FAILED on its assertion, genuinely.** Fixture pre-creates both a keyed compose
stamp (`gitlore_compose_stamp_file memory a1`) and an independent bare one
(`gitlore_compose_stamp_file memory`), then runs the batch with `agent_id: "a1"`
and a mount intent that succeeds. `add-tier-batch.sh` today (`:75`) reads no
agent id and unconditionally does
`rm -f "$(gitlore_compose_stamp_file "$mempath")"` — the bare name only — so
after a successful mount the bare stamp is gone and the keyed one is untouched.
That is exactly backwards from what the case asserts. Death is on
`[ ! -f "$keyed" ]` (`tests/cc_hook_add_tier.bats:147`) — the keyed file is
still there.

**Both remaining assertions independently discriminate**, same check via a
scratch copy (`tests/scratch_add_tier.bats`, removed after) with the two
assertions swapped:

```
$ bats -f "drops the compose baseline for its own agent" tests/scratch_add_tier.bats
1..1
not ok 1 add-tier hook: drops the compose baseline for its own agent, leaves the bare one
# (in test file tests/scratch_add_tier.bats, line 147)
#   `[ -f "$bare_stamp" ]' failed
```

The bare stamp is genuinely removed by the current code while the keyed one
survives — either assertion alone catches the bug.

## Checks that passed, by name

- `scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats`
  — 24 passed (all pre-existing cases in both files, unchanged), 2 failed (this
  slice's two new cases, both genuine reds).
- `bats -f "a main-thread compose baseline survives a subagent's compose hook" tests/cc_hook_index_compose.bats`
  — isolated red, same assertion.
- `bats -f "drops the compose baseline for its own agent" tests/cc_hook_add_tier.bats`
  — isolated red, same assertion.
- Assertion-order swap on both cases (scratch copies, removed after) — both reds
  independently confirmed non-vacuous, as shown above.
- `shellcheck -s bash tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats`
  — exit 0.
- `scripts/lint-shell.sh` — `lint-shell: 137 files clean`.
- `git status --porcelain -- tests/` — `M tests/cc_hook_add_tier.bats`,
  `M tests/cc_hook_index_compose.bats` only; no scratch files left behind.

## Out of scope, untouched

- `scripts/cc-hooks/index-compose.sh` and `scripts/cc-hooks/add-tier-batch.sh` —
  read only, unchanged; this is GREEN's work.
- `scripts/lib/index-sync.sh` — read only, unchanged (slice 1's, already keyed).
- `tests/index_sync.bats` and `scripts/cc-hooks/index-sync-pre.sh` /
  `index-sync-post.sh` — slices 1-3's, untouched.
- `docs/`, `memory/`, and everything under `plans/` other than this report.

## Files touched

- `tests/cc_hook_index_compose.bats`
- `tests/cc_hook_add_tier.bats`

Nothing committed. `just precommit` not run, per the dispatch. Tree left dirty
and unstaged.
