# Item 3.1 slice 2.5 — test review (RED phase)

Two defects found and fixed, both in case 1 (`tests/index_sync.bats`), both
found by mutation rather than by reading:

- The framing-line count — the assertion the runbook names as *the* thing
  distinguishing a merge from a second marker — **did not discriminate that
  shape at all**. With `gitlore_relay_write` mutated to key a second marker
  instead of merging, both suites passed entire: 101 passed, 0 failed.
- **Nothing in the suite pinned the single-write path's bytes**, which is the
  premise the runbook's whole choice of merge-per-channel rests on ("a single
  write to a fresh marker is byte-identical to today's, so every committed
  slice-1 contract case still describes the helper"). A merge whose fresh-marker
  write drifts by one leading newline per body passes every committed case.

Case 2 (`tests/cc_hook_index_compose.bats`) is left unchanged: every one of its
assertions is discriminating, each proved so by a mutation that reds it.

The RED report's candour about vacuity is accurate as far as it goes and its
argument — "vacuous at RED, discriminating against a plausible wrong GREEN" —
holds for the four cross-checks. It does not hold for the two frame counts,
which are vacuous in both phases. Its conclusion "None is vacuous in *both* RED
and GREEN" was false for two of the seven assertions.

## 1. Mechanical check — confirmed

Baseline, tests as submitted, `scripts/run-bats.sh tests/index_sync.bats
tests/cc_hook_index_compose.bats`: **99 passed, 2 failed**. Both failures are
failed assertions, neither is an error and neither test passed:

