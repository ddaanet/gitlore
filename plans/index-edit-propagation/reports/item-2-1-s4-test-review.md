# Item 2.1 slice 4 — test review

Scope reviewed: the two new cases and the three helper changes in
`tests/cc_hook_index_compose.bats` and `tests/cc_hook_add_tier.bats`, against
`plans/index-edit-propagation/reports/item-2-1-s4-red.md`. Read-only for
judgement: `scripts/cc-hooks/index-compose.sh`, `add-tier-batch.sh`,
`index-sync-pre.sh`, `scripts/lib/index-sync.sh`, `tests/helpers/setup.bash`,
`tests/index_sync.bats`, the runbook's Item 2.1 (slice 4 at `runbook.md:648`),
slices 1-3's RED / test-review / code-review reports, `CLAUDE.md`,
`memory/ddaanet/shared-claude.md` and `.claude/rules/shell.md`.

Four changes applied. The suite is still red, in a wider shape:
**25 passed, 3 failed** (was 24/2). The extra pass and the extra red are both
deliberate and justified below.

## Baseline reproduced before anything was touched

```
$ scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats
not ok 9 a main-thread compose baseline survives a subagent's compose hook
# (in test file tests/cc_hook_index_compose.bats, line 173)
#   `[ -z "$output" ]' failed
not ok 23 add-tier hook: drops the compose baseline for its own agent, leaves the bare one
# (in test file tests/cc_hook_add_tier.bats, line 147)
#   `[ ! -f "$keyed" ]' failed

bats: 24 passed, 2 failed
```

Byte-identical to the RED report, against production files whose shas are
recorded under "Restore proof". 24 = 15 pre-existing compose cases + 9
pre-existing add-tier cases, confirmed against
`git show HEAD:tests/… | grep -c '^@test'`.

## Mechanical verdict per case

1. **`a main-thread compose baseline survives a subagent's compose hook` —
   FAILED on its assertion, genuinely.** `[ "$status" -eq 0 ]` on the preceding
   line held, so the hook ran and exited 0. Both of its post-`run` assertions
   are independently load-bearing, proved by mutation rather than by an
   assertion-order swap (M6 and the pre-change baseline below). The order was
   wrong and is now fixed — see Major 1.
2. **`add-tier hook: drops the compose baseline for its own agent, leaves the bare one`
   — FAILED on its assertion, genuinely**, at `tests/cc_hook_add_tier.bats:143`
   (was `:147`; the header edit moved it). `add-tier-batch.sh:75` does the bare
   `rm -f` unconditionally, so today the bare stamp is gone and the keyed one
   survives — the exact inverse of the contract. Both of its assertions are
   reachable: M5 reds the second one (`[ -f "$bare_stamp" ]`) while the first
   passes.

Production was mutated for discrimination only and restored byte-identical;
proof at the end.

## Findings

### Major 1 — case 9's assertions were ordered so RED exercised the wrong one

**Fixed**, `tests/cc_hook_index_compose.bats:174-182`.

A bats body runs under errexit, so exactly one of the two post-`run` assertions
is ever exercised at RED. As committed, `[ -z "$output" ]` came first, so the
red was evidence that the hook *spoke*; that the parent's baseline is *consumed*
— the silent-data-loss bug the whole item exists to close — was never
demonstrated by the RED run at all. The RED report claims it checked this by
swapping the two in a scratch copy, which is evidence about a file that no
longer exists; the committed case is what GREEN and the audit read.

The two assertions are not interchangeable, and both are needed. Proved by
mutation, not by reading:

- The **pre-change production code** (the RED baseline itself) reds on
  `[ -f "$(gitlore_compose_stamp_file memory)" ]` at `:181` once the order is
  fixed — the bare stamp is genuinely consumed, not merely readable.
- **M6**, a lenient GREEN that keys the lookup but falls back to the bare stamp
  for *reading* when no keyed one exists and removes nothing, reds **only** on
  `[ -z "$output" ]` (`:182`): the bare stamp survives, so the first assertion
  passes.

So neither subsumes the other. Reordered to put the survival assertion first,
with the reason inline, so RED's evidence lands on the severe failure and the
noise assertion stays as the second guard:

