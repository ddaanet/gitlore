# RED: relay redesign, slice 2 (hooks)

Per `plans/index-edit-propagation/relay-redesign.md` §Slices, Slice 2, and the
slice-1 reports (`relay-s1-green.md`, `relay-s1-code-review.md`). RED, k=1:
`scripts/cc-hooks/relay-drain.sh` is an inert stub (sources `util.sh` and
`index-sync.sh`, consumes its stdin payload, exits 0 with no output) and is
registered in `hooks/hooks.json`. `index-sync-post.sh` and `index-compose.sh`
keep their drain branches unchanged; only their `gitlore_relay_write` call site
moved to the new argument order (`mempath session agent tag sysmsg ctx`) and
their `session_id` parse (new in `index-compose.sh`, already present but made
non-fatal in `index-sync-post.sh`) — no redesign. `session-start.sh` is
untouched. Nothing committed, no branch touched, `just precommit` not run.

## Memory recall gap

`plans/index-edit-propagation/recall-artifact.md` names four memory files —
`memory/ddaanet/hook-input-schema.md`, `genuine-red-not-missing-sut.md`,
`green-is-not-evidence.md`, `design-doc-writing.md` — that no longer exist in
`memory/ddaanet/` (grepped for their content under alternate names; nothing
matched). They appear to have been merged or retired since that artifact was
written, during an earlier phase of this same plan. Proceeded without them:
their load-bearing facts (agent_id subagent-only, PostToolBatch per-batch,
`systemMessage`/`additionalContext` split, genuine red as a failed assertion,
vacuous-negative pairing) are already covered by
`memory/ddaanet/shared-claude.md` (loaded every session) and by
`hook-output-channels.md` and `git-hook-env-leak.md`, which do exist and were
read. Flagging the drift rather than silently treating the artifact as current.

## New/rewritten cases — all seven FAIL on an assertion (none PASSED as new, none ERROR)

1. `tests/cc_hook_index_compose.bats`: **"concurrency: both reporting hooks
   reach relay-drain.sh exactly once per keyed batch"** (case 1). Ten
   iterations, `sync_feed a1 &` / `feed a1 &` / `wait` as real separate
   processes for one keyed batch, then `drain_feed "" test-session`. Fails on
   iteration 1 (`tests/cc_hook_index_compose.bats:320`):
   ```
   `[ "$n_sync" -eq 1 ] || { echo "iteration $i: n_sync=$n_sync output=$output"; return 1; }' failed
   iteration 1: n_sync=0 output=
   ```
   Deterministic, not a race: `relay-drain.sh` is silent on every call at k=1,
   so `n_sync`/`n_compose` are 0 every iteration. Reran 3 times standalone
   (`bats … --filter concurrency`); identical failure at iteration 1 each time —
   not flaky.

2. `tests/cc_hook_index_compose.bats`: **"relay-drain.sh delivers with no
   baseline (M2); a keyed run exits 0 silently and leaves the files"** (case 2).
   The keyed half (`drain_feed a1 test-session`: exit 0, empty output, marker
   untouched) passes trivially against the inert stub — disclosed below, not
   forced. The unkeyed half fails (`tests/cc_hook_index_compose.bats:346`):
   ```
   `[[ "$output" == *"M2 SYSMSG"* ]]' failed
   ```

3. Two cases, one per hook, replacing the "unkeyed … folds in" family:
   - `tests/index_sync.bats`:
     **"an unkeyed index-sync run leaves a marker in place"**, fails at
     `tests/index_sync.bats:773`:
     ```
     `[[ "$output" != *"gitlore-relay agent a1"* ]]' failed
     ```
   - `tests/cc_hook_index_compose.bats`:
     **"an unkeyed compose run leaves a marker in place"**, fails at
     `tests/cc_hook_index_compose.bats:289`:
     ```
     `[[ "$output" != *"gitlore-relay agent a1"* ]]' failed
     ```
   Both stage their marker under the empty/`"nosession"` mapping deliberately:
   today's drain branches are still unkeyed AND session-blind, so a marker under
   a *real* session (e.g. `test-session`) would already survive untouched today,
   making the assertion pass vacuously. Nosession is what today's code actually
   folds in and removes, so this is what makes each case genuinely red now and
   genuinely green once GREEN deletes the drain branches (which stop touching
   anything, regardless of session).

