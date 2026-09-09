# Item 3.1 slice 5 — RED

Three cases added: two in `tests/cc_hook_index_compose.bats`, one in
`tests/index_sync.bats`. All SUTs are untouched — `git status --porcelain`
shows only the two `.bats` files modified. Nothing committed.

---

## 1 · `a failed relay write tells the subagent it was not staged` (compose hook)

Reds by **absence** — the not-staged line does not exist anywhere in
`index-compose.sh` today, so the case's own last assertion is what fails.

```
not ok 1 a failed relay write tells the subagent it was not staged
# (in test file tests/cc_hook_index_compose.bats, line 491)
#   `[[ "$output" == *"could not be staged for the parent session"* ]]' failed
```

Died on: the substring check against `hookSpecificOutput.additionalContext`.

Non-vacuity: everything upstream of the death point ran and held —
`[ "$status" -eq 0 ]`, the `jq -e` parse implied by `run jq -r ...` returning
0 twice, the `systemMessage` still carrying `recomposed tier pointers`
(pinning that today's `|| true` costs only the relay, not the subagent's own
report — the fact slice 4 already established), and
`[ "$output" != "null" ]` on `additionalContext` (today's ctx is the
compose-success text, non-empty, so the null-guard is exercised as true
rather than skipped). Only the final line — the one this slice adds — fails.
Fixture: `mkdir "$(gitlore_relay_marker_file memory a1)"`, the slice-4
directory squat, driven keyed.

---

## 2 · `an unkeyed run leaves a non-marker alone` (compose hook)

**Born green** — `gitlore_relay_drain`'s `-type f` (slice 1, committed)
already skips the squat directory, so this case is a regression pin, not a
red-by-absence.

```
1..1
ok 1 an unkeyed run leaves a non-marker alone
```

Proven non-vacuous in two steps, per the dispatch's note that dropping
`-type f` alone reds a *different* existing case first.

**Step 1 — the named mutation.** `-maxdepth 1 -type f -name 'gitlore-relay-*'`
→ `-maxdepth 1 -name 'gitlore-relay-*'` in `scripts/lib/index-sync.sh:214`.
This reds my case, but at its status check, not at either of the two
assertions the case exists for:

```
not ok 1 an unkeyed run leaves a non-marker alone
# (in test file tests/cc_hook_index_compose.bats, line 506)
#   `[ "$status" -eq 0 ]' failed
```

Confirmed this is the *same* mechanism that reds the pre-existing sibling
case, as the dispatch predicted:

```
not ok 1 an unkeyed run survives a non-file squatting on a marker name
# (in test file tests/cc_hook_index_compose.bats, line 454)
#   `[ "$status" -eq 0 ]' failed
```

With `-type f` gone, `find` also matches the squat directory; the drain's
bare `rm -f "$marker"` then fails on a directory and, uncaught, aborts the
whole hook under `set -euo pipefail` before it emits any JSON — so `feed`
itself fails, and both cases die on the same status assertion. This proves
the mutation reds the case, but says nothing about the `[ -d "$squat" ]` and
no-framing assertions specifically, since the abort happens before either
runs.

**Step 2 — an isolating mutation**, to reach past the abort and exercise
those two assertions on their own. Same `-type f` drop, plus
`rm -f "$marker"` → `rm -f "$marker" || true` at `index-sync.sh:243` (mirrors
the tolerant-read pattern already used one line above it), so the directory
match no longer aborts the hook:

```
not ok 1 an unkeyed run leaves a non-marker alone
# (in test file tests/cc_hook_index_compose.bats, line 508)
#   `[[ "$output" != *"gitlore-relay agent a1"* ]]' failed
```

This shows `[ "$status" -eq 0 ]` and `[ -d "$squat" ]` both held true under
this mutation (rm -f on a directory fails silently but no longer propagates,
so the squat survives) and the framing check is what fires — the squat
directory got folded and framed once `-type f` no longer excluded it. Both
of the case's substantive assertions are therefore live, not dead code.

Both mutations applied to `scripts/lib/index-sync.sh` and restored via
`git checkout --`; `git diff --stat -- scripts/lib/index-sync.sh` empty
after each restore, confirmed before moving to the next step.

---

## 3 · `the drain survives a gitdir it cannot write` (index_sync.bats)

Reds by **absence of the fix** — `gitlore_relay_drain`'s bare `rm -f` still
propagates when the gitdir itself is unwritable, contra its own "Always
returns 0" doc line (item-3-1-s4-code-review.md §6).

```
not ok 1 the drain survives a gitdir it cannot write
# (in test file tests/index_sync.bats, line 1255)
#   `[ "$status" -eq 0 ]' failed
```

Died on: the status check on the synthetic caller (`set -euo pipefail`,
source the lib, call the drain bare, `printf "OWN REPORT\n"` — the hooks'
own shape, same idiom as the pre-existing "an unreadable marker costs the
relay, not the hook" case).

Non-vacuity: `run gitlore_relay_write memory a1 "S" "C"` and its
`[ "$status" -eq 0 ]` ran and held (the marker exists before the gitdir is
chmod'd), and `chmod 0500 "$gitdir"` ran before the synthetic caller — read
+ execute survive (so `find` and `awk` inside the drain still work; the
marker itself is read, not written), only write on the directory is gone,
which is what makes `rm -f "$marker"` specifically the failing operation
rather than some earlier step. The second assertion
(`[[ "$output" == *"OWN REPORT"* ]]`) is positioned after the death point and
did not execute this run — its own non-vacuity rests on the GREEN phase,
where a fixed drain (`rm -f "$marker" || true`) lets the caller reach its own
`printf` and the substring assertion actually fires true.

Mode restore is guarded (`[ -e "$gitdir" ] && chmod 0700 "$gitdir"`) and runs
unconditionally after `run bash -c ...` (which does not itself abort the test
body, since `run` disables errexit for its own command) — confirmed
`teardown_tmp_repo`'s `rm -rf "$TMP_REPO"` succeeds afterward with no stray
`gitlore-test.*` directory left in `$TMPDIR` across two consecutive full
suite runs (below).

Skipped under root via `[ "$(id -u)" -eq 0 ] && skip ...`, matching the
neighbouring permission cases in this file.

---

## Two consecutive full runs, identical results

```
./scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats
```

Run 1:
```
not ok 63 the drain survives a gitdir it cannot write
# (in test file tests/index_sync.bats, line 1255)
#   `[ "$status" -eq 0 ]' failed
not ok 102 a failed relay write tells the subagent it was not staged
# (in test file tests/cc_hook_index_compose.bats, line 491)
#   `[[ "$output" == *"could not be staged for the parent session"* ]]' failed