```
not ok 56 relay_write merges a second report into an existing marker
# (in test file tests/index_sync.bats, line 989)
#   `[[ "$GITLORE_RELAY_SYSMSG" == *"S1"*"S2"* ]]' failed
not ok 94 both PostToolBatch hooks in one keyed batch reach the parent
# (in test file tests/cc_hook_index_compose.bats, line 410)
#   `[[ "$output" == *"reset frontmatter to match MEMORY.md"* ]]' failed
```

`tests/cc_hook_index_compose.bats:410` is the *parent-side* drain assertion, not
the identically-worded one at `:383` that checks the sync hook's own emission —
the RED report's account of the death point is exact.

## 2. Mutation table

Every row is a full run of both suites against the mutated
`scripts/lib/index-sync.sh`, mutated in place and restored (final
`git diff -- scripts/lib/index-sync.sh` is empty). "case 1" is
`relay_write merges a second report into an existing marker`; "case 2" is
`both PostToolBatch hooks in one keyed batch reach the parent`.

### Against the tests as submitted

| mutation | shape | verdict |
|---|---|---|
| M0 | the correct merge | 101 passed, 0 failed |
| M1 | old bodies concatenated into BOTH channels | case 1 reds at `:994` (`SYSMSG != *"C1"*`) |
| M2 | old bodies appended to the wrong channels (swap) | case 1 reds at `:989`; case 2 reds at `:410` |
| **M3** | **second marker (`gitlore-relay-a1-2`) instead of a merge** | **101 passed, 0 failed — not caught** |
| M4 | prepend rather than append | case 1 reds at `:989` |
| M5 | merges sysmsg, drops the existing ctx | case 1 reds at `:990` |

M3 is the shape the frame count exists to reject, and it survives because the
counted literal is `--- gitlore-relay agent a1 ---`, which occurs exactly once
in *both* worlds: the second marker earns the agent id `a1-2`, so the drain
frames it `--- gitlore-relay agent a1-2 ---`, which does not contain the counted
string. The `-2` marker is also enumerated by the drain's `gitlore-relay-*`
find and removed by it, so `[ ! -f "$marker" ]` and the ordering substrings hold
too. Every assertion in the case is phrased in terms of the `a1` name, and the
wrong implementation leaves that name intact.

Vacuity verdict on the submitted assertions:

| assertion | RED | discriminating mutation | verdict |
|---|---|---|---|
| `SYSMSG == *"S1"*"S2"*` | fails | M2, M4 | genuine |
| `CTX == *"C1"*"C2"*` | passes | M5 | genuine, vacuous at RED only |
| `SYSMSG != *"C1"*` | passes | M1 | genuine, vacuous at RED only |
| `SYSMSG != *"C2"*` | passes | none run | unreachable behind the line above under errexit |
| `CTX != *"S1"*` | passes | none run | unreachable |
| `CTX != *"S2"*` | passes | none run | unreachable |
| `sys_frames -eq 1` | passes | **none** | **vacuous in both phases** |
| `ctx_frames -eq 1` | passes | **none** | **vacuous in both phases** |

The three "unreachable" rows are not vacuous in principle — a mutation exists
for each — but under bats' errexit each runs only when the one before it held,
so as a group they are pinned by whichever fails first and nothing exercises the
rest. Rather than split them into their own test bodies, the fix replaces the
whole block with exact-block equality, which subsumes all six substring checks
plus the frame count and cannot go vacuous (`green-is-not-evidence`: "where the
absent string is a variant of the present one, drop the pair and assert the
exact block").

### Against the fixed tests

| mutation | target | shape | reds |
|---|---|---|---|
| M0 | `relay_write` | the correct merge | **nothing — 101 passed, 0 failed on both suites entire** |
| M1 | `relay_write` | old bodies concatenated into both channels | case 1 `:1027` (sysmsg block) |
| M2 | `relay_write` | old bodies into the wrong channels | case 1 `:1027`; case 2 `:410` |
| M3 | `relay_write` | second marker instead of a merge | case 1 `:1012` (marker count) |
| M4 | `relay_write` | prepend rather than append | case 1 `:1027` |
| M5 | `relay_write` | merges sysmsg, drops the existing ctx | case 1 `:1031` (ctx block) |
| M6 | `relay_write` | keeps the existing bodies, discards the new ones | case 1 `:1027`; case 2 `:411` |
| M9 | `relay_write` | merge whose fresh-marker write also joins — one leading newline per body | case 1 `:988` (marker bytes) **only**; every committed case passes |
| M7 | `relay_drain` | folds without unlinking | 9 cases, incl. case 1 `:1027` and case 2 |
| M8 | `relay_drain` | folds without the framing line | 8 cases, incl. case 1 `:1027` and case 2 `:409` |
| M0+M7 | both | correct merge + non-unlinking drain | case 2 `:412` |

Every assertion in both cases is now verified live by at least one mutation:

| assertion | proved live by |
|---|---|
| `index_sync.bats:988` marker bytes after the single write | M9 |
| `index_sync.bats:1012` exactly one marker | M3 |
| `index_sync.bats:1027` sysmsg exact block | M1, M2, M4, M6, M8 (RED death point) |
| `index_sync.bats:1031` ctx exact block | M5 |
| `cc_hook_index_compose.bats:409` framing present at the parent | M8 |
| `cc_hook_index_compose.bats:410` sync report at the parent | baseline RED |
| `cc_hook_index_compose.bats:411` compose report at the parent | M6 |
| `cc_hook_index_compose.bats:412` marker removed | M0+M7 |

M6 is what makes `:411` honest, and it settles a question reading cannot: it
proves `recomposed tier pointers` at the parent comes from the *relayed* block
and not from the parent run's own composition. Under M6 the parent's own compose
report is unchanged and the assertion still reds, so the parent is genuinely
producing nothing of its own there — the test's comment ("composition itself
finds nothing new to splice") is correct.

M7 and M8 mutate `gitlore_relay_drain` rather than `relay_write`. They are
outside the dispatch's list and were run to answer whether case 2's `:409` and
`:412` are vacuous *in general* — under `relay_write` mutations alone neither
ever reds. Both are non-vacuous, `:412` demonstrably so only once the merge is
correct (M0+M7), because under the truncating SUT the test dies at `:410` first.
`:412` is redundant with the committed `an unkeyed compose run folds in the
marker and removes it`; it is kept as one line of end-to-end regression cover,
reported here rather than removed.

## 3. The frame-count assertion — fixed

The runbook's requirement is "one marker per agent still, one framing line per
agent at the parent". The submitted assertion counted occurrences (`grep -o`
piped to `wc -l`, not a single match) and used a literal defined test-side, not
read back from the SUT — both correct. What it got wrong is *which* literal: a
per-agent count cannot see a second agent id being fabricated, which is exactly
what the rejected second-marker design does. Fixed two ways, both of which red
M3:

- `[ "$markers" -eq 1 ]` — the number of `gitlore-relay-*` files in the memory
  gitdir after both writes and *before* the drain. This states the contract
  directly ("merges into an existing marker") and does not depend on the drain
  at all. Enumerated with `find -print0` into `read -r -d ''`, mirroring the
  drain's own enumeration, because nothing sanitizes the gitdir prefix.
- exact-block equality on each drained channel, which fails on a second framing
  line whatever agent id it names.

The `grep -o -F --` bug the RED report describes is real — reproduced on this
box (`grep: unrecognized option '--- gitlore-relay agent a1 ---'`, rc 2; the
`grep` on PATH is ugrep 7.8.4 in GNU-compatible mode) — and its fix was present
and correct. The whole line is gone now, which also removes a second latent
portability wart: BSD `wc -l` pads its count with leading spaces, so
`[ "$sys_frames" -eq 1 ]` was relying on bash's arithmetic evaluation tolerating
`"       1"`. It does, so this was never a bug, but it was one more reason the
line was the weakest in the case.

**Assertions after the death point.** The RED report is right that the `grep`
bug survived because it sat behind the dying assertion. The same audit over the
rest of both cases, done by mutation rather than by reading:

- Case 1 as submitted: everything from `:990` down had never executed. `:990`,
  `:994` were reachable by mutation; `:995`–`:997` and `:1008`–`:1009` were not
  reachable by any mutation in their position.
- Case 1 as fixed: the RED death point is `:1027`, so `:1031` never runs at RED
  — verified live by M5, which reds there.
- Case 2: the death point is `:410`, so `:411` and `:412` never run at RED —
  verified live by M6 and M0+M7 respectively. Everything above `:410` executes
  at RED and passes.

## 4. Case 2's fixture honesty — sound

- **Hook order.** `hooks/hooks.json` registers `index-sync-post.sh` (`:82`) then
  `add-tier-batch.sh` then `index-compose.sh` (`:98`) on `PostToolBatch`. The
  test drives sync then compose, which is that order.
  `scripts/cc-hooks/add-tier-batch.sh` contains no relay call, so there are
  exactly two writers to the marker today and the test drives both.
- **Both keyed runs reach their report paths**, and this is asserted rather than
  assumed: `:383` pins the sync hook's own `reset frontmatter…` emission, `:385`
  pins the frontmatter it actually rewrote, `:392` pins the compose hook's own
  `recomposed tier pointers`, `:393` pins the spliced tier bullet, `:395` pins
  the marker's existence. Neither hook can be exiting early.
- **The unkeyed run genuinely drains**: `:409` (framing) and `:412` (unlink) are
  both live under mutation, per the table above.
- **`sync_feed()` follows the file's contract**: same `local agent="${1:-}"`,
  same `+ (if $a == "" then {} else {agent_id:$a} end)` absent-vs-non-empty
  shape, and it keeps the `agent_type:"general-purpose"` decoy that `pre()` and
  `feed()` carry — so a hook keying on `agent_type` instead of `agent_id` still
  fails. Its extra envelope fields (`hook_event_name`, `session_id`,
  `tool_calls`, `tool_results`) match `batch_payload()` in
  `tests/index_sync.bats` and are read-but-inert
  (`index-sync-post.sh` takes `.session_id // ""` for the budget nudge file and
  ignores `.tool_calls`), so they neither weaken nor prop up the case.

