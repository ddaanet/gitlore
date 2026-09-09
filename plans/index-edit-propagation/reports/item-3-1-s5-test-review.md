# Item 3.1 slice 5 — test review (RED phase)

Reviewed: `tests/cc_hook_index_compose.bats` and `tests/index_sync.bats` as
submitted by `reports/item-3-1-s5-red.md`. Every claim below was measured, not
read. No SUT file is left modified; `git diff -- scripts/` is empty.

**Headline: all three cases pass under a simulated GREEN built to the runbook's
own proposal, and none of them is a case that could never have passed.** The
defect class that cost this item two cycles does not recur here. One real defect
found and fixed: the companion case's refutation was satisfied by an empty
`$output`, so a regression that silenced the compose report would have made it
vacuous rather than red — it leaned on the sibling slice-4 case for its
non-vacuity, which is precisely the case this slice makes redundant. Fixed with
a paired positive on the same capture, placed *after* the refutation per
`green-is-not-evidence`.

One finding reported and **not** acted on, because it is the orchestrator's
call: the pre-existing slice-4 case
`an unkeyed run survives a non-file squatting on a marker name` stops
discriminating anything once `rm -f || true` lands (§4).

The `rm -f "$marker" || true` fix may ship as specified. Its companion does
restore the `-type f` coverage that token removes — measured, §2.

---

## 1. The simulated GREEN

Built in place from the runbook's slice 5 entry and `item-3-1-s4-code-review.md`
§1/§6, verbatim: the `if !` not-staged block in both hooks, and
`rm -f "$marker" || true` in the drain. Full text of what was applied:

`scripts/cc-hooks/index-compose.sh`

```sh
    if ! gitlore_relay_write "$mempath" "$agent_id" "$GITLORE_COMPOSE_SYSMSG" "$GITLORE_COMPOSE_CTX"; then
      GITLORE_COMPOSE_CTX="${GITLORE_COMPOSE_CTX:+$GITLORE_COMPOSE_CTX

}gitlore: the report above could not be staged for the parent session — the relay marker could not be written. A hook's output inside a subagent reaches no one else, so repeat it in your reply or it is lost."
    fi
```

`scripts/cc-hooks/index-sync-post.sh`

```sh
    if ! gitlore_relay_write "$mempath" "$agent_id" "$sysmsg" "$ctx"; then
      if [ -n "$ctx" ]; then ctx="$ctx

"; fi
      ctx="${ctx}gitlore: the report above could not be staged for the parent session — the relay marker could not be written. A hook's output inside a subagent reaches no one else, so repeat it in your reply or it is lost."
    fi
```

`scripts/lib/index-sync.sh`: `rm -f "$marker"` → `rm -f "$marker" || true`.

**Result: `110 passed, 0 failed`.** All three new cases green, and nothing else
regressed. Question 1 item 1 answered: no case in this slice could fail to pass
at GREEN.

Restored with `git checkout -- scripts/` after every mutation; `git diff --
scripts/` verified empty before the final runs and again at hand-off.

---

## 2. `an unkeyed run leaves a non-marker alone` does restore the `-type f` coverage

Question 1 item 2 is the one that decides whether the `rm -f || true` fix may
ship. It does.

Dropping `-type f` **from the simulated GREEN tree** (M-A below) reds the
companion, and reds it on the framing assertion — the assertion the case exists
for — not on an upstream status check:

```
not ok 103 an unkeyed run leaves a non-marker alone
# (in test file tests/cc_hook_index_compose.bats, line 514)
#   `[[ "$output" != *"gitlore-relay agent a1"* ]]' failed

