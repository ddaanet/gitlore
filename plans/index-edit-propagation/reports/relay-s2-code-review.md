# GREEN code review: relay redesign, slice 2 (hooks)

Review of `scripts/cc-hooks/relay-drain.sh` (new) and the `git diff` on
`scripts/cc-hooks/index-sync-post.sh`, `scripts/cc-hooks/index-compose.sh`,
`scripts/cc-hooks/session-start.sh` and `hooks/hooks.json`, against
`plans/index-edit-propagation/relay-redesign.md` §Decisions, the RED /
test-review / GREEN reports, `relay-s1-code-review.md` for the library contract,
`.claude/rules/shell.md`, `memory/ddaanet/hook-output-channels.md` and
`memory/ddaanet/shared-claude.md` §Code and §Tests.

Seven fixes applied, all in scope, all to the four scripts. Nothing committed,
no branch touched, no test file edited, `just precommit` and `just test-unit`
not run.

Final state:
`scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats tests/plugin_distribution.bats`
— **148 passed, 0 failed**. `just lint` — `lint-shell: 137 files clean`.

## Fixes applied

### 1. The drain's payload parse failed toward destroying reports (major)

`relay-drain.sh` parsed both fields with `|| session=""` / `|| agent_id=""`,
copying the reporting hooks' fallback. That fallback is right for them and wrong
here, because their action is additive and this one is destructive: the drain
removes every file it reads. With `agent_id=""` on a payload jq could not parse,
a run **inside a subagent** takes the main-thread path, frames the markers into
a transcript no one else reads, and unlinks them. A drain that does not run at
all is re-delivered by the next batch or by SessionStart; a drain that runs
blind loses what it took.

The same fallback also let a broken or missing `jq` reach the store: `jq -r`
failing twice leaves the hook draining the `nosession` bucket, after which the
`jq -n` emit fails under `set -e`, the hook exits non-zero, stdout is discarded
— and the files are already gone.

Both parses now `|| exit 0`, which is still non-fatal in the hook sense (exit 0,
no output) and is stated as a deliberate direction rather than an oversight:

```sh
session=$(jq -r '.session_id // ""' <<<"$payload") || exit 0
agent_id=$(jq -r '.agent_id // empty' <<<"$payload") || exit 0
```

Probed: the tests always feed valid JSON (`drain_feed` builds it with `jq -n`),
and an *empty* payload is not a parse failure — `printf '' | jq -r '.x // ""'`
exits 0 — so no case changes behaviour. The residual that remains, stated in the
comment as a bound: between the drain and the emit the reports exist only in
variables, so a failure in that window still loses them. It is narrower now,
since the two parses above establish that `jq` works before anything is read.

### 2. The header cited `plans/` and a review-finding id (major)

`relay-drain.sh`'s header opened with
`D51 (revised): … (plans/index-edit-propagation/relay-redesign.md)` and closed
its second reason with `(M2)`. A comment may not point at a plan, and `M2` is an
id from `reports/deliverable-review.md` that outlives nothing. Rewritten to
argue from the two platform facts directly, naming neither:

- every hook matching one event runs in parallel, so a drain living in both
  reporting hooks runs twice on a batch that fires both and doubles every
  relayed report;
- each reporting hook runs only when its own baseline fired, so a drain living
  in either skips the batch whose `Agent` call returned — that batch changed no
  index and left no stash and no stamp, and it is exactly the batch the
  subagent's report was staged for.

### 3. `D51 (revised)` in four comments (medium)

`docs/decisions.md` carries **D51**, not "D51 revised". The parenthetical is
also the "correction of a previous version" framing the writing rule bans — git
history is the changelog. Removed from `relay-drain.sh`, `index-sync-post.sh`,
`index-compose.sh` and `session-start.sh`; each now names `relay-drain.sh` as
the one drainer without dating the claim.

### 4. The parse comments pointed at each other instead of stating a reason (medium)

