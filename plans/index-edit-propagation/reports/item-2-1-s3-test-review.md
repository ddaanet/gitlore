# Item 2.1 slice 3 — test review

Scope reviewed: the two new cases in `tests/index_sync.bats` and the
`batch_payload` / `TEST_AGENT_TYPE` change, against
`plans/index-edit-propagation/reports/item-2-1-s3-red.md`. Read-only for
judgement: `scripts/cc-hooks/index-sync-post.sh`, `index-sync-pre.sh`,
`scripts/lib/index-sync.sh`, `tests/helpers/setup.bash`,
`helpers/fixtures.bash`, `plans/index-edit-propagation/outline.md` §C, slice 2's
test and code reviews, and the recall artifact.

One change applied, inside case 1: a second phase that gives the parent a
baseline it owns. It closes the two channels the dispatch named — the
`[ -z "$output" ]` vacuity and an inert `agent_type` decoy — and it turns a
wrong GREEN the **whole suite** was green under into a red. The slice is still
red in the same shape.

## Mechanical verdict per case

Reproduced the RED report's run verbatim before touching anything — byte
identical, line 693 included:

```
$ bats -f "leaves a subagent's pre-image intact|then consumes its keyed pre-image" tests/index_sync.bats
1..2
ok 1 a parent post-hook leaves a subagent's pre-image intact
not ok 2 the subagent's own post-hook then consumes its keyed pre-image
# (in test file tests/index_sync.bats, line 693)
#   `[ "$output" = 'description: "new hook"' ]' failed
```

`scripts/run-bats.sh tests/index_sync.bats` on the untouched tree:
**70 passed, 1 failed**, matching the RED report.
`sha256sum scripts/cc-hooks/index-sync-post.sh` = `1a657eb3…`, the sha the RED
report recorded, so the reproduction ran against the same SUT.

1. **`a parent post-hook leaves a subagent's pre-image intact` — passed against
   unmodified code, legitimately, and it is a guard rather than a test of slice
   3's change.** The structural argument holds; verified below. Non-vacuous by
   mutation before my change (MA, MG, MH) and materially more so after it (MB,
   MD).
2. **`the subagent's own post-hook then consumes its keyed pre-image` — FAILED
   on its assertion, genuinely.** `[ "$status" -eq 0 ]` on the preceding line
   held, so the hook was found, ran and exited 0; death is on
   `[ "$output" = 'description: "new hook"' ]`, a value assertion — not an error
   and not a missing symbol. Both of its assertions are independently reachable
   (ME, MF below).

The SUT was restored byte-identical after every mutation; proof at the end.

## The RED report's structural argument for case 1 — tested, and it holds

The claim: today's bare-path post-hook and slice 3's keyed one resolve the
identical name in this scenario (the parent carries no `agent_id`), so slice 3's
change cannot move the outcome.

Confirmed by running the presumed GREEN itself rather than reading for it —
**MC**, `agent_id=$(jq -r '.agent_id // empty' …)` plus
`gitlore_index_preimage_file "$mempath" "$agent_id"` in `index-sync-post.sh:30`:

```
=== MC (presumed GREEN) ===
ok 1 a parent post-hook leaves a subagent's pre-image intact
ok 2 the subagent's own post-hook then consumes its keyed pre-image
```

Case 1 is green before and after the change; case 2 flips. So case 1 is a guard
against a wrong fix, not a test of the fix, exactly as the RED report says. MC
also establishes something the RED report never did:
**the slice is satisfiable** — GREEN has a reachable target, and neither my
change nor the committed assertions over-specify it.

**It earns its place in this slice, and belongs to no other.** The hazard it
guards is created *here*: slice 3 is where `index-sync-post.sh` first reads the
payload, so it is where the post hook can first resolve the wrong name. Slice
2's three cases drive `$PRE` only and cannot see a post-hook misread — I
checked, and under MD (below) all three stay green. Written at slice 2 the case
would have passed too, but it would have been guarding a hazard that did not yet
exist. A guard belongs where the hazard is introduced.

## Findings

### Major — the whole suite was green under the forbidden `agent_type` fallback