bats: 109 passed, 1 failed
```

It is the **sole** red under that mutation. This is a strictly better result than
the RED report's step 2, which had to stack two mutations to reach past the abort:
against the real GREEN tree one token does it, and the death point is the right
assertion first time.

`[ -d "$squat" ]` is separately live. It needs its own mutation, since a drain
that merely *enumerates* the squat still cannot remove it with `rm -f`. Under
M-D — `-type f` dropped **and** `rm -f` widened to `rm -rf` — the case reds at
line 510 on `[ -d "$squat" ]`, one assertion before the framing check.

So both substantive assertions of the companion discriminate, each against its
own mutation, against the tree GREEN will actually produce. **The fix must not be
held back.**

---

## 3. Case 3's `OWN REPORT` assertion fires true under GREEN, and reds without it

Question 1 item 3. The RED report is correct that this assertion sits behind a
death point and never executed in the RED run. Both halves measured:

- **Fires true**: under the simulated GREEN the case passes, which it cannot do
  without executing line 1260.
- **Reds against a GREEN that returns 0 without reaching the caller's own
  report**: mutation M-C replaces the fix with `rm -f "$marker" || exit 0`, so
  the drain absorbs the failure but exits the caller before its `printf`. The
  case reds, and reds on that assertion alone:

```
not ok 63 the drain survives a gitdir it cannot write
# (in test file tests/index_sync.bats, line 1256)   [pre-fix numbering]
#   `[[ "$output" == *"OWN REPORT"* ]]' failed

bats: 109 passed, 1 failed
```

`[ "$status" -eq 0 ]` is satisfied by that mutation (the caller exits 0), so the
`OWN REPORT` line is the only thing standing between a real fix and a drain that
swallows its caller. It is load-bearing.

---

## 4. The slice-4 squat case becomes dead weight — reported, not deleted

Question 1 item 4. `an unkeyed run survives a non-file squatting on a marker
name` (`tests/cc_hook_index_compose.bats:444`) no longer discriminates anything
once `rm -f || true` lands. Measured three ways:

| mutation, applied to the simulated GREEN | slice-4 squat case | new companion |
|---|---|---|
| `-type f` dropped (M-A) | **green** | **red**, on the framing assertion |
| `-type f` → `-type d` (M-B) | **green** | **red**, on the framing assertion |
| `-type f` dropped + `rm -rf` (M-D) | red, but on its *cleanup* `rmdir "$squat"` at line 458, not on an assertion | **red**, on `[ -d "$squat" ]` |

M-A is `item-3-1-s4-code-review.md`'s M7c confirmed independently: the case's
only historical discrimination was M7, and the fix retires it. M-B is the
interesting one — the drain enumerates the squat and frames it, and the slice-4
case is *still* green, because framing a non-marker is not something it asserts
about. M-D reds it for the wrong reason entirely: a cleanup command failing, not
a claim about behaviour.

Its residual unique content is `[[ "$output" == *"recomposed tier pointers"* ]]`
— "the hook still emits its own report over a squat fixture". After the fix,
nothing can break that without also breaking the companion's `[ "$status" -eq 0 ]`,
and the companion now carries that same assertion itself (§5). **It is redundant.
Not deleted — that is the orchestrator's call**, and there is a weak argument for
keeping it: it is the only case that reads the compose report out of the JSON
with `jq` over this fixture rather than as a raw-JSON substring.

---

## 5. Defect found and fixed — the companion's refutation could go vacuous

`tests/cc_hook_index_compose.bats`, `an unkeyed run leaves a non-marker alone`.

As submitted the body was: `[ "$status" -eq 0 ]`, `[ -d "$squat" ]`,
`[[ "$output" != *"gitlore-relay agent a1"* ]]`. **An empty `$output` satisfies
all three.** `index-compose.sh` emits its JSON only inside
`if [ -n "$GITLORE_COMPOSE_SYSMSG" ]` and otherwise writes nothing at all and
exits 0 — so "the hook produced no report" is a reachable state of this SUT, not
a hypothetical, and in it the case passes while proving nothing. This is
`green-is-not-evidence`'s *path staleness*: "Pair each negative with a positive
over the **same fixture**." The submitted case had no positive of its own; it
borrowed the sibling case's — the very case §4 shows the slice retires.

Measured before the fix: mutation M-E renames the compose report literal
(`recomposed tier pointers` → `MUTATED tier pointers` in
`scripts/lib/index-compose.sh:717`), which empties nothing but is the cheapest
proxy for a silenced report. Eight cases red under it; the companion, as
submitted, was **not** among them.

**Fix applied** — a paired positive on the same capture:

```sh
  [[ "$output" != *"gitlore-relay agent a1"* ]]
  [[ "$output" == *"recomposed tier pointers"* ]]