`relay-drain.sh` and `index-sync-post.sh` both carried "see index-compose.sh's
identical note on its own agent_id parse", while `index-compose.sh`'s note
points back at `index-sync-post.sh` for the agent_id contract. The notes are
also not identical: compose's argument is that the **stamp** is its trigger,
which is compose-specific. Each comment is now self-contained and argues from
what that hook actually loses.

`index-sync-post.sh`'s, grounded in `index-sync-pre.sh:65`
(`if [ -f "$stash" ] then exit 0`), which is what makes a stranded stash
durable:

> the stash is what drives this hook, so an unparseable payload must not be what
> stops it. A jq aborting under errexit would leave the stash unconsumed, and
> `index-sync-pre.sh`'s `if [ -f "$stash" ]` then hands that stale baseline to a
> later batch, which propagates against an ancient index. Falling back costs the
> session keying of the byte-budget nudge and the relay staging below — never
> the propagation itself.

### 5. `session-start.sh` lost the placement argument (major)

The rewrite dropped the paragraph explaining why the relay calls sit **after**
the diverged and ff-failure early exits, leaving the placement — which the brief
keeps deliberately — unargued. Restored, and corrected rather than copied: the
retired version promised "the marker survives undrained to the session after the
repair, so the relay is delayed rather than lost", which own-session keying
makes false. The divergence message tells the user to start a **fresh** session,
and a fresh session has a new id and is a stranger to those markers. The comment
now states what is true: a resume or compaction of the same session still
collects them here, a fresh session leaves them to the sweep like any other
session's report.

### 6. `session-start.sh`'s `session_id` parse had no stated reason (medium)

`|| session=""` with nothing saying why it is non-fatal, or why the fallback
direction is the opposite of fix 1's. Added, and it is checkable rather than
asserted: `jq` has already parsed `.claude/settings.json` at line 36 and the
hook exits when it cannot, so the only failure reachable here is a malformed
payload, and it costs the own-session keying alone — the sweep still runs.

### 7. `payload=$(cat)` sat ~390 lines above its use with a thin comment (minor)

The comment said only "read once; session_id parsed from it below". The
invariant a future editor can break is that
**nothing else in this script reads stdin** — the two `while IFS= read -r` loops
at lines 249 and 370 consume pipelines, not stdin — and that the read precedes
every guard that exits. Both now stated. `index-compose.sh`'s `session` parse
also moved from `// empty` to `// ""`, the shape every other session_id parse in
the repo uses; identical result, and the two comments no longer claim to be the
same shape while differing.

## Verified against the brief, no change needed

- **`relay-drain.sh` structure.** `set -euo pipefail`; payload read exactly
  once; keyed run exits 0 **before** `gitlore_cd_project_root`, so it never
  touches the store; the project-root and submodule guards then follow in the
  same order and with the same `|| exit 0` comment as `index-sync-post.sh` and
  `index-compose.sh`; `gitlore_relay_drain "$mempath" "$session"` called with
  the session; `exit 0` as the last statement.
- **Emission.** JSON only when `GITLORE_RELAY_SYSMSG` is non-empty, built with
  `jq -n --arg`, carrying `suppressOutput: true` and
  `hookSpecificOutput.hookEventName: "PostToolBatch"` — byte-identical in shape
  to `index-compose.sh`'s emit.