**Fixed.** Outline §C names the constraint: "Read `agent_id` specifically, never
`agent_type` — that one also appears on the main thread of an `--agent`
session", and the section comment the RED phase wrote asserted the decoy
enforced it — "so a post-hook that falls back to `agent_type` cannot pass either
case by accident." That claim was false, measured rather than read. **MD**, a
GREEN reading `(.agent_id // .agent_type) // empty`:

```
=== MD, against the cases AS WRITTEN ===
ok 1 a parent post-hook leaves a subagent's pre-image intact
ok 2 the subagent's own post-hook then consumes its keyed pre-image
```

The reason is structural, and it is the same reason as the `[ -z "$output" ]`
finding below. In the case as written the parent owns **no** baseline, so its
post hook exits at `index-sync-post.sh:32` before touching any file: every
candidate key — the bare name, or a fallback onto `agent_type` — resolves to a
file that does not exist, and the three assertions cannot tell them apart. The
scenario is name-blind on the parent side. Case 2's second call is no help
either: its payload carries `agent_id`, so `.agent_id` and
`(.agent_id // .agent_type)` are the same string there. (Case 2 *does* catch the
reversed reading `.agent_type // .agent_id` — that resolves `-general-purpose`,
finds nothing, and the propagation never happens. So the decoy was not wholly
inert, only inert against the fallback direction, which is the plausible one.)

This was suite-wide, not case-local. Every other `post:` case builds its payload
with `batch_payload` carrying no `agent_type` at all, so a fallback reading is
invisible to them by construction.