```

After the fix, M-E reds the companion at line 521 on the new assertion.

**Ordering.** `green-is-not-evidence` is explicit that a negative sitting behind
a positive runs only when the positive already held, and says to place the
negative ahead of it. I placed the positive **last** accordingly, which also
gives the better diagnosis: on a run that breaks both — output that has lost the
compose report *and* gained a framing line — the reported failure is the
refutation, which is what this case is named for. Confirmed both ways: under M-A
the reported line is the refutation (514), under M-E it is the anchor (521).

Also added: the `--separate-stderr` rationale comment the case was missing (its
two siblings both carry one), and a note that the refutation is deliberately over
the whole JSON rather than one jq-extracted channel, since the unkeyed fold puts
the framing line on **both** `systemMessage` and `additionalContext` and a
channel-scoped refutation would miss half of it.

---

## 6. Question 2 — the not-staged literal

Four checks, all pass.

1. **It is a substring of the wording GREEN will write.** The runbook's slice 5
   entry defers the wording to `item-3-1-s4-code-review.md` §1, which gives it
   verbatim for both hooks: "gitlore: the report above **could not be staged for
   the parent session** — the relay marker could not be written. A hook's output
   inside a subagent reaches no one else, so repeat it in your reply or it is
   lost." The asserted literal is contained in it exactly, and the simulated
   GREEN built from that text turns the case green.
2. **Distinctive.** `grep -rn "could not be staged"` over the repo returns three
   other producers — `scripts/resolve.sh:228`, `scripts/add-tier.sh:243`,
   `scripts/lib/resolve.sh:1579` — and all three say "pointer could not be
   staged" / "could not be staged in the memory store". None carries "for the
   parent session", and none of them is reachable from either hook's stdout.
   The literal cannot be satisfied by another line of either channel.
3. **Held test-side.** Written inline in the assertion, not sourced from the lib
   and not derived from any production variable — so a GREEN that changes the
   wording turns this red rather than moving both sides together. This case is
   the *positive* on the literal, so no shared-variable indirection is called
   for: the runbook's one-variable rule applies to the SessionStart framing
   pair (slice 3), where a negative also has to move with the wording.
4. **The right channel is pinned.** The assertion is on the value `jq -r`
   extracts from `.hookSpecificOutput.additionalContext`, so a GREEN that put the
   line on `systemMessage` instead — the channel `subagent-hook-output-probe.md`
   measured as reaching no one — reds this case. That is the slice's whole
   argument, and it is pinned rather than assumed.

The `[ "$output" != "null" ]` guard on line 490 is weaker than the runbook's
framing suggests, since what follows it is a positive match rather than a
refutation — `jq -r` printing `null` fails the positive anyway. It is correct,
documented, and costs nothing; left as written.

---

## 7. Question 3 — mechanical checks

**Cases 1 and 3 failed on an assertion, not an error.** Confirmed from the TAP
log, twice, at hand-off:

```
not ok 63 the drain survives a gitdir it cannot write
# (in test file tests/index_sync.bats, line 1259)
#   `[ "$status" -eq 0 ]' failed
not ok 102 a failed relay write tells the subagent it was not staged
# (in test file tests/cc_hook_index_compose.bats, line 491)
#   `[[ "$output" == *"could not be staged for the parent session"* ]]' failed
```

Both are `bats`' assertion form, naming the failing expression. Neither is a
"command not found", a `jq` parse error, or a non-zero from a fixture step.

**Assertions after a death point — the full enumeration.**

| case | death point in RED | assertions after it, never executed | verified by |
|---|---|---|---|
| 1 · `a failed relay write tells the subagent it was not staged` | line 491, the **last** assertion | none. `rmdir "$squat"` (492) is cleanup, not an assertion; it does run under the simulated GREEN, where the case is green | simulated GREEN, 110/0 |
| 2 · `an unkeyed run leaves a non-marker alone` | none — born green | none; every assertion executes on every run | M-A reds 514, M-D reds 510, M-E reds 521 — one mutation per assertion |
| 3 · `the drain survives a gitdir it cannot write` | line 1259 | line 1260, `[[ "$output" == *"OWN REPORT"* ]]` | M-C (§3) |

Case 3's guarded `chmod` restore at line 1257 is *before* the death point and did
execute in the RED run — confirmed by the absence of any surviving fixture tree
(below). No assertion in any of the three cases is unreachable at GREEN.

**Fixture hygiene.** Case 3 makes the memory store's gitdir mode 0500. Three
things checked:

- **The restore runs on every path as written.** The only statement between
  `chmod 0500` (1233) and the restore (1257) is `run bash -c …`, and bats' `run`
  never aborts the body regardless of the command's status. There is no path
  through this case that skips the restore.
- **The hazard is real, so the ordering is load-bearing.** Measured by inserting
  a temporary `false` immediately after the `chmod 0500` and running the case
  alone: `teardown_tmp_repo`'s `rm -rf` then fails on **every** entry in the
  gitdir (`gitlore-relay-a1`, `config`, `index`, `HEAD`, `logs`, `packed-refs`,
  `refs`, `objects`, `info`, `hooks`, `branches`, `description` — all
  "Permission denied") and the whole fixture tree survives the run. The probe
  edit was reverted and the leaked tree removed. I added a comment recording
  this, so a later edit does not insert an assertion into that window.
- **Nothing leaks as written.** `find "${TMPDIR:-/tmp}" -maxdepth 1 -name
  'gitlore-test.*'` is empty after every run in this review — including the two
  mutation runs that left the squat directory behind, and every run of case 3
  itself.

**The root skip.** `[ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"`
is character-for-character the neighbouring `an unreadable marker costs the
relay, not the hook` idiom. It cannot trip errexit when not root: a failing
command that is a non-final member of an AND-OR list is exempt from `set -e` by
POSIX, and the `&&`'s right side is what is final here. Verified empirically
rather than argued — a two-case probe bats file with a false `[ … ] && …` list
mid-body, plus the `[ -e path ] && chmod` guard shape, both `ok`. This box runs
as uid 1000, so every run in this review took the non-root branch and executed
the case.

**Standard hunt.**

- `run --separate-stderr` where a diagnostic is expected: correct in cases 1 and
  2 (both fixtures emit bash/awk diagnostics on stderr and both assert on
  parsed or raw JSON); correct to *omit* in case 3, where the assertion is a
  positive on a line no diagnostic supplies and `--separate-stderr` would cost
  shellcheck's linting of the `bash -c` body. Each choice carries its rationale
  in a comment.
- `null`-guards before refutations: case 1 guards its extracted channel before
  asserting on it; case 2's refutation is over raw JSON where `null` cannot
  arise, and now carries the positive anchor that was the real gap (§5).
- Whitespace safety: every expansion is quoted — `"$squat"`, `"$json"`,
  `"$marker"`, `"$gitdir"`, `"$SRC"`, `"$PWD/memory"`. No word-splitting on any
  path, no unquoted glob, no `ls` pipeline. `$TMP_REPO` comes from `mktemp -d`
  under `${TMPDIR:-/tmp}` and is passed through quoted throughout.
- `run` vs bare calls under errexit: case 3 deliberately uses bare
  `gitlore_relay_drain` **inside** `run bash -c 'set -euo pipefail; …'`, the
  established shape in this file, because bats' `run` suspends the errexit the
  defect needs. `run gitlore_relay_write` outside it is right — that call is
  fixture, not subject.
- Substring vs exact: every new assertion is a substring, matching the file's
  own convention for hook-JSON channels. None of them is an exact-block claim
  that a substring would have to stand in for, and the drain's exact-block
  assertions elsewhere in `index_sync.bats` (1027, 1031, 1163) are untouched.
- bash 3.2 / BSD: `[[ … == *…* ]]`, `<<<`, `run --separate-stderr` (guarded by
  the file's `bats_require_minimum_version 1.5.0`), `chmod 0500`/`0700`,
  `id -u`, `rmdir`, `mkdir`. No `sed`, `grep`, `find`, `mktemp` or `stat` in the
  new code, so `tests/helpers/bsd-stubs.bash` shadows nothing the diff uses and
  `tests/bsd_portability.bats` is owed no lock-in. Numeric `chmod` modes are
  identical on BSD; the drain's own `find` is SUT, not test.
- Fixture reachability — each case reaches the path it names, not an upstream
  early exit. Case 1: the keyed run reaches `gitlore_relay_write` and the write
  fails, proven because the simulated GREEN's not-staged text appears. Case 2:
  the unkeyed run reaches `gitlore_relay_drain`, whose `find -type f` matches
  nothing and takes the `[ -n "$names" ] || return 0` exit — which is exactly
  the behaviour under test, and the mutations confirm the filter is what
  produces it. Case 3: the drain enumerates a real marker and reaches `rm -f`,
  proven because the RED failure is the caller's own errexit abort at that
  statement.

---

## 8. Mutation table

Every mutation applied in place to the SUT and restored with
`git checkout -- scripts/`; `git diff -- scripts/` verified empty after each.
Suites: `tests/index_sync.bats tests/cc_hook_index_compose.bats`.

| # | tree | mutation | result | cases that red |
|---|---|---|---|---|
| — | committed | none (baseline, RED as submitted) | **108/2** | cases 1 and 3, each on its own assertion |
| G0 | committed | **simulated GREEN**: `if !` in both hooks + `rm -f \|\| true` | **110/0** | — |
| M-A | simulated GREEN | `-type f` dropped from the drain's `find` | **109/1** | **case 2 only**, at the framing assertion |
| M-B | simulated GREEN | `-type f` → `-type d` | 98/12 | case 2 at the framing assertion; the slice-4 squat case **green** |
| M-C | simulated GREEN | `rm -f "$marker" \|\| true` → `\|\| exit 0` | **109/1** | **case 3 only**, at `[[ … OWN REPORT … ]]` |
| M-D | simulated GREEN | `-type f` dropped **and** `rm -f` → `rm -rf` | 108/2 | case 2 at `[ -d "$squat" ]`; the slice-4 squat case reds on its `rmdir` cleanup, not an assertion |
| M-E | committed | compose report literal renamed in `lib/index-compose.sh` | 102/8 | case 2 **not among them before the fix**; at line 521 after it |
| M-F | — | test-side probe: temporary `false` after `chmod 0500` | 0/1 | teardown fails on every gitdir entry; fixture tree leaks (probe reverted, tree removed) |
| — | committed | the tree as I leave it | **108/2**, twice | cases 1 and 3, same lines both runs |

---

## 9. Checks that passed, by name

- **Simulated GREEN built to the runbook's own proposal** — all three cases
  green, `110 passed, 0 failed`. No case in this slice could have failed to pass
  at GREEN.
- **`an unkeyed run leaves a non-marker alone` reds when `-type f` is dropped
  from the simulated GREEN tree** (M-A) — sole red, on the framing assertion.
  The companion restores the coverage `rm -f || true` removes; the fix may ship
  as specified.
- **`[ -d "$squat" ]` independently live** (M-D) — reds one assertion earlier
  under a drain that both enumerates and removes the squat.
- **Case 3's `OWN REPORT` assertion fires true under the simulated GREEN, and
  reds under a GREEN that returns 0 without reaching the caller's own report**
  (M-C) — sole red, on that assertion.
- **The slice-4 squat case no longer discriminates** (M-A, M-B, M-D) —
  redundant, reported, not deleted.
- **The not-staged literal is a substring of the specified GREEN wording,
  distinctive against the three other "could not be staged" producers in the
  repo, held test-side, and pins `additionalContext` rather than
  `systemMessage`.**
- **Cases 1 and 3 red on an assertion, not an error** — confirmed from the TAP
  log on both final runs.
- **Every assertion behind a death point enumerated and verified** — case 1 has
  none, case 2 has none, case 3's `OWN REPORT` verified by M-C.
- **Fixture hygiene** — the guarded restore runs on every path as written;
  `teardown_tmp_repo` succeeds; no `gitlore-test.*` directory survived any run;
  the leak hazard measured directly and recorded in a comment.
- **The root skip cannot trip errexit when not root** — verified with a probe
  bats file, not argued from the manual.
- **`shellcheck -s bash tests/index_sync.bats tests/cc_hook_index_compose.bats`**
  — clean.
- **`./scripts/lint-shell.sh`** — 137 files clean.
- **`./scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats`,
  run twice after every SUT was restored** — `108 passed, 2 failed` both times,
  the same two cases at the same lines.
- **`git diff -- scripts/`** — empty. **`git status --porcelain`** — only the two
  `.bats` files modified plus this report and the RED report; nothing staged,
  nothing committed.