## 5. Standard hunt — nothing else found

- **Whitespace.** The new marker enumeration is `find -print0` into
  `read -r -d ''`. Every expansion in both cases is quoted; `abs="$PWD/…"` is
  quoted at both use sites. No word-splitting anywhere in the diff.
- **bash 3.2 / BSD.** No `-i`, no `\b`, no `-P`/`-z`, no GNU-only `find`
  predicate. `while … done < <(find …)` and `$(cat "$marker")` are portable.
  The one GNU/BSD divergence in the submitted diff (`grep -o -F --`, plus
  `wc -l` padding) is gone with the line that carried it.
- **`run` vs bare.** `run` is used where `$status`/`$output` are asserted; the
  drain is deliberately called bare with `|| rc=$?` because its output is two
  variables a subshell would discard — the same idiom the committed slice-1 case
  uses, with the reason in its comment. Bare `grep -qF` and bare `pre`/
  `seed_root_fact` are assertions-by-exit-status under errexit, matching the
  file's existing idiom.
- **Equality vs substring.** Case 1 is now all equality. Case 2's five substring
  checks each match a phrase only one producer emits — verified for
  `recomposed tier pointers` by M6, which is the one where a second producer was
  plausible.
- **Fixture leakage.** `setup`/`teardown` are the file's own; both cases build
  their own state and leave nothing behind. `git status --short` after the whole
  mutation campaign shows only the two test files and this slice's reports.