```sh
  # Survival first, silence second: a bats body runs under errexit, so only the
  # first of the two is exercised at RED, and the stranded parent edit this
  # assertion catches is the silent bug the item exists to close — the stray
  # report the next one catches is merely noise. …
  [ -f "$(gitlore_compose_stamp_file memory)" ]
  [ -z "$output" ]
```

**For GREEN:** `[ -z "$output" ]` is now the assertion RED does not exercise. It
discriminates (M6), but it has not been shown to fail against the tree as it
stands, only against a hypothetical.

### Major 2 — nothing in either suite pinned that a subagent's compose does anything at all

**Fixed** by a new case, `tests/cc_hook_index_compose.bats:185-209`
(`a subagent's compose consumes its own baseline, not the main thread's`).

Case 9 is a pure negative: `feed a1` finds no keyed stamp and must return
silently, so it never reaches `index-compose.sh:50`'s `rm -f "$stamp"` and never
reaches the compose itself. Every other compose case drives the main-thread
path. That left the whole positive half of the slice unpinned. Measured, against
the presumed GREEN with one line changed each time:

| mutation of the presumed GREEN | suite, before this fix |
| --- | --- |
| **M3** — keys the stamp LOOKUP, leaves `rm -f` on the bare name | **26 passed, 0 failed** |
| **M4** — `[ -z "$agent_id" ] \|\| exit 0`: subagents never compose at all | **26 passed, 0 failed** |

Both ship green. M3 is the failure mode slice 3's code review named for its own
slice ("keying the lookup and forgetting the removal"), reproduced here for the
compose hook; the stranded keyed stamp it leaves is then handed to that agent's
*next* batch by `index-sync-pre.sh:58`'s `if [ ! -f "$stamp" ]`, so a later real
edit composes against an ancient baseline. M4 is the lazier wrong fix — the one
an implementer reaches for after reading case 9 and concluding that a subagent's
job is to keep quiet.

The new case puts a parent batch in flight alongside the subagent, so which name
the subagent resolved is observable from both sides:

```sh
  pre "$PWD/memory/MEMORY.md" a1
  pre "$PWD/memory/MEMORY.md"
  keyed=$(gitlore_compose_stamp_file memory a1)
  bare=$(gitlore_compose_stamp_file memory)
  [ -f "$keyed" ]
  [ -f "$bare" ]
  seed_root_fact "p.md" "a project fact"
  run feed a1
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  [[ "$output" == *systemMessage* ]]
  [ ! -f "$keyed" ]
  [ -f "$bare" ]
```

The two `[ -f ]` guards run before the SUT for the reason slice 2's review
recorded: they are what keeps `[ ! -f "$keyed" ]` from passing vacuously on a
file nothing ever wrote. `index-sync-pre.sh:40-42` resolves both names per agent
and gates on `[ ! -f "$stamp" ]` per key, so the two `pre` calls write two
distinct files — asserted, not assumed.

It is a **genuine red against unchanged production code**, on
`[ ! -f "$keyed" ]` (`:207`): today's hook resolves the bare stamp, composes,
reports and removes the bare one, so the keyed stamp is still there. And it
catches M3 (`:207`) and M4 (`:205`, the `grep`) — see the matrix.

### Major 3 — the `agent_type` decoy was wholly inert in `cc_hook_add_tier.bats`

**Fixed** by a new case, `tests/cc_hook_add_tier.bats:147-170`
(`add-tier hook: a main-thread batch drops the bare compose baseline, not an agent_type-keyed one`).

Established by running the forbidden fallback, per the dispatch. **M2**, both
hooks reading `jq -r '.agent_id // .agent_type // empty'`, against the cases as
committed:

```
$ scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats
not ok 5  an index-touching batch composes and reports on both channels        :116
not ok 6  a Bash-applied index edit composes, though it named no file          :130
not ok 7  a manifest-touching batch recomposes                                 :140
not ok 10 a validation failure reports on both channels and exits 0            :182
not ok 11 a dangling pointer is reported even when nothing was composed        :196
not ok 13 an index-only batch composes but emits no triage directive           :220
not ok 14 a manifest-touching batch emits a triage directive…                  :237

bats: 19 passed, 7 failed
```

