# RED test review: relay redesign, slice 2 (hooks)

Review of the new and rewritten cases in `tests/cc_hook_index_compose.bats`,
`tests/cc_hook_session_start.bats`, `tests/plugin_distribution.bats`,
`tests/index_sync.bats` and the `relay_marker_for` helper in
`tests/helpers/fixtures.bash`, against
`plans/index-edit-propagation/relay-redesign.md` §Decisions and §Slices,
`reports/relay-s2-red.md`, `reports/relay-s1-code-review.md`,
`.claude/rules/shell.md`, `memory/ddaanet/hook-output-channels.md` and
`memory/ddaanet/shared-claude.md` §Tests.

Six fixes applied, all on tests and helpers, plus one note. Nothing committed,
no branch touched, `just precommit` not run. `scripts/cc-hooks/relay-drain.sh`,
`scripts/lib/index-sync.sh` and `scripts/cc-hooks/session-start.sh` were each
mutated for a probe and restored byte-identical; `git diff --stat` names the
same library and hook files it named before this review, with the same line
counts.

Two of the fixes are the review's substance: the concurrency case could not
detect the doubled block it exists to detect, and the whole session-start suite
was one GREEN edit away from hanging.

## Mechanical check

`scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats tests/plugin_distribution.bats`,
run before any fix: **141 passed, 7 failed**, matching the RED report exactly.
Every failure is a failed assertion at a named line; none is an ERROR, and no
case the report lists as red passed.

A second run surfaced an eighth failure the RED report did not list —
`relay_write does not destroy a staged report when its temp cannot be written` —
which turned out to be a pre-existing flake, fix 5 below.

## Findings and fixes

### 1. The concurrency case could not see a doubled report (major)

Case 1 counted with `grep -c 'phrase' <<<"$output"` over the drain's
**raw JSON**. `jq` emits `systemMessage` as one physical line with its newlines
escaped, so `grep -c` — which counts matching *lines*, not occurrences — returns
1 no matter how many blocks the drain wrote. The assertion read "exactly once"
and meant "at least once".

Proved by mutation rather than by reading: with the probe drainer doubling both
channels (`GITLORE_RELAY_SYSMSG="$GITLORE_RELAY_SYSMSG$GITLORE_RELAY_SYSMSG"`),
the case **passed**. A report relayed twice is one of the two symptoms C2 names,
and the case named as its whole purpose was blind to it.

Fixed by counting on the decoded channel, where the drain's framing puts one
block per line, and by adding a framing-line count:

```sh
sysmsg=$(jq -r '.systemMessage' <<<"$output")
n_sync=$(printf '%s\n' "$sysmsg" | grep -c 'reset frontmatter to match MEMORY.md' || true)
n_frame=$(printf '%s\n' "$sysmsg" | grep -c -- '--- gitlore-relay agent a1 ---' || true)
...
[ "$n_frame" -eq 2 ] || { echo "iteration $i: n_frame=$n_frame sysmsg=$sysmsg"; return 1; }
```

Re-mutated after the fix: the doubling mutation now fails at iteration 1 with
`n_sync=2`. Against the correct drainer it passes, three consecutive runs.

### 2. Every session-start case was one GREEN edit from hanging (major)

Slice 2 gives `session-start.sh` a payload read. Every other hook reads its
payload with `payload=$(cat)`, and 45 call sites across five suites invoke
`bash "$SESSION_START"` with **nothing piped in**, so that `cat` would inherit
bats' own stdin.

Measured rather than assumed: inside a bats test, stdin is a socket, not
`/dev/null` — `timeout 3 cat > /dev/null` exits 124. The suite would not fail,
it would hang, and under an interactive run it would hang on the terminal.

The RED author saw the need and covered two cases with a piping helper
(`run_session_start_with_session`); the other 43 sites, including the new sweep
case, were left bare.

Fixed once, in `setup_tmp_repo` (`tests/helpers/setup.bash`), with
`exec 0</dev/null` and the reason inline. `exec` rather than a per-call redirect
because it has to hold for every invocation in the body; bats runs setup and the
test in one process, so it does not leak to the next test, and a test that means
to feed a payload still pipes one, which overrides it.

Verified with a temporary session-start carrying `gl_payload=$(cat)` and a
session-keyed drain plus sweep: all four relay cases in that suite pass,
including the three that invoke the hook bare.

### 3. `relay_marker_for` matched on an unanchored agent field (medium)

`-name "gitlore-relay-*-$agent-*"` matches wherever `-$agent-` appears: an agent
id another id is a prefix of, or a session id embedding it. The header comment
documented the hazard instead of removing it.

Anchored on the whole `-<agent>-<epoch>-<pid>-<tag>` tail, which the naming
scheme makes exact — two decimal fields and a tag from a closed set:

```sh
found=$(find "$gitdir" -maxdepth 1 -type f \
  '(' -name "gitlore-relay-*-$agent-[0-9]*-[0-9]*-sync" \
  -o -name "gitlore-relay-*-$agent-[0-9]*-[0-9]*-compose" ')' -print)
```

