# Phase 1 boundary checkpoint — index-edit propagation

Scope: `git diff 843bb12..HEAD -- scripts/ tests/` plus
`plans/index-edit-propagation/runbook.md`'s Item 1.1 section, against FR-B — "a
memory commit never records a carrier stale against the root index".

**Verdict: Phase 1 satisfies FR-B.** The compose lands on the shared body both
entry points call, in the position the four slices assert, and the carrier that
reaches a tier's remote is the composed one. Three fixes applied (§Fixes
applied), all in the phase's own files. Six items are left for my human partner
to decide (§Decisions for my human partner) — three carried in by the dispatch,
three found here. Nothing was committed or staged.

---

## Decisions for my human partner

Read this section on its own. Nothing here is implemented; each item states the
current behaviour, what each option costs, and a recommendation.

### D-1 — a memory commit adopts an off-pin tier gitlink (carried item 1)

**Verified against the code as committed**, through the `pre-commit` entry
point, with a scratch bats probe deleted in the same call. The tier's carrier
held an approved upstream fact; root's index line carried older text:

| | after run 1 | after run 2 |
|---|---|---|
| exit | 0 | 0 |
| refusal on stderr | `tier composition refused … is checked out at …` | *none* |
| `memory` records for the tier | `f65f48e` (the tier's *moved* HEAD) | `f65f48e` |
| tier carrier | `— upstream fact` | `— root older text` |

Run 1 is a rc-1 refusal that reports and lets the commit proceed; the commit's
own `add -A` then stages the tier's moved gitlink, which removes the very
condition `gitlore_compose_check_pins` refused on. Run 2 — any later memory
commit, SessionStart, or a `PostToolBatch` compose — projects root's older text
over the carrier with no refusal at all, and `gitlore_sync_tiers_to_live` then
commits it inside the tier and advances that tier's local `live` — which
`pre-push` publishes to the tier's own remote. So the approved upstream fact is
destroyed, and then shipped, one commit after the warning.

The `item-1-1-s3-code-review.md` Major 2 account holds. This is
**not a regression**: `add -A` predates the whole job, and before the commit
path composed at all the same sequence ended in the same overwrite at the next
SessionStart. What Phase 1 adds is one more trigger for run 2, and a warning at
run 1 that did not exist before.

**Correction to the dispatch's framing of option (b).** The brief says excluding
refused tiers from the memory `add -A` "touches the staging the `GIT_INDEX_FILE`
handoff depends on — i.e. Phase 2's territory". It does not. `GIT_INDEX_FILE`
appears in `scripts/git-hooks/pre-commit:17,75` and
`scripts/git-hooks/pre-push:5` only, and it is about the **parent** repo's index
staging the `memory` gitlink — a different index from the memory store's own
`git -C "$mempath" add -A`. Phase 2's file list (`scripts/lib/index-sync.sh`
plus four `scripts/cc-hooks/` consumers) does not include
`scripts/lib/resolve.sh` at all. Option (b) is expensive for other reasons,
below, but not for that one.

**Sizing.**

- **(a) Abort on a pin-mismatch rc 1**, narrowed to the pin subset.
  `gitlore_compose` collapses `gitlore_compose_check` and
  `gitlore_compose_check_pins` into one rc 1, so the call site cannot tell a
  stale pin from a broken index line. The cheap way is to call
  `gitlore_compose_check_pins "$mempath"` at the call site *before*
  `gitlore_compose` and abort on its refusal — about six lines, pure reads (one
  `rev-parse` per active tier), and it leaves `gitlore_compose`'s 0/1/2 contract
  untouched, so the `*)` arm's comment and slice 4's stub test stay true. It
  contradicts the runbook's "commit proceeds" rule, but that rule was written
  about rc 1 as a whole; the pin case is the only one of the two with a
  destructive consequence. Cost to the user: an off-pin tier blocks every
  **parent** commit until they return the tier to its pin or run
  `/gitlore:merge`. That is severe, and it is exactly the shape
  `gitlore_guard_stale_merge_state` already commits to for a comparable
  condition — and the refusal is self-describing, carrying the verbatim
  `checkout --detach <pin>` command.