**Which case catches the fallback, precisely:** in the compose suite, none of
this slice's own cases — all seven reds are *pre-existing* main-thread cases,
which now carry the decoy because `pre()` and `feed()` stamp it on every
payload. Slice 4's case 9 cannot catch it and does not need to: its `feed a1`
payload carries `agent_id`, which wins under `//`. In the
**add-tier suite, zero cases failed.** Its nine pre-existing cases pre-create no
compose stamp, so the `rm -f` is unobservable to them, and the one new case
supplies `agent_id`, under which `.agent_id` and `.agent_id // .agent_type` are
the same string. The decoy that `run_batch()` adds to every payload was catching
nothing, while the header comment asserted it was "the decoy a hook that falls
back to `agent_type` would key on by mistake".

The catching shape has to be a *main-thread* batch with a baseline to drop. The
new case is that: bare stamp and an `agent_type`-keyed decoy stamp both
pre-created, `run_batch` with no agent id, then the bare one must be gone and
the decoy must not. Under M2 it reds on `[ ! -f "$bare_stamp" ]` (`:168`) and is
the only add-tier case that does.

It **passes against today's unkeyed code**, deliberately — it is a regression
guard on the runbook's own slice-1 contract ("Empty or absent yields today's
unsuffixed name, which stays the main thread's, so nothing migrates"), pinned at
the consumer for the first time. Same shape as the second phase slice 3's test
review added to its case 1, and the reason the final count is 25/3 rather than
24/3.

### Minor — a file-wide `shellcheck disable` in `cc_hook_add_tier.bats` that suppresses nothing

**Fixed**, `tests/cc_hook_add_tier.bats` header (formerly `:5-8`). The RED phase
added `# shellcheck disable=SC2119,SC2120` with a three-line rationale claiming
SC2119/SC2120 flag the argument-less `run_batch` calls. They do not: every call
site in that file is `run run_batch`, and shellcheck does not resolve a call
through bats' `run`. Verified by deleting the directive from a scratch copy —
`shellcheck -s bash` emits nothing at all, and the pre-existing SC2030/SC2031
directive keeps applying on its own.

A blanket `disable` that currently suppresses nothing is not free: it silently
absorbs the first *real* SC2119/SC2120 that appears anywhere in the file later.
Removed, with its rationale comment; the `run_batch` contract comment at the
function is untouched. `just lint` stays at `137 files clean`.

The same directive in `cc_hook_index_compose.bats` **is** load-bearing — the
same scratch-copy deletion produces SC2120 on `feed()` (`:52`) and SC2119 at the
three bare `feed >/dev/null` sites (`:146`, `:223`, `:238`). Kept, and its
comment corrected: it named `pre()` as a trigger, which is false (`pre` is never
called without `$1`, so SC2120 cannot fire on it), and it did not say why the
directive is file-scoped rather than sitting on the function. Now:

```sh
# feed()'s agent id is optional and most calls below omit it (a main-thread
# call), which is what SC2119/SC2120 flag as suspicious at the three bare
# `feed >/dev/null` sites — the argument is genuinely optional. Scoped to this
# file rather than to the function because SC2119 fires at the call sites.
```

## Mutation matrix

Six mutations, each applied in place to `scripts/cc-hooks/` and reverted. "as
committed" is the RED phase's two cases; "after fix" is the reviewed state. The
presumed GREEN (M1) is `payload=$(cat)` +
`agent_id=$(jq -r '.agent_id // empty' <<<"$payload")` in both hooks, with
`gitlore_compose_stamp_file "$mempath" "$agent_id"` at `index-compose.sh:32` and
`add-tier-batch.sh:75`.

