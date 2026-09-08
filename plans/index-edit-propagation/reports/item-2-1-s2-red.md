# Item 2.1 slice 2 — RED

Three cases added to `tests/index_sync.bats`. Two live beside the existing
`pre:` cases (after "pre: no-op when the edited file is not the index", `:132`);
the mutation case lives in the "per-agent pre-image / compose-stamp paths"
section slice 1 opened, after `compose_stamp_file suffixes the agent id` and
before `# --- routing-key advisories ---`. `pre_stdin` needed no change — its
callers already build the full payload, including `agent_id`, before handing it
to the piper. `batch_payload` gained an optional `TEST_AGENT_ID` (mirrors
`TEST_SESSION_ID`: unset/empty omits the `agent_id` field, non-empty adds it) —
not exercised by these three cases, which drive the pre-hook directly, but in
scope per the dispatch and needed by later slices' `post:`/batch cases.

## Command

```
bats -f "stamps the keyed path|stamps the bare path|cannot leave the gitdir" tests/index_sync.bats
```

```
1..3
not ok 1 pre: a payload carrying agent_id stamps the keyed path, not the bare one
# (in test file tests/index_sync.bats, line 148)
#   `[ -f "$(gitlore_index_preimage_file memory a1)" ]' failed
ok 2 pre: a payload with no agent_id stamps the bare path
ok 3 an agent id outside [A-Za-z0-9-] cannot leave the gitdir
```

Full suite (`scripts/run-bats.sh tests/index_sync.bats`):
**68 passed, 1 failed** — the one case above, no collateral damage to the other
68 (64 from before slice 1, plus slice 1's 4, plus this slice's 2 that already
pass).

## Per case

### 1. `pre: a payload carrying agent_id stamps the keyed path, not the bare one`

**FAILED on its assertion**, genuinely — `index-sync-pre.sh` does not read
`agent_id` at all yet, so it always writes the bare pre-image/stamp regardless
of what the payload carries. Death is on
`[ -f "$(gitlore_index_preimage_file memory a1)" ]` (`:148`): the keyed file was
never created. `$status -eq 0` on the preceding line passed (the hook ran and
exited 0), so this is a clean assertion failure, not an error or a missing
symbol. The case also asserts the bare-file absence
(`[ ! -f "$(gitlore_index_preimage_file memory)" ]`) — that one would fail too
on unmodified code (the bare files ARE created), so the case is doubly wrong
today; GREEN has to flip both.

### 2. `pre: a payload with no agent_id stamps the bare path`

**Passes already**, for the stated reason — `index-sync-pre.sh` always writes
the bare pre-image/stamp today (it reads no `agent_id`), which is exactly what
an absent-`agent_id` payload is supposed to produce. Not vacuous: it asserts the
two bare files exist (`[ -f "$(gitlore_index_preimage_file memory)" ]`, same for
the stamp) and, via the `find`-based idiom the slice text specifies, that no
keyed file exists in the gitdir (`-name 'gitlore-index-preimage-*'` /
`-compose-stamp-*'`) — both would fail if the hook ever started creating a keyed
file unconditionally, or stopped creating the bare one. Same shape as slice 1's
two "expected pass" cases (`item-2-1-s1-test-review.md`): a legitimate pass
proven non-vacuous by what it discriminates, not a missing assertion.

### 3. `an agent id outside [A-Za-z0-9-] cannot leave the gitdir`

Direct unit test of `gitlore_index_preimage_file`/`gitlore_compose_stamp_file`
with `../../../etc/passwd`, plus a same-case check that `agent-7` still passes
through byte for byte. Passes on the unmutated tree (the guard is already
committed from slice 1's code review). Red is obtained by mutation, per the
dispatch:

**Before** (`scripts/lib/index-sync.sh:130-133`, committed):
```sh
_gitlore_agent_suffix() {
  [ -n "${1:-}" ] || return 0
  printf -- '-%s' "$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9-' '_')"
}
```

**After** (passthrough mutation applied for the run below):
```sh
_gitlore_agent_suffix() {
  [ -n "${1:-}" ] || return 0
  printf -- '-%s' "$1"
}
```

Run against the mutation:
```
$ bats -f "cannot leave the gitdir" tests/index_sync.bats
1..1
not ok 1 an agent id outside [A-Za-z0-9-] cannot leave the gitdir
# (in test file tests/index_sync.bats, line 709)
#   `[ "$output" = "$base-$sanitized" ]' failed
```

Death is on the sanitized-equality comparison (the traversal id came back raw,
unsanitized), not on an error — genuine red by mutation, same shape as Item 1.1
slice 4.

## Restore

```
$ git checkout -- scripts/lib/index-sync.sh
$ git status --porcelain -- scripts/lib/index-sync.sh
(no output)
$ sha256sum scripts/lib/index-sync.sh
64f9d191243e685eda56bcb76456954306083bd22d21a6c087af1c8f65596c59  scripts/lib/index-sync.sh
```

Matches the sha before the mutation. Re-ran case 3 after restore: passes again
(shown in the combined 3-case run above, `ok 3`).

## Checks that passed, by name

- `bats -f "stamps the keyed path|stamps the bare path|cannot leave the gitdir" tests/index_sync.bats`
  — 1 genuine red, 2 legitimate passes, as above.
- `scripts/run-bats.sh tests/index_sync.bats` — 68 passed, 1 failed (this
  slice's one red case), no regression elsewhere.
- `shellcheck -s bash tests/index_sync.bats` — exit 0.
- `scripts/lint-shell.sh` — `lint-shell: 137 files clean`, same file count as
  slice 1 (no file added or left behind).
- `git status --porcelain -- tests/ scripts/ plans/` — `M tests/index_sync.bats`
  only.
- `git status --porcelain -- scripts/lib/index-sync.sh` after the mutation
  round-trip — empty. SUT restored byte-identical to HEAD.

## Out of scope, untouched

- `scripts/lib/index-sync.sh` — read, then temporarily mutated and restored;
  ends byte-identical to HEAD. `_gitlore_agent_suffix` was not asked to learn
  anything new.
- Every consumer under `scripts/cc-hooks/`, including
  `index-sync-pre.sh:43-47`'s comment — GREEN's work; read only, to see what the
  hook does with `agent_id` today (nothing).
- Slices 3 and 4's cases; `tests/cc_hook_index_compose.bats`;
  `tests/cc_hook_add_tier.bats`.
- `docs/`, `memory/`, and everything under `plans/` other than this report.

Nothing committed. `just precommit` not run, per the dispatch.