- **No baseline.** No pre-image, no stamp, no index-existence check. The drain
  itself guards a missing gitdir (slice 1's `rev-parse` / `[ -d ]`) and returns
  0 on every path, and sets both out-variables before either early return, so
  `set -u` on `$GITLORE_RELAY_CTX` is safe.
- **The two reporting hooks.** No drain branch and no comment about folding
  survives in either; `grep -rn relay scripts/ hooks/` outside
  `scripts/lib/index-sync.sh` returns only the write call sites, the not-staged
  fallback, and comments naming `relay-drain.sh` as the consumer. Nothing argues
  sequential hooks or a per-agent merge. Each keyed write passes `"$session"`
  and its own tag (`sync` / `compose`) in the new argument order.
- **The not-staged fallback text is unchanged** in both hooks, including
  `index-sync-post.sh`'s `$sysmsg`-when-`$ctx`-is-empty branch.
- **`index-sync-post.sh`'s `session` is still one parse.** It feeds
  `gitlore_index_budget_nudge_file "$mempath" "$session"` at line 177 exactly as
  before, and the relay write at 268; no second parse was added.
- **`hooks.json`.** `relay-drain.sh` registered once under `PostToolBatch` as
  its own matcher-less entry, the same shape as all five siblings; the file is
  `-rwxr-xr-x`. `tests/plugin_distribution.bats:205` asserts `length` is 1 —
  which catches a duplicate registration, the doubling half of C2 — plus
  `[ -x ]`, matching the house shape for every other hook.
- **Shell rules.** No `2>/dev/null` added anywhere. Every expansion quoted;
  nothing splits on whitespace; no `ls`. bash 3.2 safe — no arrays, no
  `${var,,}`, `<<<` and `${BASHPID:-$$}` only in the library. No BSD/GNU
  divergence in the hooks: `cat`, `jq` and `[` only.
- **Entry points first.** Each script reads its payload, parses, guards, then
  acts; no constant or helper is front-loaded above its user.
- **Comments state current truth.** After fixes 2, 3 and 5,
  `grep -rn 'revised\|plans/'` over the four scripts returns nothing.

## Mutation probe

One probe, in place, restored byte-identical (`diff` clean) and re-run green.

Removed the keyed-exit guard from `relay-drain.sh`
(`[ -z "$agent_id" ] || exit 0` → a no-op `:`) and ran
`tests/cc_hook_index_compose.bats`:

```
not ok 14 relay-drain.sh delivers with no baseline (M2); a keyed run exits 0 silently and leaves the files
# (in test file tests/cc_hook_index_compose.bats, line 351)
#   `[ -z "$output" ]' failed
23 passed, 1 failed
```

The guard is genuinely load-bearing and the case genuinely watches it. Restored
and re-run: 24 passed, 0 failed.

## Flagged, not fixed

- **`tests/plugin_distribution.bats:196` still says "D51 (revised)".** Same
  wording as fix 3, in a file this pass does not own. One word, worth taking
  with the docs slice.
- **The `git ls-files -s` clause the test review left for GREEN is still
  pending.** `scripts/cc-hooks/relay-drain.sh` is untracked, so the mode
  assertion the sibling `plugin-upgrade-batch.sh` case carries cannot be written
  yet without the case redding for a packaging reason. It belongs to whoever
  stages the commit, not to this review.
- **`relay-drain.sh` emits `additionalContext` even when the ctx half is empty**,
  following `index-compose.sh`; `index-sync-post.sh` omits the key instead. An
  empty context injects nothing, so this is a shape inconsistency rather than a
  defect, and the compose precedent is the closer sibling. Left as is.
- **The drain-then-emit window is a residual, not a bug to fix here.** Once
  `gitlore_relay_drain` returns, the reports exist only in two variables and the
  files are gone; anything that kills the hook before its `jq -n` lands loses
  them. Claim-by-rename is the fix and D51 rejects it by name. Fix 1 narrows the
  window to the emit itself; the bound is stated in the code and belongs in
  slice 3's node alongside the delivery-timing residual.

## Checks run

| check | result |
| --- | --- |
| `scripts/run-bats.sh` over the four suites | 148 passed, 0 failed |
| `just lint` | `lint-shell: 137 files clean` |
| `shellcheck -x` on all four scripts | clean |
| `bash -n` on all four scripts | OK |
| keyed-exit mutation probe | reds case 14, restored byte-identical |
| `grep -rn 'relay' scripts/ hooks/` | no stale premise outside the library |