4. `tests/cc_hook_index_compose.bats`:
   **"relay-drain.sh with session S1 leaves an S2 file standing"** (case 4),
   fails at `tests/cc_hook_index_compose.bats:361`:
   ```
   `[[ "$output" == *"S1 BODY"* ]]' failed
   ```

5. Two cases in `tests/cc_hook_session_start.bats` (session-start.sh left
   untouched per the task frame, so both red on the current unkeyed,
   session-blind drain and the missing sweep call):
   - **"session-start drains its own session's marker and leaves a peer
     session's standing"**, fails at `tests/cc_hook_session_start.bats:378`:
     ```
     `[[ "$sysmsg" == *"S1 SYSMSG BODY"* ]]' failed
     ```
     (Neither `s1` nor `s2` is `"nosession"`, so today's drain — no session
     concept at all — finds neither; not a vacuous pass on the negative half.)
   - **"session-start sweeps a relay file older than 7 days"**, fails at
     `tests/cc_hook_session_start.bats:403`:
     ```
     `[ ! -e "$old_marker" ]' failed
     ```

## Case 7 (library level) — born green, mutation-proofed

`tests/index_sync.bats`:
**"relay_write: a tag outside {sync, compose} is refused and leaves no file"**
(the code review's flagged item). Passes as written — the guard is already in
`scripts/lib/index-sync.sh` from slice 1's code review. Disclosed rather than
forced: temporarily changed
`case "$tag" in sync|compose) ;; *) return 1 ;; esac` to
`case "$tag" in sync|compose|*) ;; esac` (accept-all), reran the single case —
`[ "$rc" -ne 0 ]` failed — then restored the file from a pre-mutation copy and
confirmed byte-identical (`diff`) and the case green again. No net change to
`scripts/lib/index-sync.sh` from this proof.

## Retired / adapted cases

Retired (superseded by the case named after each, per the task's replacement
map):
- `tests/cc_hook_index_compose.bats`: "an unkeyed compose run folds in the
  marker and removes it", "an unkeyed compose run with no report of its own
  still emits the relay", "an unkeyed compose run folds in a marker a keyed run
  wrote", "both PostToolBatch hooks in one keyed batch reach the parent" (→ case
  1), "an unkeyed run leaves a non-marker alone" — all pinned the
  drain-in-each-hook contract slice 2 removes; the last (`-type f` on a squatted
  non-marker) needed a filename-prediction technique D51's naming makes
  impossible pre-write, and its coverage is already carried by the library-level
  ".tmp beside the markers" case.
- `tests/index_sync.bats`: "an unkeyed index-sync run folds in the marker", "an
  unkeyed index-sync run with no report of its own still emits the relay" — same
  family, replaced by "an unkeyed index-sync run leaves a marker in place".
- `tests/cc_hook_session_start.bats`: "session-start drains a stranded relay
  marker" — replaced by "session-start drains its own session's marker and
  leaves a peer session's standing", which is the same fixture correctly scoped
  by session (the retired version keyed under a session-shaped argument the old
  4-arg signature had no room for, and passed today vacuously via the nosession
  mapping regardless of session-scoping).

Kept, adapted to the new signature and a glob-based marker lookup (all still
pass — confirmed in the full four-suite run, not merely assumed from the
signature change):
- `tests/index_sync.bats` / `tests/cc_hook_index_compose.bats`: "a keyed
  index-sync run writes its replacement report to a marker" / "a keyed compose
  run writes a marker and still emits its own json" —
  `gitlore_relay_marker_file` calls replaced by the new shared helper
  `relay_marker_for` (glob by agent id, `tests/helpers/fixtures.bash`), since
  D51's filenames (epoch+pid) are no longer predictable in advance.
- `tests/cc_hook_index_compose.bats`: "a failed relay write leaves the
  subagent's own report intact", "a failed relay write tells the subagent it was
  not staged" — the old technique (`mkdir` on a *predicted* marker path) is no
  longer possible for the same reason; substituted a `PATH`-shadowed `mv` stub
  that fails only a `*/gitlore-relay-*` destination and delegates everything
  else to the real `mv`, so `gitlore_compose_and_report`'s own index-writing
  `mv` (`index-compose.sh:702`) is untouched and composition still succeeds as
  the case requires.
- `tests/cc_hook_session_start.bats`: "an unreadable marker costs the relay, not
  the hook" — `gitlore_relay_write` call updated to the new 6-arg signature with
  an explicit empty/`nosession` session (matching what today's still-unkeyed
  drain actually targets) and `gitlore_relay_marker_file` replaced by
  `relay_marker_for`.
- `tests/cc_hook_session_start.bats`: "session-start with no marker emits no
  relay framing" — unchanged; it makes no `gitlore_relay_write` call and needed
  no adaptation.

## Helper changes

- `tests/helpers/fixtures.bash`: new `relay_marker_for(mempath, agent)` — glob
  lookup (`gitlore-relay-*-<agent>-*`, excluding `.tmp`) shared by all three
  suites via `load helpers/fixtures`.
- `tests/cc_hook_index_compose.bats`: `feed()` now carries a fixed
  `session_id: test-session` (previously carried none), matching `sync_feed()`'s
  own fixed value — needed so a fixture giving both hooks a real report in one
  keyed batch relays under one session rather than two. New `DRAIN` var and
  `drain_feed()` helper, mirroring `feed()`/`sync_feed()`, for driving
  `relay-drain.sh`.

## Full suite

`scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats tests/plugin_distribution.bats`:

```
141 passed, 7 failed
```

The 7 are exactly the new/rewritten cases above (index_sync.bats:45,
cc_hook_index_compose.bats:96–99, cc_hook_session_start.bats:130–131). Reran the
full four-suite set twice; identical result both times.

`just lint`: `lint-shell: 137 files clean` (includes the new
`scripts/cc-hooks/relay-drain.sh`, confirmed separately with a direct
`shellcheck` pass on every touched/new script and test file — all clean).

## Scope

Touched: `scripts/cc-hooks/relay-drain.sh` (new), `hooks/hooks.json`,
`scripts/cc-hooks/index-sync-post.sh`, `scripts/cc-hooks/index-compose.sh`,
`tests/helpers/fixtures.bash`, `tests/index_sync.bats`,
`tests/cc_hook_index_compose.bats`, `tests/cc_hook_session_start.bats`,
`tests/plugin_distribution.bats`. Not touched:
`scripts/cc-hooks/session-start.sh` (per the task frame — case 5 reds on it
as-is), `scripts/cc-hooks/nudge-reset.sh`, `docs/`, and
`scripts/lib/index-sync.sh` (case 7's guard was already in place from slice 1's
code review; the mutation proof above left it byte-identical).