The tail anchor also excludes a writer's in-progress temp by construction — it
ends in `.tmp`, not in a tag — so the separate `'!' -name '*.tmp'` clause is
gone. The helper now also refuses a non-unique match with a message naming the
count, instead of returning a two-line string that fails the caller's
`[ -f "$marker" ]` with nothing said about why.

### 4. Three cases asserted less than they named (medium)

- **Case 2 (M2)** checked `systemMessage` only. M2 is about the parent
  *learning* of its subagent's report, and `additionalContext` is the half the
  parent model reads. Added `[[ "$ctx" == *"M2 CTX"* ]]`.
- **Case 4 (S1/S2 keying)** matched on raw JSON, never decoded a channel, and
  never asserted the S1 file was removed. Now decodes both channels for the
  positives, keeps the S2 refutation on the raw JSON so it covers a channel the
  case does not name, and adds `[ ! -e "$s1_marker" ]`.
- **Case 5 (session-start drain)** dropped the `$RELAY_FRAMING` assertions the
  retired case carried. That constant's own header says the positive case is
  what pins the wording, and the negative
  (`session-start with no marker emits no relay framing`) refutes it — a
  refutation of a string no positive asserts stops watching anything the day the
  wording moves. Restored on both channels, and added `[ ! -e "$s1_marker" ]`,
  since drained means read *and* removed.
- **Case 5, sweep half** had no keeper: a sweep that deleted every relay file
  regardless of age satisfied it. Added a fresh marker under a session nothing
  in that case drains, so only its age can decide it, and asserted it survives.

### 5. A pre-existing flake, 4 failures in 25 runs (medium)

`relay_write does not destroy a staged report when its temp cannot be written`
(`tests/index_sync.bats`) needs its second write to land on the *same* name as
the first, and squats that name's `.tmp`. The comment argued the pid half (both
calls in one process, never through `run`) and missed the epoch half: the name
also carries `date +%s`, so whenever the two calls straddle a second boundary
the second picks a fresh name, misses the squat and succeeds.

Measured at **4 failures in 25 runs** before the fix, **0 in 25** after. This is
slice 1's case rather than slice 2's, and it is not caused by anything in this
slice; it is reported here because it fails inside the suite this review
certifies.

Fixed by freezing the epoch for the two writes with a `PATH`-shadowed `date`
that answers `+%s` with a constant and delegates everything else to the real
binary, so the collision is the fixture's construction rather than a coincidence
of timing.

### 6. The distribution case's comment named a failure it cannot detect (minor)

The comment argued from a recorded `100644`; the case asserts `[ -x ]`, which
reads the working tree. The sibling `plugin-upgrade-batch.sh` case pins the
recorded mode with `git ls-files -s` for exactly that reason, and this one
cannot yet: `scripts/cc-hooks/relay-drain.sh` is untracked, so `ls-files -s`
would report nothing and the case would red for a packaging reason rather than
an assertion. Comment corrected to state what the case reaches.
**For GREEN or the orchestrator:** once the file is tracked, add the three-line
`ls-files -s` clause the plugin-upgrade case carries.

The comment now also states why `length` is 1 rather than `>= 1` — a duplicate
registration would relay every report twice, which is the other half of C2.

### Note: `hook-output-channels.md` has no §2

The task frame cites `memory/ddaanet/hook-output-channels.md §2`. The file
carries no numbered sections; it was read whole. Same class of drift as the four
missing memory files the RED report flagged.

## Checks the review ran and did not have to fix

- **Case 1's fixture really gives both hooks a report.** Dumped one iteration:
  the sync hook emits `reset frontmatter to match MEMORY.md (1 file)`, the
  compose hook emits `recomposed tier pointers (1 index)`, and two files land in
  the gitdir with the **same epoch and different pids** —
  `gitlore-relay-test-session-a1-<epoch>-278-compose` and `…-276-sync`. The pid
  is doing the separating, which is the guarantee D51 claims and the reason the
  case spawns real processes rather than subshells.
- **Case 1 resets per iteration.** Fresh `a$i.md` / `shared$i.md` / MEMORY.md
  each round rather than a teardown cycle, and the root index is overwritten
  with an unspliced single bullet, so the compose hook has a real change every
  round and the cross-iteration count catches a file the drain failed to remove.
  Against a correct drainer: 10 iterations × 3 runs, no failure, no
  intermittency.
- **Case 3 is not vacuous.** Both halves red on the relay text being *present*
  (`[[ "$output" != *"gitlore-relay agent a1"* ]]` failed), which is only
  reachable if the unkeyed run got past its baseline guard and into its current
  drain branch. No mutation needed: the red itself is the proof. The cases also
  assert the run still emits its own report, so an early exit after GREEN would
  fail them.