- **(b) Exclude refused tiers from the memory `add -A`.** Three coupled changes,
  not one: the call site needs a machine-readable list of pin-refused tiers
  (parsing `$compose_result`'s prose is not it); the index entry has to be put
  back after `add -A` (`git -C "$mempath" reset -q -- "$tier"`, which restores
  from **HEAD**, not from `:$tier`, so it is only equivalent while those agree);
  and `gitlore_sync_tiers_to_live` has to stop committing and pushing inside a
  refused tier too, or the tier's HEAD advances further while memory keeps the
  old pin. That last state is the "local `live` ahead of the pin" shape
  `tests/helpers/tier-fixtures.bash:strand_live_ahead_of_pin` exists to
  reproduce as a field defect. A slice of its own, with tests.

- **(c) Record as a known residual and do neither.** Defensible: not a
  regression, and the warning at run 1 is new and now accurate about the pin
  figure going stale.

**Recommendation: (a), narrowed to the pin subset, as a follow-up item — not
inside Phase 1.** It is the smallest change that actually stops the loss, it
reuses a refusal shape the codebase already commits to, and it does not
manufacture the live-ahead-of-pin state that (b) does. The trade being made is
silent destruction of approved upstream facts against a blocking,
self-describing refusal, and every other D31/D36 decision in this codebase takes
the refusal. It needs the runbook's rc-1 rule amended to say "a compose_check
refusal proceeds; a pin refusal aborts", so it is a decision, not a review fix.

### D-2 — four remedy sentences are pinned by nothing (carried item 2, widened)

The dispatch carried this as one sentence on an unreachable arm. Measured by
in-place mutation against the committed tree, it is **four**, and two of them
are on arms an agent actually reaches. Each mutation replaced one whole sentence
and ran `tests/commit_memory.bats tests/git_hook_pre_commit.bats`; the SUT was
restored with `git checkout HEAD --` and `git diff --exit-code` proved clean
after each.

| mutated sentence | `resolve.sh` arm | result |
|---|---|---|
| `This commit also stages each tier at the commit its worktree is on now, …` | rc 1, **agent** | 33 passed, 0 failed |
| `Investigate that path (permissions, disk space, a read-only worktree), then retry the commit …` | rc 2, **agent** | 33 passed, 0 failed |
| `gitlore: the commit was aborted rather than commit a memory store in an unknown state. Establish what gitlore_compose did, …` | `*)`, agent | 33 passed, 0 failed |
| `gitlore: the commit was aborted rather than commit a memory store in an unknown state. Open this project in Claude Code and ask it to repair …, then retry.` | `*)`, user | 33 passed, 0 failed |

The `*)` user-arm result independently confirms `item-1-1-s4-code-review.md`
probe 5: the rc-2 and `*)` user arms end with the same sentence verbatim, so the
rc-2 user test cannot distinguish them.

What **is** pinned: each arm's header phrase, one forwarded problem-line
fragment per reachable arm, `unrecognised status (7)`, and the two *user* remedy
endings (`ask it to repair the memory store.` for rc 1, `…, then retry.` for rc
2).

The weight is higher than the dispatch assumed. The rc-1 agent sentence is not
incidental wording — it is the specific fix `item-1-1-s3-code-review.md` made
for its own Major 2, the sentence that tells an agent the pin figure printed
above is already stale. It reverts silently.

Closing all four is four `[[ "$stderr" == *"…"* ]]` lines added to tests that
already run with the right `CLAUDECODE` value and `--separate-stderr` — the rc-1
and rc-2 agent cases need one each, and the `*)` case needs one plus a second
case with `CLAUDECODE` unset. **Not applied**: the runbook enumerates each of
those tests' assertions by name, so this changes an accepted test's assertion
list. Recommendation: **take the rc-1 and rc-2 agent sentences** (two lines, two
reachable arms, one of them a fix that shipped without a test); leave the `*)`
arm's two as a recorded residual, since that arm is unreachable while
`gitlore_compose` returns only 0, 1 or 2.

### D-3 — `CLAUDECODE` in the ambient environment (carried item 3)

**Confirmed:** `CLAUDECODE=1` is exported in a subagent's environment
(`CLAUDE_CODE_ENTRYPOINT=cli` alongside it), and nothing in
`tests/helpers/setup.bash` scrubs it — bats inherits whatever the invoking shell
holds. The runbook's claim was wrong and is **fixed** (§Fixes applied).

`grep -rn CLAUDECODE tests/ scripts/` shows the only thing that branches on it
is `scripts/lib/log.sh:10`, so the exposure is message text, never an exit
status or a side effect. Audited empirically rather than by reading — the full
unit suite run under `env -u CLAUDECODE`:

```
bats: 782 passed, 2 failed
not ok 656 says memory stays local when it has no remote, and offers /gitlore:resolve
#   (tests/push_memory.bats, line 117)  `[[ "$stderr" == *"/gitlore:resolve"* ]]' failed
not ok 776 a naked commit inside a tier is blocked by the FR11 gate
#   (tests/tier_lockstep.bats, line 216) `[[ "$output" == *"approval gate"* ]]' failed
```

Both assert on strings that exist **only** in the agent arm
(`scripts/lib/resolve.sh:1177` and `scripts/git-hooks/memory-pre-commit:16`; the
user arms at `:1178` and `:17` carry neither), and neither test sets or unsets
`CLAUDECODE`. They pass here only because this session exports it. **They fail
for a human running `just test` from an ordinary terminal, and in any CI that
does not set it.**

Both are outside the phase's diff, so not fixed. The fix is one line each —
`CLAUDECODE=1` prefixed to the `run` at `tests/push_memory.bats:114` and
`tests/tier_lockstep.bats:215`, matching the idiom the rest of both suites
already use. Nothing else in `tests/` reads an arm-specific string without
controlling the variable: the only four such assertions are those two plus
`tests/git_hook_pre_commit.bats:36` and
`tests/git_hook_memory_pre_commit.bats:32`, and both of those set it explicitly.

Every case Phase 1 added is safe either way: the four that read one arm set or
unset it, and the rest assert on text common to both arms
(`unrecognised status (7)`, the two headers, the forwarded problem lines).

### D-4 — a successful compose on the commit path is silent

On rc 0 the captured `$compose_result` — `composed memory/<tier>/MEMORY.md`, one
line per file actually rewritten — is discarded. A commit that repairs a stale
carrier says nothing to anyone. The design chose this ("composition needs no
judgement, so making the agent run it is overhead the harness should absorb",
outline §Design record), and the FR11 argument is that a carrier is a projection
of root index lines the approved summary already covered. Named here so it is a
decision rather than an omission: the counter-argument is that a *non-empty*
`$compose_result` on the commit path means the in-session compose was missed,
which is the hole this job exists to close, and one line on stderr would say so.
Cost: one `[ -n "$compose_result" ]` branch. **Recommendation: leave it**; the
in-session `PostToolBatch` report is the intended surface and duplicating it at
commit time adds noise to every commit. Worth a sentence in Phase 4's decision
node.

### D-5 — the test suite does not neutralise `CDPATH`

Every entry point under `scripts/` opens with `unset CDPATH   # else \`cd\` may
echo its target into the $(cd … && pwd)
capture` (`scripts/resolve.sh:5`, `scripts/add-tier.sh:22`, `scripts/install/run.sh:3`, `emit-wrappers.sh:3`, and four more), and `gitlore_compose_check_pins` uses `CDPATH=''
cd --
…` inline. `tests/helpers/setup.bash` does not, and six test sites carry the raw pattern. Measured with `CDPATH=.`
exported:

```
not ok 2  exits 0 when memory is clean and synced
#   tests/helpers/fixtures.bash line 25: cd: $'…/parent-with-memory/memory\n…/parent-with-memory'
not ok 11 a tier holding a merge gitlore did not prepare is not composed into
```

The second was in Phase 1's diff and is **fixed** (§Fixes applied). The first is
`tests/helpers/fixtures.bash:25`, outside the diff. The store-wide fix is one
line — `unset CDPATH` in `tests/helpers/setup.bash`, which every suite loads —
and it would cover `tests/tier_divergence.bats:96,339,341,392`,
`tests/index_compose.bats:259` and `tests/resolve_recovery.bats:339` as well.
Recommendation: take it, as its own one-line change outside this job.

### D-6 — the up-front tier guard is broader than its comment says

The loop added ahead of the compose iterates `gitlore_tier_paths` (every tier in
`.gitmodules`), while `gitlore_compose` only ever writes into tiers listed in
`.gitlore-tiers`. Its comment justifies the loop by "the compose below writes
carrier files inside the tier worktrees", which is false for a dormant tier. The
loop is nonetheless right at that width, because it mirrors
`gitlore_sync_tiers_to_live`'s own enumeration — which commits inside dormant
tiers too (`tests/tier_lockstep.bats`, "a mounted but unlisted tier is still
committed") — so hoisting the guard is a strict improvement: a run that would
have committed tier A and then aborted on tier B's stale merge now aborts before
touching either. Not fixed, because the correct comment states a reason
(ordering against the tier commits) the dispatch did not ask me to introduce and
which reads as design text. One sentence if my human partner wants it.

---

## Fixes applied

Three, uncommitted and unstaged.

1. **`tests/commit_memory.bats`** —
   `gd=$(cd memory/ddaanet && cd "$(git rev-parse --git-dir)" && pwd)` replaced
   with `gd=$(git -C memory/ddaanet rev-parse --absolute-git-dir)`, with the
   reason in a comment. Load-bearing, not cosmetic: under `CDPATH=.` the old
   form captured two lines and the test failed on
   `git -C memory/ddaanet rev-parse HEAD > "$gd/MERGE_HEAD"` (measured, above).
   The replacement is the idiom `tests/tier_discovery.bats:67` and
   `gitlore_compose_write` (`scripts/lib/index-compose.sh:655`) already use, and
   `--absolute-git-dir` rather than `--git-path` for the reason that call site
   gives. The line came verbatim from `item-1-1-s1-code-review.md`'s suggested
   snippet.

2. **`plans/index-edit-propagation/runbook.md:84`** — "picks by `CLAUDECODE`,
   which a bats run does not set" was false (D-3). Now states that bats neither
   sets nor clears it, that a test inherits the invoking shell's value, that a
   subagent dispatch has `CLAUDECODE=1`, and that a case reading one arm has to
   set or unset it in the test body.

3. **`plans/index-edit-propagation/runbook.md:300`** — the same claim in slice
   4's third test ("which is the state a bats run leaves it in anyway"),
   corrected the same way.

`rumdl fmt` was run on the runbook only; the diff carries nothing but those two
paragraphs, and no new line over 80 columns.

---

## The phase's diff, reviewed

### FR-B is met

`gitlore_sync_memory_to_live` is the only body behind both entry points
(`scripts/git-hooks/pre-commit:68`, `scripts/commit-memory.sh:66`), and both
have a case asserting the *committed* carrier —
`git -C memory/ddaanet show HEAD:MEMORY.md` — equals the composed block exactly,
plus `git -C memory rev-parse HEAD:ddaanet` == the tier's `HEAD`, which is what
makes the composed carrier the one the memory commit records and the one the
tier's remote receives.

### The placement is asserted, all four properties

| property | pinned by |
|---|---|
| after the freshness read | slice 1's two cases (a compose ahead of it stales the summary, the commit is refused, the carrier never lands — reproduced as collateral in `item-1-1-s2-green.md`'s mutation) |
| inside the `dirty = 1` branch | `a clean store is not composed by the commit path`, on `gitlore_memory_dirty` |
| before `gitlore_sync_tiers_to_live` | slice 1's `assert_bullets` on `HEAD:MEMORY.md` (mutation: compose moved after the tier sync reds both cases, `item-1-1-s1-code-review.md`) |
| after the per-tier stale-merge guard | `a tier holding a merge gitlore did not prepare is not composed into`, on the carrier's unchanged text |

### The `case` is exhaustive and each arm's message is accurate

`0 / 1 / 2 / *)`. Checked against the source rather than the reports:
`gitlore_compose` (`scripts/lib/index-compose.sh:800-853`) exits only through
explicit `return 0`, `return 1`, `return 2`, so no internal status leaks. rc 1's
"left untouched" is true — `gitlore_compose_check` and
`gitlore_compose_check_pins` both run before any write and the function returns
before `gitlore_compose_down`. rc 2's "only partly composed" is true — the tier
loop returns 2 mid-way, after emitting `$changed` for what was written. Both
headers are byte-identical to `gitlore_compose_and_report`'s own at
`index-compose.sh:779` and `:787`, and the two cited line numbers are exact.

`local compose_result compose_rc=0` is declared ahead of the assignment, so the
status captured is the command substitution's and not `local`'s.

### `tests/index_compose.bats`'s rewritten comment is correct

Verified from `gitlore_compose_write` (`:646-677`): the temp file goes to
`git -C "$(dirname -- "$file")" rev-parse --absolute-git-dir`, which for a tier
is `<parent>/.git/modules/gitlore-memory/modules/<tier>` — outside the
`chmod a-w`'d directory, so it is created fine. `cmp -s` then differs, and the
`mv` into `memory/ddaanet/` is what needs write permission on that directory and
what fails. The old comment ("the temp file cannot be created there") was wrong;
the new one is right, including "to create the destination entry".

### Whitespace safety and BSD / bash 3.2

Clean, with one exception fixed above.

- No expansion is split on whitespace. Both new loops are `while IFS= read -r`
  over `gitlore_tier_paths`, which is NUL-delimited internally
  (`scripts/lib/util.sh:365`, `git config -z --get-regexp`), so a tier path with
  spaces survives; a path with an embedded newline is out of scope by that
  helper's own construction, unchanged by this diff.
- `case "$compose_rc"`, `"$compose_result"`, `touch "$msgfile"`,
  `"$mempath/$tier"` all quoted.
- No bash-4 construct. `local` inside a `case` arm is function-scoped and fine
  on 3.2. `touch` with no flags is POSIX and identical on BSD. No GNU-only
  `sed`/`find`/`stat`/`grep`/`mktemp` added. Process substitution matches the
  existing consumer four lines below.
- The tests add `chmod`, `id -u`, `sleep`, `printf`, `cmp`-free git plumbing —
  nothing BSD-divergent. `[ "$(id -u)" -eq 0 ] && skip …` as a leading statement
  is safe under bats' errexit (a failing non-final command in an `&&` list does
  not exit) and is the guard `tests/index_sync.bats:356` already carries.

### Test quality, and the two waived phases

- **Slice 2's mutation evidence carries.** The mutation hoists the compose out
  of the `dirty = 1` branch entirely, and the negative reds on
  `[ "$(gitlore_memory_dirty memory)" = "0" ]` — the discriminating assertion,
  not a fixture error — while the positive stays green in its control role. The
  conflation the report notes (the hoist also puts compose ahead of the
  freshness read, redding slice 1's case as collateral) is unavoidable: the
  freshness check lives *inside* the dirty branch, so there is no placement that
  is unconditional and still after it. The collateral lands on a different test
  from the one under review, so slice 2's own discrimination is clean.
- **Slice 4's shape is sound.** Its two freshness tests have a genuine RED — the
  `touch` lines were backed out and both redded on their own assertions — and
  the two characterization tests are discriminated by the mutation table, which
  I re-ran independently for three further sentences (D-2). No implementation
  diff is the right outcome for a slice whose job was to test an untested fix.
- **No overlap worth removing.** Three cases exercise the rc-2 arm — agent text
  through `commit-memory.sh`, user text through the same induction, and the
  two-tier freshness case through the hook — and each pins something the others
  do not. Slice 1's two cases are the same store through the two entry points,
  which the runbook justifies and which is the point of FR-B.
- **The seams that remain** are D-2 (four remedy sentences) and D-4 (silent rc
  0). Nothing else in the diff is unasserted.

### Reuse and simplification — considered, nothing taken

- The up-front guard loop duplicates `gitlore_sync_tiers_to_live`'s enumeration,
  its `[ -e "$tierpath/.git" ]` submodule-escape guard and that guard's comment.
  A shared `gitlore_guard_tiers_stale_merge_state` helper would remove ~6 lines,
  but the second call site is *inside* the other function's per-tier loop and
  cannot use it, so the helper would have one caller. Left alone.
- The rc-2 and `*)` arms are near-identical (message, `touch`, `return 1`) and
  could collapse to `2|*)`. That would cost the `*)` arm its own
  `unrecognised status (…)` text, which is the only thing distinguishing an
  unknown status in the log. Left alone.
- Each arm's header already lives in one `local` variable interpolated into both
  `gitlore_say_for_agent_or_user` arguments — the drift risk is closed. Going
  further and factoring the shared remedy tails is what makes the arms
  indistinguishable to a test (D-2). Left alone.
- The `add -A` / `commit` / `rm -f "$msgfile"` sequence is untouched by this
  phase and correct: the two aborting arms return before all three.
- Cost added to every dirty memory commit: one `gitlore_compose` pass (reads
  each index, one `rev-parse` per active tier, and a `cmp -s` that skips the
  write when a carrier is already composed — `index-compose.sh:672`), plus a
  second `gitlore_guard_stale_merge_state` per tier, which is two `rev-parse`s
  and two `[ -f ]` once the first call has left the state clean. Nothing here is
  worth optimising.

---

## Verification

- Probe for D-1: scratch bats case under `tests/`, run through
  `scripts/run-bats.sh`, deleted in the same call; `git status --short` clean
  for `tests/` afterwards.
- Mutations for D-2: four, each asserting the target sentence's exact current
  text before editing; `git checkout HEAD -- scripts/lib/resolve.sh` and
  `git diff --exit-code scripts/lib/resolve.sh` after each, all clean.
- `CDPATH=.` run of `tests/commit_memory.bats` against the unfixed file
  (restored immediately) — 2 failed; with the fix and `CDPATH=/tmp`,
  `tests/commit_memory.bats tests/git_hook_pre_commit.bats` — 33 passed, 0
  failed.
- `env -u CLAUDECODE` over every non-integration suite — 782 passed, 2 failed
  (D-3); over `tests/integration_*.bats tests/evals/lib/*.bats` — 72 passed, 0
  failed, so the audit is complete and those two are the whole exposure.
- `just precommit` over the tree as it now stands — **exit 0**.
  `check-memory-hygiene` 0 errors (32 pre-existing `deictic` warnings),
  `check-docs-links` 0 across all nine checks, `check-version: in sync (0.7.1)`,
  `lint-shell: 137 files clean`, unit `784 passed, 0 failed`, integration
  `72 passed, 0 failed`, `check-distribution` cached. Sentinels rewritten at
  11:18:39 (`test-unit`) and 11:19:35 (`test-integration`), both postdating the
  last edit to any gated input.
- `scripts/lib/resolve.sh` is byte-identical to `HEAD` after every mutation —
  `git hash-object` == `git rev-parse HEAD:scripts/lib/resolve.sh`. Its mtime
  moved, but the gate keys on a content hash, not mtime, and the run above
  postdates the last restore either way.
- Tree: only the three fixes above, uncommitted and unstaged. The untracked
  dotfiles at the repo root were not touched. `memory/`, `CLAUDE.md` and the two
  `.claude/handoff-*.md` files were not read for review and not edited.