| # | mutation | as committed | after fix |
| --- | --- | --- | --- |
| M0 | none — production as it stands (the RED baseline) | 24 ok, 2 red (`:173`, `:147`) | 25 ok, **3 red** — `cc_hook_index_compose.bats:181`, `:207`, `cc_hook_add_tier.bats:143` |
| M1 | presumed GREEN | 26 ok, 0 red — satisfiable | **28 ok, 0 red** — still satisfiable, nothing over-specified |
| M2 | GREEN reading `.agent_id // .agent_type` | 19 ok, 7 red — **all seven pre-existing compose cases; zero add-tier** | 20 ok, 8 red — adds `cc_hook_add_tier.bats:168` |
| M3 | GREEN, but `rm -f` stays on the bare compose stamp | **26 ok, 0 red** — ships | 27 ok, 1 red — `cc_hook_index_compose.bats:207` |
| M4 | GREEN, plus `[ -z "$agent_id" ] \|\| exit 0` (subagents never compose) | **26 ok, 0 red** — ships | 27 ok, 1 red — `cc_hook_index_compose.bats:205` (`grep -qF`) |
| M5 | GREEN, but add-tier drops the keyed **and** the bare stamp | 25 ok, 1 red — `cc_hook_add_tier.bats:148` | 27 ok, 1 red — `:144`, `[ -f "$bare_stamp" ]` |
| M6 | GREEN, but falls back to the bare stamp for reading and removes nothing | n/a — masked by the assertion order | 27 ok, 1 red — `cc_hook_index_compose.bats:182`, `[ -z "$output" ]` |

M1 matters as much as the reds: it is the only evidence that GREEN has a
reachable target and that neither the committed assertions nor mine over-specify
the contract. M3 and M4 are the two findings that motivated Major 2; M2 is the
one that motivated Major 3.

Line numbers in the "after fix" column are from the final tree, after the header
edits under Minor.

## Assessed, no defect

### The helper changes follow the established contract

`pre()` (`:37`), `feed()` (`:54`) and `run_batch()` (`:29`) each take an
optional trailing agent id, exercised directly rather than read: absent and
empty both **omit `agent_id` entirely** — neither emits `"agent_id": ""` — and
non-empty adds it. That is the same absent/empty-vs-non-empty contract as
`gitlore_index_preimage_file` / `gitlore_compose_stamp_file`
(`scripts/lib/index-sync.sh:94,102`, where `_gitlore_agent_suffix`
short-circuits on an empty `$1`) and as `batch_payload`'s `TEST_AGENT_ID`
(`tests/index_sync.bats:186-200`). The value crosses into jq through `--arg`,
never through word splitting.

The mechanism differs from `batch_payload`'s — a positional argument rather than
an env var — which is right here: `pre()` already takes `$1`, so a second
positional is the natural extension, whereas `batch_payload`'s arguments are a
variadic file list with no room for one.

### The 24 pre-existing cases still drive the behaviour they did

They do **not** drive byte-identical payloads: every one now carries
`agent_type:"general-purpose"`, and `pre Bash` moved from a `printf` literal to
`jq -n`. Both are inert against production as it stands —
`grep -rn 'agent_type' scripts/` returns two hits, both comment lines in
`index-sync-post.sh`, so no script reads the field — and all 24 pass unchanged
in the baseline run. Under a future GREEN the widening is a strengthening, not a
weakening: M2 above shows seven of them turning red on the forbidden fallback,
which is exactly what the decoy is for.

### Whitespace and hostile input

Run, not judged by reading. Both suites under
`TMPDIR="/tmp/claude-1000/space dir"`, so the temp repo and therefore the memory
gitdir path contain a space: **25 passed, 3 failed**, identical to the normal
run, and the wrapper's own log landed at
`/tmp/claude-1000/space dir/gitlore-bats.9EK08l`, which is what proves the
spaced `TMPDIR` really reached the test process and `setup_tmp_repo`'s
`mktemp -d "${TMPDIR:-/tmp}/…"`.

No glob and no `ls` pipeline asserts absence anywhere in this slice: every
absence is `[ ! -f "$var" ]` against one fully-resolved path, so the bash 3.2
unmatched-glob-stays-literal hazard does not arise, and `find` is not needed
here (it is needed in `tests/index_sync.bats:180-184`, where the assertion is
"no keyed file of *any* name"). Every `$( )` result is captured into a variable
or used inside double quotes. The agent ids driven are `a1` and
`general-purpose`; the hostile-id path is `_gitlore_agent_suffix`'s and is
pinned by slice 2's boundary case, not re-litigated here.

### bash 3.2 and BSD

