# GREEN: relay redesign, slice 2 (hooks)

Per `plans/index-edit-propagation/relay-redesign.md` §Slices, Slice 2, the RED
report (`relay-s2-red.md`), its test review (`relay-s2-test-review.md`) and the
library contract (`relay-s1-code-review.md`). Nothing committed, no branch
touched, `just precommit` not run.

## The four files

- `scripts/cc-hooks/relay-drain.sh` (new, 39 lines): sources `util.sh` and
  `index-sync.sh`; reads its payload once; parses `session_id` and `agent_id`
  non-fatally; a keyed run (`agent_id` non-empty) exits 0 at once, before either
  guard; otherwise `gitlore_cd_project_root` / `gitlore_has_submodule` guard as
  every other hook; no baseline of its own — calls
  `gitlore_relay_drain "$mempath" "$session"` unconditionally and emits both
  channels through `jq -n` when `GITLORE_RELAY_SYSMSG` is non-empty. No
  pre-image, no stamp, no index-existence check, matching the design: it runs on
  every main-thread batch by construction (M2).
- `hooks/hooks.json`: `relay-drain.sh` registered once under `PostToolBatch`, no
  matcher, alongside its five siblings (already true going into this slice — the
  RED stub had it wired).
- `scripts/cc-hooks/index-sync-post.sh`: the `else` drain branch is gone. The
  keyed branch (`[ -n "$agent_id" ] && [ -n "$sysmsg" ]`) is unchanged apart
  from that merge, still calls `gitlore_relay_write … sync …` with `$session`
  and the `sync` tag, and its header comment now names `relay-drain.sh` as the
  consumer instead of arguing the old "fold in what a subagent staged" premise.
  `session` itself is still parsed the same non-fatal way and still feeds the
  byte-budget nudge marker, so it stays a live variable.
- `scripts/cc-hooks/index-compose.sh`: same shape — the `else` branch that
  called `gitlore_relay_drain "$mempath"` unkeyed is gone, the keyed branch
  merged into one `if` with its emptiness guard, comment rewritten the same way,
  `compose` tag and `$session` unchanged.
- `scripts/cc-hooks/session-start.sh`: reads `payload=$(cat)` once, right after
  sourcing `util.sh` and before `gitlore_cd_project_root`, matching
  `nudge-reset.sh`'s own placement. `session_id` is parsed non-fatally
  (`|| session=""`) immediately above the relay call, which is now
  `gitlore_relay_drain "$mempath" "$session"` followed by
  `gitlore_relay_sweep "$mempath"`, still positioned after every early exit
  (guards, launcher check, diverged/ff-failure returns) and before the final
  `emit_session_json`. The header comment above the call is rewritten from the
  code: own-session drain is the only path a report reaches a session that
  resumed or compacted (neither event fires the PostToolBatch drainer); the
  sweep collects anything older than 7 days, temps included, because a report to
  a session that ended with no further batch has no other backstop; both calls
  absorb every failure and return 0. Confirmed no other part of the script reads
  stdin, so the single `cat` does not disturb anything else.

Comments elsewhere: grepped `gitlore-relay`/`relay` across `scripts/` — the only
files touched are the four above plus `scripts/lib/index-sync.sh` (slice 1, out
of scope here, unmodified this slice). No stray comment left arguing the
drain-in-each-hook premise.

`bash -n` and `shellcheck -x` clean on all four files (`shellcheck` also
flagged, then cleared, an SC2034 on `payload` in `session-start.sh` mid-edit —
resolved once the session parse landed below it).

## Per-test result — the seven RED cases, one at a time in the RED report's order

All seven now pass, made green in this order against the four files above (no
test file edited):

1. `tests/cc_hook_index_compose.bats`: "concurrency: both reporting hooks reach
   relay-drain.sh exactly once per keyed batch" — pass, 10/10 iterations,
   `n_sync=1`, `n_compose=1`, `n_frame=2` every round.
2. `tests/cc_hook_index_compose.bats`: "relay-drain.sh delivers with no baseline
   (M2); a keyed run exits 0 silently and leaves the files" — pass, both halves
   (keyed silent/untouched, unkeyed delivers `M2 SYSMSG` and `M2 CTX` and
   removes the marker).
3. `tests/index_sync.bats`: "an unkeyed index-sync run leaves a marker in place"
   — pass. `tests/cc_hook_index_compose.bats`: "an unkeyed compose run leaves a
   marker in place" — pass.
4. `tests/cc_hook_index_compose.bats`: "relay-drain.sh with session S1 leaves an
   S2 file standing" — pass.
5. `tests/cc_hook_session_start.bats`: "session-start drains its own session's
   marker and leaves a peer session's standing" — pass. "session-start sweeps a
   relay file older than 7 days" — pass.

## Full suite

`scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats tests/plugin_distribution.bats`:

```
148 passed, 0 failed
```

(141 pre-existing + the 7 above; no regression anywhere else in the four files.)

`just test-unit` (full unit suite, foreground per the task frame — ran in the
background of this session and confirmed via the gate sentinel
`.git/gitlore/gates/test-unit`, written after this slice's edits):

```
846 passed, 0 failed
```

`just lint`: `lint-shell: 137 files clean` (includes the new
`scripts/cc-hooks/relay-drain.sh`).

## Scope

Touched: `scripts/cc-hooks/relay-drain.sh` (new), `hooks/hooks.json` (no change
needed — already registered from the RED stub),
`scripts/cc-hooks/index-sync-post.sh`, `scripts/cc-hooks/index-compose.sh`,
`scripts/cc-hooks/session-start.sh`. Not touched: `scripts/lib/index-sync.sh`
(slice 1's contract, out of scope), `docs/` (slice 3), any test file.
