# Item 3.1, slice 3 — test review (RED phase)

Scope: `tests/cc_hook_session_start.bats`. The SUT was mutated in place for
measurement and restored; `git diff -- scripts/cc-hooks/session-start.sh` is
empty and its sha matches the pre-review copy. Nothing committed, no `just`
recipe run.

Verdict: **the two cases are sound and non-vacuous.** Every one of their nine
assertions is killed by at least one mutation. Two hardenings applied, both
mutation-backed. Three findings reported for GREEN, none blocking.

## Q1 — the unreachability claim holds, measured

The RED report's argument is correct, and stronger than it states.

**Measurement.** `emit_session_json` was instrumented in a copy of the SUT to
log, at each call, whether `$sysmsg` was empty and which line called it. Every
suite that runs the hook was then driven: `cc_hook_session_start`,
`cc_hook_worktree_remove`, `merge_memory`, `push_rejection_discriminator`,
`tier_discovery`, `tier_divergence`, `integration_clone_restore`,
`integration_gitlink_staging`, `integration_happy_path`,
`integration_replay_guard`.

```
     50 NONEMPTY callsite=380    # the final emit (pristine :379)
      1 NONEMPTY callsite=208    # the ff-failure early exit (pristine :207)
      1 NONEMPTY callsite=203    # the diverged early exit (pristine :202)
total: 52, EMPTY: 0
```

All three call sites are exercised, including the two early-exit ones the report
named, and no fixture in the repository reaches any of them with `$sysmsg`
empty.

`add_sysmsg` cannot be reached with an empty argument on any of the four
`gitlore_memory_dirty` branches: each passes a non-empty string literal, and the
ff-failure branch's argument is a literal prefix concatenated with `$merge_err`,
so it is non-empty whatever git said.

**The case is also not needed for what it was specified to catch.** The runbook
justifies it by two bugs — a fold after `emit_session_json`, and one appending
to the wrong variable. Both red the *positive* on its first assertion (M4, M6
below). So the third case is redundant as well as unreachable.

**The fragility, stated precisely.** It is narrower than "a silent branch
strands the relay". A correct fold makes `$sysmsg` non-empty by itself, so the
relay is emitted even when it is the only news. What today's code genuinely
cannot distinguish from correct is a fold *nested inside* an `[ -n "$sysmsg" ]`
guard — mutation M8, which passes both cases and is behaviour-identical to the
correct fold while all four dirty branches report, and drops the relay silently
the day one stops. That is the residual the missing case would have covered.

Handling: recorded in the test file's existing comment block (the durable record
of why the case is absent), and reported here for GREEN, which should carry a
one-line comment at the fold site saying the relay must not be conditioned on
`$sysmsg` already being non-empty. A case pinning "at least one dirty branch
always reports" was considered and rejected: it would pin an unrelated behaviour
to protect an assumption the fold should simply not make.

## Q2 — the negative discriminates; full mutation table

Every mutation was written into `scripts/cc-hooks/session-start.sh`, run, and
the file restored from a saved pristine copy. The whole table was re-run against
the final test file, so every line number below is current. Case 1 =
`session-start drains a stranded relay marker`, case 2 =
`session-start with no marker emits no relay framing`.

| # | Mutation | Case 1 | Case 2 | Kills |
|---|---|---|---|---|
| M0 | correct fold before the final emit (`drain`, `-n` guard, both channels) | pass | pass | — (must be green) |
| M1a | fold with **no `-n` guard**: `add_sysmsg "$GITLORE_RELAY_SYSMSG"` + unguarded ctx join | pass | **pass** | nothing — see Finding 1 |
| M1b | framing emitted **unconditionally** (fold synthesizes its own framing line) | pass | red `:397` | `[[ "$sysmsg" != *"$RELAY_FRAMING"* ]]` |
| M2 | appends to `sysmsg` but **not** `protocol_ctx` | red `:375` | pass | `[[ "$ctx" == *"STRANDED CTX BODY"* ]]` |
| M3 | appends to `protocol_ctx` but **not** `sysmsg` | red `:373` | pass | `[[ "$sysmsg" == *"STRANDED SYSMSG BODY"* ]]` |
| M4 | correct fold placed **after** `emit_session_json` | red `:373` | pass | sysmsg body |
| M5 | folds both channels correctly but **never removes the marker** | red `:377` | pass | `[ ! -f "$marker" ]` |
| M6 | drains, appends to the **wrong variable** (`tier_guidance`, already consumed) | red `:373` | pass | sysmsg body |
| M8 | correct fold nested inside `[ -n "$sysmsg" ]` | pass | **pass** | nothing — see Q1 fragility |
| M9 | folds body but **strips the framing line from sysmsg** | red `:374` | pass | `[[ "$sysmsg" == *"$RELAY_FRAMING a1 ---"* ]]` |
| M10 | folds the framing line but **empty body** on both channels | red `:373` | pass | sysmsg body |
| M11 | folds body but **strips the framing line from ctx** | red `:376` | pass | `[[ "$ctx" == *"$RELAY_FRAMING a1 ---"* ]]` |
| M12 | unconditional framing on **ctx only** | red `:373` | red `:398` | `[[ "$ctx" != *"$RELAY_FRAMING"* ]]` |
| M13 | `sysmsg=""` before the emit, so `systemMessage` is omitted from the JSON | red `:373` | red `:395` | `[ "$sysmsg" != "null" ]` (added) |
| M14 | `emit_session_json` emits no `additionalContext` key | red `:373` | red `:396` | `[ "$ctx" != "null" ]` (added) |