bats: 108 passed, 2 failed
```

Run 2: byte-identical pass/fail set and line numbers. No
`/tmp/gitlore-test.*` (or `$TMPDIR` equivalent) directory survived either
run — checked with `find "${TMPDIR:-/tmp}" -maxdepth 1 -name 'gitlore-test.*'`
immediately after each, both empty.

`git status --porcelain` after both runs: only `tests/cc_hook_index_compose.bats`
and `tests/index_sync.bats` modified; the four SUT files untouched.

---

## Checks that passed, by name

- `shellcheck -s bash tests/index_sync.bats tests/cc_hook_index_compose.bats` — clean.
- `./scripts/lint-shell.sh` — **137 files clean**.
- `./scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats`,
  run twice — **108 passed, 2 failed** both times, same two cases, same line
  numbers, no stray fixture directory left behind either time.
- Case 1 (`a failed relay write tells the subagent it was not staged`) —
  reds on its own last assertion; every prior assertion in the body
  confirmed to run and hold.
- Case 2 (`an unkeyed run leaves a non-marker alone`) — green against the
  committed SUT; reds under the named `-type f` mutation (via the status
  check, alongside the pre-existing sibling case); reds under an isolating
  mutation (`-type f` dropped + `rm -f || true`) specifically on its framing
  assertion, proving `[ -d "$squat" ]` and the no-framing check are both
  live. Both mutations applied and restored; `git diff --stat -- scripts/lib/index-sync.sh`
  empty after each.
- Case 3 (`the drain survives a gitdir it cannot write`) — reds on its own
  status assertion against the caller's synthetic `set -euo pipefail` shape;
  the preceding `gitlore_relay_write` call and its status check confirmed to
  run and hold before the gitdir is made unwritable.
- `git status --porcelain` — only the two `.bats` files modified; nothing
  staged, nothing committed.