- **No dead assertions.** Every assertion in cases 1, 2 and 4 executes and
  passes against the probe drainer, including the ones sitting below each case's
  RED death point. The four session-start relay cases likewise pass against the
  probe session-start.
- **Case 7's mutation proof, re-run independently.** Replacing
  `case "$tag" in sync|compose) ;; *) return 1 ;; esac` with an accept-all
  `case "$tag" in sync|compose|*) ;; esac` reds the case at `[ "$rc" -ne 0 ]`.
  The case asserts both the non-zero return and that
  `find … -name 'gitlore-relay-*'` is empty, which covers temps: a refused
  write's leftover would be `…-bogus.tmp`, still matched by that glob.
  `scripts/lib/index-sync.sh` restored byte-identical, case green again.
- **The 7-day sweep fixture** uses the BSD `date -v-10d` / GNU `date -d` shape
  with the `2>/dev/null` justified inline as the detection mechanism, which is
  what `.claude/rules/shell.md` allows.
- **`feed()` gaining `session_id: test-session`** breaks nothing:
  `index-compose.sh` reads `session` for the relay write and nothing else
  (grepped), and the full suite passes around the intended reds.
- **The distribution case matches the house shape** —
  `jq … | select(test("relay-drain")) | length` is 1, plus `[ -x ]` — rather
  than inventing a bespoke one, and `hooks.json` registers the hook once under
  `PostToolBatch` with no matcher, like its five siblings.
- **Shell rules.** No bare `!` in any test body (`run !` where negation is
  wanted); no `[[ ]]` used as a command whose failure is swallowed; no `ls`
  pipelines; the one added `2>/dev/null` is the pre-existing `date` probe; the
  helper enumerates with `find … -print` over names this library sanitizes and
  refuses a multi-line result rather than splitting it. bash 3.2 safe: no
  arrays, no `${var,,}`, `case` over `[[ =~ ]]`. Every `find` predicate used —
  `-maxdepth`, `-type`, `-name`, grouping, `-mtime` — is BSD- and bfs-safe.
- **`shellcheck -x`** clean on all four suites and both helpers.

## Final state

`scripts/run-bats.sh` over the four files, after the fixes:

| run | result |
| --- | --- |
| before any fix | 141 passed, 7 failed |
| after the fixes | 141 passed, 7 failed |

The reds are the same seven cases, each failing on a named assertion and none an
ERROR:

| case | file:line | assertion |
| --- | --- | --- |
| an unkeyed index-sync run leaves a marker in place | `tests/index_sync.bats:773` | `[[ "$output" != *"gitlore-relay agent a1"* ]]` |
| an unkeyed compose run leaves a marker in place | `tests/cc_hook_index_compose.bats:289` | `[[ "$output" != *"gitlore-relay agent a1"* ]]` |
| concurrency: both reporting hooks reach relay-drain.sh exactly once per keyed batch | `tests/cc_hook_index_compose.bats:327` | `[ "$n_sync" -eq 1 ]`, `n_sync=0` |
| relay-drain.sh delivers with no baseline (M2) | `tests/cc_hook_index_compose.bats:359` | `[[ "$sysmsg" == *"M2 SYSMSG"* ]]` |
| relay-drain.sh with session S1 leaves an S2 file standing | `tests/cc_hook_index_compose.bats:387` | `[[ "$sysmsg" == *"S1 BODY"* ]]` |
| session-start drains its own session's marker | `tests/cc_hook_session_start.bats:380` | `[[ "$sysmsg" == *"S1 SYSMSG BODY"* ]]` |
| session-start sweeps a relay file older than 7 days | `tests/cc_hook_session_start.bats:422` | `[ ! -e "$old_marker" ]` |

Whole unit suite (`just test-unit`): **839 passed, 7 failed** — the seven above
and nothing else, which is what confirms the `setup_tmp_repo` change in fix 2
costs no other suite anything. The four other suites that invoke session-start
(`tier_divergence`, `tier_discovery`, `merge_memory`, `cc_hook_worktree_remove`)
were additionally run against a session-start carrying `payload=$(cat)`:
**73 passed, 0 failed**, which is the direct proof that the fix reaches all 45
bare call sites rather than the two the RED author converted.

`just lint`: `lint-shell: 137 files clean`.

## Files touched by this review

- `tests/cc_hook_index_compose.bats` — fixes 1, 4
- `tests/cc_hook_session_start.bats` — fix 4
- `tests/index_sync.bats` — fix 5
- `tests/plugin_distribution.bats` — fix 6
- `tests/helpers/fixtures.bash` — fix 3
- `tests/helpers/setup.bash` — fix 2

Unchanged, and verified unchanged after their probes:
`scripts/cc-hooks/relay-drain.sh`, `scripts/lib/index-sync.sh`,
`scripts/cc-hooks/session-start.sh`, `scripts/cc-hooks/index-sync-post.sh`,
`scripts/cc-hooks/index-compose.sh`, `hooks/hooks.json`.