The added lines use `printf`, `[`, `[[ ]]`, `grep -qF`, `jq` and plain
assignment. No arrays, no `${var^^}`, no `**`, no process substitution. No
`find`, `sed`, `stat` or `mktemp` added, so nothing new meets
`tests/helpers/bsd-stubs.bash`. `grep -qF` with a literal pattern behaves
identically on BSD and GNU. No bare top-level `!` (SC2314) was added — the two
`!` occurrences are inside `[ ]`.

### Ambient environment

Both suites under `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` — 25 passed, 3
failed, identical, so the result is neither dispatch-only nor human-only.

### `feed()`'s dropped comment

The RED phase removed "The payload is drained and ignored; an empty object is a
faithful stand-in." Correct to remove: `index-compose.sh:23` still drains, but
the sentence's *conclusion* — that any payload is as good as another — is what
this slice falsifies. The replacement says the contents stay drained while the
agent id steers the baseline, which is true of both the current and the intended
hook.

## Findings deliberately not fixed

- **The RED report's line numbers and its "2 failed" count are now stale.**
  `plans/index-edit-propagation/reports/item-2-1-s4-red.md:17-24` quotes `:173`
  and `:147`; both moved, and case 9's failing assertion is now a different one.
  The RED report is a record of the RED run and is out of this dispatch's scope
  to rewrite — flagged the way slice 3's test review flagged the same drift.
- **The RED report's "both remaining assertions independently discriminate"
  evidence** rests on scratch copies (`tests/scratch_compose.bats`,
  `tests/scratch_add_tier.bats`) that were deleted. The claim is true — M5 and
  M6 above re-establish it against the tree that ships — but the report's own
  proof is unreproducible. Not edited, same reason.
- **The rationale duplication slice 3's code review flagged for this slice.** It
  predicted that a third and fourth consumer copying the
  `agent_id`-never-`agent_type` paragraph is the point at which it should move
  to the headers of `gitlore_index_preimage_file` / `gitlore_compose_stamp_file`
  in `scripts/lib/index-sync.sh`. That is a GREEN-phase call about production
  comments; nothing on the test side blocks it either way.
- **`add-tier-batch.sh:20` and `index-compose.sh:18-23`** both carry header
  comments that the runbook says become false once the payload is read. Not a
  test-side matter; GREEN's, and the runbook already names both.

## Checks that passed, by name

- `scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats`
  on the untouched tree — 24 passed, 2 failed, byte-identical to the RED report
  including both line numbers.
- `git show HEAD:tests/cc_hook_index_compose.bats | grep -c '^@test'` = 15 and
  the same for `cc_hook_add_tier.bats` = 9 — confirms the 24 baseline is the
  pre-existing cases and nothing else.
- `grep -rn 'agent_type' scripts/` — two comment lines in `index-sync-post.sh`,
  no code — the evidence that the decoy is inert against production as it
  stands.
- Mutations M0-M6, each against the cases as committed and again after the fix —
  matrix above, each with its failing assertion line.
- `scripts/run-bats.sh …` after the fixes — **25 passed, 3 failed**.
- The same under `TMPDIR="/tmp/claude-1000/space dir"` — 25 passed, 3 failed,
  with the wrapper log landing inside the spaced directory.
- The same under `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` — 25 passed, 3
  failed.
- Scratch-copy deletion of each `# shellcheck disable=SC2119,SC2120` block —
  compose file emits SC2120 + 3×SC2119 without it (load-bearing), add-tier file
  emits nothing (dead, removed); deleting the pre-existing SC2030/SC2031 block
  also emits nothing, so the two directives were not shadowing each other.
- `shellcheck -s bash tests/cc_hook_index_compose.bats tests/cc_hook_add_tier.bats`
  — exit 0.
- `just lint` — `lint-shell: 137 files clean`, exit 0, before and after the
  directive removal; same count as slices 1-3, so nothing was added or left
  behind.
- `git status --porcelain -- scripts/ tests/` — the two test files modified,
  nothing else; no untracked path under `tests/` or `scripts/`.
- Residue sweep — no `.orig`, `.rej`, `.bak` or `scratch_*` anywhere outside
  `.git/`.

## Restore proof

Every mutation was applied in place and reverted with
`git checkout HEAD -- scripts/cc-hooks/`. Before the first mutation and after
the last:

```
$ sha256sum scripts/cc-hooks/index-compose.sh scripts/cc-hooks/add-tier-batch.sh \
            scripts/cc-hooks/index-sync-pre.sh scripts/lib/index-sync.sh
6d87a7788aa865302869b1ec6834dd07fd5570cd00ff6fef9c6f1142454d38cb  scripts/cc-hooks/index-compose.sh
cf9f7509829574cb47f8fa0cd0bbd55db412833b73c83d293f11ed15f6dc0546  scripts/cc-hooks/add-tier-batch.sh
73b9b5cd5e7747f789fe4369a690b278b400f6b7fdeb4571d7b1d19f608af22e  scripts/cc-hooks/index-sync-pre.sh
64f9d191243e685eda56bcb76456954306083bd22d21a6c087af1c8f65596c59  scripts/lib/index-sync.sh
```

Identical before and after (`diff` of the two captures is empty). `73b9b5cd…`
and `64f9d191…` are the shas slice 2's and slice 3's reviews recorded for the
two files I did not mutate at all.

```
$ git status --porcelain -- scripts/
(no output)
$ git diff HEAD --stat -- scripts/
(no output — covers content and mode)
```

The mutation driver lived at `/tmp/claude-1000/mutate.py`, never under `tests/`
or `scripts/`. The two scratch `.bats` copies used for the shellcheck directive
check were written to `/tmp/claude-1000/` and deleted.

## For GREEN

- **Read `.agent_id`, never `.agent_type`.** Pinned in the compose suite by
  seven pre-existing cases and in the add-tier suite by
  `tests/cc_hook_add_tier.bats:168` — the only case in that file capable of
  seeing it.
- **Key the removal, not just the lookup.** `index-compose.sh:50`'s
  `rm -f "$stamp"` and `add-tier-batch.sh:75`'s
  `rm -f "$(gitlore_compose_stamp_file …)"` are both pinned now (M3, M5); before
  this review neither was.
- **A subagent's compose hook must actually compose.** M4 — bailing whenever
  `agent_id` is set — passed every case in both suites before
  `tests/cc_hook_index_compose.bats:192` existed.
- **`[ -z "$output" ]` at `tests/cc_hook_index_compose.bats:182` is the one
  assertion RED does not exercise**, because the reordered survival assertion
  above it fires first. It discriminates (M6) but has not been shown to fail
  against the tree as it stands.
- **`tests/cc_hook_add_tier.bats:155` passes today**, by design. It is a
  regression guard on the empty-id-stays-bare contract, not a red to make green;
  if it turns red during GREEN, the empty case has been broken.
- `add-tier-batch.sh` drains with `cat >/dev/null || true` under
  `set -euo pipefail`; the runbook prescribes `payload=$(cat || true)` there. M1
  used exactly that and all 28 cases pass, including the two no-op guards that
  exit before the payload would matter.

## Files touched

- `tests/cc_hook_index_compose.bats` — assertion reorder in case 9, one new
  case, header comment corrected.
- `tests/cc_hook_add_tier.bats` — one new case, dead shellcheck directive and
  its rationale removed.
- `plans/index-edit-propagation/reports/item-2-1-s4-test-review.md` — this
  report, untracked.

Nothing staged, nothing committed. `just precommit`, `just test-unit` and
`just test-integration` were not run, per the dispatch. The tree is left dirty
and unstaged.

## Out of scope, untouched

- `scripts/cc-hooks/index-compose.sh` and `add-tier-batch.sh` — mutated for
  discrimination only, restored byte-identical (proof above). Neither learns to
  read `agent_id` in this dispatch, and neither does.
- `scripts/cc-hooks/index-sync-pre.sh` and `scripts/lib/index-sync.sh` — read
  only, never mutated; shas above.
- `tests/index_sync.bats` — slices 1-3's, read only.
- `plans/index-edit-propagation/reports/item-2-1-s4-red.md` — stale line numbers
  and count flagged above rather than edited.
- `docs/`, `memory/`, and everything under `plans/` other than this report.

## Gate note

`tests/` is a `precommit_inputs` gated input, so this review's edits invalidate
whatever sentinels the RED run left under `.git/gitlore/gates/`. The
orchestrating session's commit needs a fresh `just precommit` in the foreground
— and it will be red until GREEN lands, which is the expected state for a
RED-phase tree.