Assertion coverage — **no assertion in either case survives every mutation**:

| Assertion | Killed by |
|---|---|
| `:373` `[[ "$sysmsg" == *"STRANDED SYSMSG BODY"* ]]` | M3, M4, M6, M10, M12, M13, M14 |
| `:374` `[[ "$sysmsg" == *"$RELAY_FRAMING a1 ---"* ]]` | M9 |
| `:375` `[[ "$ctx" == *"STRANDED CTX BODY"* ]]` | M2 |
| `:376` `[[ "$ctx" == *"$RELAY_FRAMING a1 ---"* ]]` | M11 |
| `:377` `[ ! -f "$marker" ]` | M5 |
| `:395` `[ "$sysmsg" != "null" ]` | M13 |
| `:396` `[ "$ctx" != "null" ]` | M14 |
| `:397` `[[ "$sysmsg" != *"$RELAY_FRAMING"* ]]` | M1b |
| `:398` `[[ "$ctx" != *"$RELAY_FRAMING"* ]]` | M12 |

The two channels are separately pinned in the sense `green-is-not-evidence.md`
requires: M2 reds the ctx body assertion while both sysmsg assertions above it
stay green. The mirror direction (M3) is masked by bats' errexit — the sysmsg
assertions come first, so the test dies before reaching the ctx ones — which is
inherent to a single test body and is why the per-assertion kills above are the
evidence rather than the pass/fail pair.

### Fixes applied

Both are one-liners in case 2, each backed by a mutation that reds it.

1. `[ "$sysmsg" != "null" ]` / `[ "$ctx" != "null" ]` before the two
   refutations. `jq -r` prints the literal string `null` for an absent key, so
   both refutations passed on a JSON that had dropped the channel entirely — the
   negative would have gone on counting as green while watching nothing. This is
   `green-is-not-evidence.md`'s "check that the observable the negative watches
   is one the positive path actually produces", applied to the channel rather
   than the string. Proven by M13 and M14: without the guards both mutations
   leave case 2 green.

2. The comment block recording why the third case is absent now carries the
   measurement (52 emits, three call sites, zero empty) and the second reason
   (case 1 already discriminates both bugs the third case was specified to
   catch), plus the M8 residual it does not cover.

## Q3 — mechanical checks