**Changed:** case 1 gains a second phase (`tests/index_sync.bats:674-691`).
After the first phase's assertions, the parent's *own* pre-hook fires — a `Bash`
call with no `agent_id` and the `agent_type` decoy, landing after the subagent's
Edit, which is the interleaving the outline actually observed (the subagent's
Edit at 22:10:47.696, the parent's Bash pre-hook 243 ms later). The pre-hook
stashes the index as it already stands, so the parent now owns a bare baseline
identical to the index; the parent's post-hook must consume it, stay silent
(nothing changed against that baseline), and still leave the subagent's keyed
pair alone:

```sh
  printf '%s' '{"tool_name":"Bash","tool_input":{"command":"ls"},"agent_type":"general-purpose"}' \
    | bash "$PRE"
  [ -f "$(gitlore_index_preimage_file memory)" ]
  run post_stdin "$(TEST_AGENT_TYPE=general-purpose batch_payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$(gitlore_index_preimage_file memory)" ]
  [ -f "$(gitlore_index_preimage_file memory a1)" ]
```

Now the parent's resolved name is observable, and MD reds on `:689`. Run against
the **full** suite so the claim is bounded rather than asserted:

```
$ scripts/run-bats.sh tests/index_sync.bats      # with MD applied
not ok 42 a parent post-hook leaves a subagent's pre-image intact
# (in test file tests/index_sync.bats, line 689)
#   `[ ! -f "$(gitlore_index_preimage_file memory)" ]' failed
bats: 70 passed, 1 failed
```

Exactly one case fails under MD, and it is the strengthened one — which is also
the proof that nothing else in the 71 cases was catching it.

The section comment now says where the decoy bites instead of claiming it bites
everywhere, so the next reader can check the claim:

```
# `--agent` payload. It bites in the second phase of the first case, where the
# parent has a baseline of its own to consume: a post-hook falling back to
# `agent_type` resolves a name nothing ever wrote and strands that baseline.
```

**Deviation from the runbook, stated plainly.** The runbook's parenthetical for
this case is "(it had no baseline of its own, so nothing to diff)". Phase 1
keeps that scenario intact and unchanged — including the `[ -z "$output" ]` it
justifies. Phase 2 adds the opposite arm, in which the parent's silence has a
different cause (its own baseline matched). Both arms are needed and neither
subsumes the other: MA, the RED report's own mutation, is caught **only** by
phase 1 (with a bare baseline present, its `if [ ! -f "$stashfile" ]` fallback
never fires), while MB and MD are caught **only** by phase 2.

### Major — `[ -z "$output" ]` could not distinguish a correct no-op from a dead hook

**Fixed by the same change.** The dispatch's suspicion was right, and it is
measurable. **MB**, the post hook reduced to `exit 0` on its second line:

```
=== MB, against the cases AS WRITTEN ===
ok 1 a parent post-hook leaves a subagent's pre-image intact
not ok 2 the subagent's own post-hook then consumes its keyed pre-image
```

Case 1 passed against a hook that does nothing at all — all three of its
assertions are satisfied by `POST=/bin/true`. That is inherent to the prescribed
scenario: the correct behaviour there *is* to do nothing observable, so no
assertion over that scenario alone can separate "ran and correctly found no
baseline of its own" from "never ran". The discrimination has to come from a
second observation in which the hook must act.

Phase 2 is that observation, and it is a genuine positive control rather than
another negative: the parent's own baseline must be **gone** afterwards. MB now
reds on `:689` as well:

```
=== MB, after the fix ===
not ok 1 a parent post-hook leaves a subagent's pre-image intact
# (in test file tests/index_sync.bats, line 689)
#   `[ ! -f "$(gitlore_index_preimage_file memory)" ]' failed
```

The setup guard `[ -f "$(gitlore_index_preimage_file memory)" ]` (`:685`) is
what keeps that `! -f` from passing vacuously when the file was never written —
it is the `find`-over-a-missing-directory hazard slice 2's review recorded, in a
different dress. Verified live, not argued: **MI**, the pre-hook's tool filter
narrowed to `Write|Edit` so a parent `Bash` call stashes nothing, reds on the
guard itself:

```
=== MI (pre-hook ignores Bash) ===
not ok 1 a parent post-hook leaves a subagent's pre-image intact
# (in test file tests/index_sync.bats, line 685)
#   `[ -f "$(gitlore_index_preimage_file memory)" ]' failed
```

### Assessed, no defect — the RED report's mutation choice

MA — the post hook falling back to any keyed file via
`find … -maxdepth 1 -name 'gitlore-index-preimage-*' -print -quit` — is a fair
mutation, not a strawman. It is the wrong fix that reopens precisely the race
the item exists to close (a parent's post hook consuming a subagent's baseline),
and it is reachable: an implementer who notices the parent now finds nothing and
"fixes" the regression slice 2 introduced for subagents would write something
close to it. Reproduced independently, before and after my change, dying on
`[ -z "$output" ]` both times.

It is not, however, the *only* plausible wrong fix, and the two simpler ones the
dispatch named are both real. **MG**, an unconditional
`rm -f "$(dirname "$stashfile")"/gitlore-index-preimage-*` ahead of today's
resolution, reds case 1 on `[ -f … memory a1 ]` (`:672`) and case 2 on its
description. **MH**, a correctly-keyed post hook against a pre-hook keying on
`agent_type` instead, reds case 1 on the same line — the pre/post pair has to
agree on the name, and the case pins that they do. Both are caught. What was
*not* caught before my change was MD, the fallback read — the RED report's
mutation set had no member that could see it, because none of them varies the
name the parent resolves while leaving something for the parent to find.

### Assessed, no defect — case 2's two assertions

Both reachable, and GREEN cannot satisfy the case by flipping one. A bats body
runs under errexit, so the description assertion aborts the case before the
`! -f` is reached — but each is independently load-bearing, shown by mutating a
correct GREEN in one direction at a time:

| mutation of the presumed GREEN | case 2 |
| --- | --- |
| **ME** — propagates correctly, but the final `rm -f` targets the **bare** path | red `:713` `[ ! -f "$(gitlore_index_preimage_file memory a1)" ]` |
| **MF** — resolves the keyed path and removes it, but always takes the `cmp`-equal branch, so it never propagates | red `:712` `[ "$output" = 'description: "new hook"' ]` |

ME is the more plausible of the two: an implementer who keys the *lookup* and
forgets the *removal* leaves a stale baseline behind, which the pre-hook's
`[ -f "$stash" ] && exit 0` then treats as the next batch's baseline.

### Assessed, no defect — `TEST_AGENT_TYPE`

The contract holds, exercised directly rather than read:

```
unset       : {"has_t":false,"has_a":false}
empty       : {"has_t":false,"has_a":false}     (TEST_AGENT_TYPE= )
set         : {"t":"general-purpose","has_a":false}
spacey      : {"t":"gen purpose"}
quotey      : {"t":"he said \"hi\""}
both        : {"a":"a1","t":"general-purpose"}
```

Unset and empty both **omit the field entirely** — neither emits
`"agent_type": ""` — mirroring `TEST_AGENT_ID` and `TEST_SESSION_ID`. The value
crosses into jq through `--arg`, never through word splitting, so a space or a
quote survives byte for byte. Both of this slice's cases carry the decoy on
every payload that has no `agent_id`, which is where a real main-thread
`--agent` payload would carry it, and case 2's subagent payload carries both
fields with distinct values — the shape that makes the reversed reading fail on
case 2's own assertions. The helper is used in no other suite
(`grep -rln 'batch_payload\|TEST_AGENT_TYPE\|TEST_AGENT_ID' tests/` → one file),
so the change cannot perturb anything outside `index_sync.bats`.

Noted for the record: `batch_payload` with no arguments emits `tool_calls: []`,
and both of this slice's parent calls use that form. It is harmless — the post
hook deliberately never inspects `.tool_calls[]` (`index-sync-post.sh:15-20`),
and the existing "a sed -i under Bash" case already drives it the same way — but
it does mean the batch contents are decoration in these cases, not a lever.

### Assessed, no defect — the discarded scratch harness left no residue

The RED report describes an ad hoc `git init`/`git submodule add` harness whose
results were misleading because `gitlore_cd_project_root` never resolved it.
Nothing of it survives in the tree:

- `git status --porcelain` — one modified file, `tests/index_sync.bats`, plus
  the RED report and the pre-existing ambient dotfiles that were already
  untracked at session start (`.bashrc`, `.claude/*`, `.idea`, `.vscode`, …). No
  new untracked path under `tests/`, `scripts/` or the repo root.
- `find . -name '*.orig' -o -name '*.rej' -o -name '*.bak' -o -name '*.save'` —
  nothing.
- `find . -mindepth 2 -maxdepth 4 -name .git` — `./memory/.git` and
  `./memory/ddaanet/.git` only, the two legitimate submodules, and neither shows
  as modified.

### Assessed, no defect — whitespace, ambient env, bash 3.2, BSD

- **Whitespace.** Every `$( )` in the new lines is inside double quotes, and the
  paths reach the assertions through `gitlore_index_preimage_file`, which
  returns an absolute path from `rev-parse --git-path`. Proved rather than
  argued: the two cases re-run with `TMPDIR="/tmp/claude/space dir"`, same
  1-pass/1-red result, plus a throwaway probe confirming the spaced `TMPDIR`
  really reaches the test process and `setup_tmp_repo`'s
  `mktemp -d "${TMPDIR:-/tmp}/…"`
  (`mktemp-gave=[/tmp/claude/space dir/gitlore-test.nYSTG0]`), so the gitdir
  path the `-f` tests received genuinely contained a space. The probe file lives
  in a scratch directory, not under `tests/`.
- **Ambient `CLAUDECODE`.** Neither case reads it and neither hook does on these
  paths (`scripts/lib/log.sh:10` is the only reference under `scripts/`). Ran
  the pair under `CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli` and under
  `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` — identical output both ways, so
  the result is neither dispatch-only nor human-only.
- **bash 3.2.** No arrays, no `${var^^}`, no `**`, no `<<<` added on the test
  side; the new lines are `printf`, a pipe, and `[` tests.
- **BSD.** The added lines introduce no `find`, `sed`, `stat` or `mktemp`. The
  only external tools are `printf`, `bash`, `jq` and (in case 2)
  `grep '^description:'`, a BRE anchor that behaves identically on BSD and GNU.
  The `printf '%s' '<json>' | bash "$PRE"` form matches the existing "a sed -i
  under Bash" case's idiom, and `%s` keeps a literal `%` in a payload from being
  read as a conversion.
- **shellcheck.** `shellcheck -s bash tests/index_sync.bats` — exit 0. No bare
  top-level `!` (SC2314) was added.

### Minor — the RED report's line numbers are stale

Not fixed; the RED report is out of this dispatch's scope. Case 2's failing
assertion moved from `:693` to `:712` — `:693` is now the case's `@test` line —
purely from the comment and phase-2 additions above. The assertion text is
unchanged.

## Mutation matrix

Nine mutations, each applied in place to the SUT and reverted. "as written" is
the RED phase's committed cases; "after fix" is the reviewed state.

| # | mutation | as written | after fix |
| --- | --- | --- | --- |
| MA | post falls back to any keyed file via `find … -print -quit` (the RED report's) | 1 red `:670` `[ -z "$output" ]` | 1 red `:671`, same assertion |
| MB | post hook is a no-op (`exit 0`) | **1 ok** — vacuous | 1 red `:689` `[ ! -f … memory) ]` |
| MC | presumed GREEN: reads `.agent_id`, keys the stash | 1 ok, 2 ok — satisfiable | 1 ok, 2 ok |
| MD | GREEN reading `(.agent_id // .agent_type)` | **1 ok, 2 ok** — forbidden GREEN ships | 1 red `:689` |
| ME | GREEN, but the final `rm -f` targets the bare path | 2 red `:694` `[ ! -f … a1) ]` | 2 red `:713`, same assertion |
| MF | GREEN, but always takes the `cmp`-equal branch (removes, never propagates) | 2 red `:693` description | 2 red `:712`, same assertion |
| MG | unconditional `rm -f …/gitlore-index-preimage-*` before today's logic | 1 red `:671` `[ -f … a1) ]` | 1 red `:672`, same assertion |
| MH | post keys correctly, pre keys on `agent_type` | 1 red `:671` | 1 red `:672` |
| MI | pre-hook's tool filter narrowed to `Write\|Edit` (parent `Bash` stashes nothing) | n/a — phase 2 did not exist | 1 red `:685`, the setup guard |

MC matters as much as the reds: it is the only evidence that GREEN has a
reachable target and that the strengthened case does not over-specify the
contract.

## Re-run after the fix

```
$ bats -f "leaves a subagent's pre-image intact|then consumes its keyed pre-image" tests/index_sync.bats
1..2
ok 1 a parent post-hook leaves a subagent's pre-image intact
not ok 2 the subagent's own post-hook then consumes its keyed pre-image
# (in test file tests/index_sync.bats, line 712)
#   `[ "$output" = 'description: "new hook"' ]' failed
```

Same shape as RED: case 1 passes and is now demonstrably non-vacuous (MB, MD,
MI), case 2 dies on its description assertion with `$status` already asserted 0.

```
$ scripts/run-bats.sh tests/index_sync.bats
bats: 70 passed, 1 failed — full log: /tmp/claude-1000/gitlore-bats.bIyUHK
```

The one failure is this slice's red case. No collateral damage — same 70/1 as
the untouched tree.

## Restore proof

Every mutation was applied in place and reverted with `git checkout --`. After
the last one:

```
$ git status --porcelain -- scripts/
(no output)
$ git diff HEAD --stat -- scripts/
(no output — covers content and mode)
$ sha256sum scripts/cc-hooks/index-sync-post.sh scripts/cc-hooks/index-sync-pre.sh scripts/lib/index-sync.sh
1a657eb305e46d72c7696a7c8a84f5ecf574f5ec9b340494bdbbcc4c075b2ce4  scripts/cc-hooks/index-sync-post.sh
73b9b5cd5e7747f789fe4369a690b278b400f6b7fdeb4571d7b1d19f608af22e  scripts/cc-hooks/index-sync-pre.sh
64f9d191243e685eda56bcb76456954306083bd22d21a6c087af1c8f65596c59  scripts/lib/index-sync.sh
```

Independently of `git status`, every tracked file under `scripts/` was compared
blob-by-blob — `git hash-object -- "$f"` against `git rev-parse "HEAD:$f"`, over
`git ls-files -z` so a spaced path could not be mis-split — with no mismatch.
`1a657eb3…` is the sha the RED report recorded; `73b9b5cd…` and `64f9d191…` are
slice 2's code review's, for the two files I mutated only for discrimination.
Modes are unchanged (`100755` on both hooks).

## Checks that passed, by name

- `bats -f "leaves a subagent's pre-image intact|then consumes its keyed pre-image" tests/index_sync.bats`
  before any edit — reproduced the RED report byte for byte, line 693 included.
- `sha256sum scripts/cc-hooks/index-sync-post.sh` before any edit — matched the
  RED report's `1a657eb3…`, so the reproduction ran against the same SUT.
- `scripts/run-bats.sh tests/index_sync.bats` on the untouched tree — 70 passed,
  1 failed.
- The same filtered command after the fix — 1 pass, 1 genuine red on `:712`.
- `scripts/run-bats.sh tests/index_sync.bats` after the fix — 70 passed, 1
  failed, no collateral damage.
- `scripts/run-bats.sh tests/index_sync.bats` **under MD** — 70 passed, 1
  failed, the single failure being the strengthened case; bounds the "nothing
  else in the suite catches the fallback" claim.
- Mutations MA, MB, MC, MD, ME, MF, MG, MH against the cases as written and
  again after the fix; MI against the fixed cases — table above, each with its
  failing assertion line.
- `batch_payload` direct exercise — `TEST_AGENT_TYPE` unset and empty omit the
  field, non-empty sets it, spaces and quotes survive.
- `grep -rln 'batch_payload\|TEST_AGENT_TYPE\|TEST_AGENT_ID' tests/` — one file,
  so no other suite is affected.
- The pair under `TMPDIR="/tmp/claude/space dir"`, with a probe confirming the
  spaced path really reaches `setup_tmp_repo`'s `mktemp` — same result.
- The pair under `CLAUDECODE=1 CLAUDE_CODE_ENTRYPOINT=cli` and under
  `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` — identical both ways.
- `shellcheck -s bash tests/index_sync.bats` — exit 0.
- `scripts/lint-shell.sh` — `lint-shell: 137 files clean`, the same count as
  slices 1 and 2; nothing added or left behind.
- `git status --porcelain` / `git diff HEAD --stat -- scripts/` / per-file blob
  comparison — `M tests/index_sync.bats` only; `scripts/` byte-identical to
  HEAD.
- Scratch-harness residue sweep — no `.orig`/`.rej`/`.bak`/`.save`, no nested
  git repo beyond the two submodules, no untracked path under `tests/`.

## Out of scope, untouched

- `scripts/cc-hooks/index-sync-post.sh` and `index-sync-pre.sh` — mutated for
  discrimination only, restored byte-identical (proof above). The post hook must
  not learn to read `agent_id` in this dispatch, and does not.
- `scripts/lib/index-sync.sh` — read only; unchanged, sha above.
- Slice 4's cases; `tests/cc_hook_index_compose.bats`;
  `tests/cc_hook_add_tier.bats`.
- `docs/`, `memory/`, and everything under `plans/` other than this report —
  including the RED report, whose stale line numbers are flagged above rather
  than edited.

## For GREEN and the code review

- The `agent_type` fallback is now pinned by `tests/index_sync.bats:689`. GREEN
  must read `.agent_id` specifically, as `index-sync-pre.sh:40` already does.
- ME is the failure mode to watch: keying the *lookup* and forgetting the
  *removal* leaves a stale keyed baseline that the pre-hook's
  `[ -f "$stash" ] && exit 0` will hand to the next batch as its baseline.
- Slice 4's consumers (`index-compose.sh`, `add-tier-batch.sh`) face the same
  blindness this review found: a main-thread payload can only pin which name a
  hook resolved if that hook has a baseline of its own to consume. The outline's
  prescribed compose case ("a pre-hook with `agent_id` set and a post-hook
  without it, asserting the main-thread baseline survives") needs the
  main-thread stamp to exist for the same reason.

Nothing committed. `just precommit` not run, per the dispatch.