- **`shellcheck -s bash`** clean on both files; **`scripts/lint-shell.sh`** 137
  files clean.

## 6. Do the committed slice-1 cases still describe the helper? No — gap closed

The runbook justifies merging per channel over per-source keying with: "Merging
per channel changes neither the file format nor the marker's name, so every
committed slice-1 contract case still describes the helper: a single write to a
fresh marker is byte-identical to today's."

**The committed cases cannot detect a violation of that premise.** They are
sufficient to catch a merge that breaks the single write *observably through the
drain* — M7 and M8 each red several of them — but every slice-1 relay case reads
the drained channels or the marker's existence, and none reads the marker's
bytes. Measured with M9, a merge whose fresh-marker path joins unconditionally
and so writes one leading newline into each body: **every committed case
passes.** `relay_write then relay_drain splits the two channels and removes the
marker` still finds `S1` in the sysmsg channel and `C1` in the ctx channel,
because the drain's `awk` re-splits a drifted file into the same two channels.

Since `tests/index_sync.bats` slice-1 cases are frozen and out of this slice's
scope, the gap is closed from inside case 1 instead: the byte check at `:988`
runs on the first write, before any merge is in play, and pins exactly the file
today's `gitlore_relay_write` produces. M9 reds there and nowhere else.

## 7. Changes applied

Only `tests/index_sync.bats`, case 1. `tests/cc_hook_index_compose.bats` is
unchanged from what the RED phase committed.

- Added a byte-exact assertion on the marker after the *first* write (§6).
- Added a count of `gitlore-relay-*` files, taken before the drain, asserting
  exactly one (§3).
- Replaced the two ordering substrings, the four cross-checks and the two frame
  counts with two exact-block equalities on `GITLORE_RELAY_SYSMSG` and
  `GITLORE_RELAY_CTX`, written as test-side literals.

The exact blocks pin the join — a single newline between the two reports, no
blank line — which the substring form left free. That is a real constraint added
to GREEN, and it is the right one: bodies in this format are line-oriented, and
`index-sync-post.sh` already joins its own several sysmsg blocks with a single
newline. It is stated in the test's comment so GREEN does not have to guess.

RED state after the fixes is unchanged in shape — 99 passed, 2 failed, both on
assertions — with case 1's death point moved from `:989` to `:1027`.

## Checks that passed, by name

- `scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats`,
  baseline before any edit — 99 passed, 2 failed, both new cases, both on a
  failed assertion, no other case regressed.
- The same command after the fixes — 99 passed, 2 failed, same two cases.
- `M0` (the correct merge) against both suites entire — 101 passed, 0 failed,
  both before and after the fixes.
- `M1`–`M6`, `M9` against both suites entire — every one reds at least case 1;
  first failing assertion recorded per row in §2.
- `M7`, `M8`, `M0+M7` (drain mutations) against both suites — used to establish
  that case 2's `:409` and `:412` are non-vacuous in general.
- `shellcheck -s bash tests/index_sync.bats tests/cc_hook_index_compose.bats` —
  rc 0.
- `scripts/lint-shell.sh` — 137 files clean.
- `git diff -- scripts/lib/index-sync.sh` after the last mutation — empty; the
  SUT is byte-identical to `HEAD`.
- `git status --short` — only `tests/index_sync.bats`,
  `tests/cc_hook_index_compose.bats` and this slice's two reports; no scratch
  file, no mutation artifact left in the tree. Nothing committed, nothing
  staged.
- `hooks/hooks.json` read directly for the `PostToolBatch` order, and
  `scripts/cc-hooks/add-tier-batch.sh` grepped for `gitlore_relay` (no match) —
  the two hooks case 2 drives are the only writers to the marker.