- **Case 1 fails on an assertion, not an error.** Confirmed:
  `` `[[ "$sysmsg" == *"STRANDED SYSMSG BODY"* ]]' failed `` at `:373`. The
  fixture guards ahead of it (`[ "$write_status" -eq 0 ]`, `[ -f "$marker" ]`,
  `[ "$status" -eq 0 ]`) all pass, so `gitlore_relay_write` and
  `gitlore_relay_marker_file` resolve and the hook exits 0 — the red is the
  absent drain, nothing else.
- **`RELAY_FRAMING` is defined test-side** at `:15` of the test file, hand-typed
  with a comment saying why it is not sourced from `scripts/lib/index-sync.sh`.
  The positive genuinely pins the wording: M9 and M11 strip the framing line and
  red `:374` and `:376` respectively. Note for the record — the repo already has
  `tests/helpers/triggers.bash` for this exact pattern (`GITLORE_T_*`, one entry
  per literal, each naming the positive that pins it). The runbook directs
  top-of-test-file placement, and the concern triggers.bash exists to solve
  (positive and negative in different files drifting apart) does not arise here
  since both live in this file, so this was left as the runbook specifies.
- **Assertions past the death point.** Case 1's assertions after `:373` never
  execute at RED. Rather than reordering, each was killed by its own mutation
  with all its predecessors passing — see the coverage table. `:374` (M9),
  `:375` (M2), `:376` (M11) and `:377` (M5) each red as the *first* failure in
  their run, which proves both that they execute and that they discriminate.
  Case 2's `:398` is likewise proven reachable by M12, which reds it with
  `:395`, `:396` and `:397` all green.
- **The two cases differ only in whether a marker exists.** Both call
  `make_parent_with_memory`, both `mkdir -p .claude` and write the same
  `settings.json`, both invoke the hook the same way. The only fixture
  divergence is case 1's `gitlore_relay_write`. That write lands in the memory
  gitdir, not the work tree, so it cannot flip which `gitlore_memory_dirty`
  branch fires; the probe confirms both cases reach the same final emit call
  site.
- **Marker path.** `gitlore_relay_marker_file memory a1` returns an absolute
  path (`$TMP_REPO/.git/modules/gitlore-memory/gitlore-relay-a1`), so
  `[ -f ]`/`[ ! -f ]` are cwd-independent, and the pairing is real: `:366`
  proves the path resolves before `:377` asserts its absence. It lives under
  `$TMP_REPO`, which `setup_tmp_repo` mints fresh per test, so no leakage into
  case 2 — the fixture template is copied *before* the write.
- **Whitespace and quoting.** Every expansion in both cases is quoted; nothing
  splits on whitespace, no command substitution is left bare, no array or `IFS`
  handling. `[[ … == *"$X"* ]]` quotes the literal side of every pattern.
- **bash 3.2 / BSD.** The new cases use only `[[ … == … ]]`, `[ … ]`, `printf`,
  `mkdir -p`, `jq` and bats builtins. No `sed`, `grep`, `find`, `stat` or
  `mktemp`, so nothing for `tests/helpers/bsd-stubs.bash` to catch; the two
  added assertions are POSIX `[` string comparisons.
- **`run` vs bare calls under errexit.** The one bare helper call
  (`gitlore_relay_write`) sits in an `if`, which suspends errexit for it, and
  its status is captured and asserted at `:364` — the runbook's "capture the
  return status explicitly" requirement, met in a form equivalent to `run`.
- **Substring vs exact.** The four content assertions are substrings, but each
  is a string only the relay can put on that channel, and the mutation table
  shows each fails alone. `STRANDED SYSMSG BODY` and `STRANDED CTX BODY` are
  distinct, so a fold that crossed the channels reds (M2/M3).

## Findings for GREEN — none blocking

1. **The `-n` guard on the fold is unpinned (M1a).** A fold that appends the
   drained channels unconditionally passes both cases: with no marker the drain
   sets both variables empty, `add_sysmsg ""` emits no framing, and the negative
   watches the framing literal, not blank-line pollution. The cost is a trailing
   empty paragraph appended to `systemMessage` and to `additionalContext` on
   every marker-less session — which is every ordinary session. Both committed
   PostToolBatch folds guard on `[ -n … ]` (`index-compose.sh`); GREEN should
   match that shape. Pinning it would mean asserting message formatting, which
   is beyond what the runbook specifies for this slice, so it is reported rather
   than tested.

2. **A fold nested inside `[ -n "$sysmsg" ]` is indistinguishable from correct
   (M8).** See Q1. Worth a comment at the fold site.

3. **The early-exit emit sites are not covered, and the gap is benign.**
   Measured: with the correct fold (M0) placed before the final emit, a diverged
   store with a stranded marker emits `gitlore: memory diverged from live…` and
   leaves the marker on disk undrained. Neither slice-3 case reaches that path.
   It self-heals — the marker survives to the session after `/gitlore:resolve`,
   which is what "SessionStart is the backstop" means — so the report is delayed
   until divergence is fixed, never lost. Whether GREEN should also drain on the
   two early exits is a design call the runbook does not make; flagging it
   rather than writing a case that presupposes an answer.

## Checks that passed, by name

- `scripts/run-bats.sh tests/cc_hook_session_start.bats` — 22 passed, 1 failed;
  the failure is case 1 at `:373` on its first content assertion, which is the
  intended RED state. Case 2 passes, and its pass is backed by the four
  mutations that red it.
- `shellcheck -s bash tests/cc_hook_session_start.bats` — clean.
- `scripts/lint-shell.sh` — 137 files clean.
- `git diff -- scripts/cc-hooks/session-start.sh` — empty, and the file's sha
  matches the copy taken before the first mutation
  (`a65188bedf8c653f3f6219627ecb10e80f8d9881`).
- `git status --porcelain` — only `tests/cc_hook_session_start.bats` modified,
  plus the two untracked report files. The temporary probe suite used for the
  divergence and marker-path measurements was removed.
- Mutation matrix — 15 mutations, all 9 assertions in the two cases killed, no
  vacuous assertion.
