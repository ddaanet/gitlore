# Item 3.1 slice 5 — code review (whole-surface, GREEN phase)

Four fixes applied, all to comments except two: `session-start.sh` loses a
`|| true` that slice 5 made redundant, and `index-sync-post.sh` seeds its
`additionalContext` from `$sysmsg` when the channel would otherwise be empty, so
the not-staged line's own "the report above" has an antecedent on the one path
the runbook names as reachable for that hook.

Nothing committed; the tree is dirty and unstaged. No `just` recipe run.

The relay surface is sound. Its failure policy is coherent once stated in one
place, which it now is. Two coverage gaps are reported, not fixed: the tests are
frozen and both are unpinned by design or by measurement.

---

## 1. Accumulated comments — three were stale, all fixed

### 1a. The drain's `-type f` rationale contradicted the line it now sits above

`scripts/lib/index-sync.sh`, the comment on the `find`. As handed over it read:

```
  # `-type f` because a non-file squatting on a marker name — the shape a
  # failed relay write leaves behind — must be skipped rather than removed.
  # The block reads below tolerate a path they cannot open, but `rm -f` still
  # fails on a directory, and under the hooks' `set -e` that takes down the
  # whole hook, trading a lost relay for a lost report.
```

Two defects, in the same five lines.

**The second sentence is false as of this slice.** `rm -f "$marker" || true`,
seven lines below, is precisely the fix for "`rm -f` fails and takes down the
hook". The comment justifies `-type f` by an abort the same function no longer
causes — the fourth-slice pattern the brief warned about, one slice on.

**The first sentence is factually wrong about the mechanism, and always was.** A
non-file is not "the shape a failed relay write leaves behind": the write's own
contract, twelve lines earlier, says "the redirect below is the single write, so
a failed open leaves nothing on disk to clean up". The directory is what *makes*
the write fail, not what it leaves.

Rewritten to state what `-type f` is now for — which is what the companion case
`an unkeyed run leaves a non-marker alone` pins, and what M8 below measures:

```
  # `-type f` because anything else on a marker name is not a marker: framing
  # it would attribute a block to an agent that staged nothing, and `rm -f`
  # cannot remove it, so every later run would frame it again. That shape is
  # what makes a relay write fail in the first place — a directory already
  # occupying the marker path — not something a failed write leaves behind.
```

"every later run would frame it again" is the durable cost, and it does not
depend on errexit, so it cannot go stale the way the removed sentence did.

The `|| true` comment seven lines below is left as written: it explains a
different thing (the gitdir's mode, not the marker's shape) and does not overlap
once the sentence above is gone.

### 1b. `session-start.sh`'s `|| true` comment described a residual slice 5 closed

`scripts/cc-hooks/session-start.sh`. Eleven lines asserting that the drain's
`rm -f` "still propagates on a marker whose gitdir has been made unwritable, and
under this file's `set -e` a bare call would take the hook down". That is
exactly what this slice fixed.

The `|| true` itself is now the only guard on any of the drain's three call
sites — both PostToolBatch hooks call it bare and always have. **Removed**, and
the comment replaced by a statement of why no call site guards it:

```
# Called bare, as both PostToolBatch hooks call it: the drain absorbs every
# failure a marker or its gitdir can produce — one it cannot read folds as an
# empty block, an `rm -f` the gitdir refuses is swallowed — and returns 0 on
# every path, so there is no status to inspect and nothing here for this
# file's `set -e` to trip on. A guard at this one call site would imply the
# other two were taking a risk this one does not.
```

**Coverage delta of the removal: zero, measured.** Under M7 (the `|| true`
backed out of the drain, i.e. the defect this slice fixed restored),
`tests/cc_hook_session_start.bats` is **24 passed, 0 failed** — the suite has no
fixture that makes the gitdir unwritable, so the token was protecting a case
nothing here exercises. The protection lives entirely at the lib level, in
`the drain survives a gitdir it cannot write`, which calls the drain
**bare under `set -euo pipefail`** — the exact shape `session-start.sh` now uses
— and which M7 does red.

I re-enumerated every statement in `gitlore_relay_drain` for errexit exposure
before removing it: `git rev-parse` takes `|| return 0`; both block reads take
`|| …=""`; `rm -f` takes `|| true`; the `find` and the `printf | sort` are both
inside process substitutions, whose status the shell never examines; the
function ends `return 0`. The one unguarded expansion is `mempath="$1"`, which
would abort under `set -u` if a caller passed no argument, and all three pass
`"$mempath"`.

### 1c. Not stale, and deliberately duplicated

The nine-line `if !` comment is byte-identical in both hooks. That matches the
pair's existing convention — the `Keyed:`/`Unkeyed:` block immediately above it
is duplicated the same way — so it is consistency, not layering. Left alone.

Its claims check out: `if !` and `|| true` do suspend errexit identically;
`additionalContext` is the channel the slice's own case pins (M3); and the
append is after the write in both files.

---

## 2. Failure policy — coherent, and now stated once

The policy across the five functions and three call sites:

| operation | on failure | who reports |
|---|---|---|
| `gitlore_relay_write`, empty agent id | returns 1, writes nothing | caller |
| `gitlore_relay_write`, marker unopenable | returns non-zero, writes nothing | caller |
| `gitlore_relay_write`, existing marker unreadable | degrades to overwrite, returns 0 | nobody — the loss is what was already staged |
| `gitlore_relay_drain`, no gitdir | `return 0`, both vars empty | nobody |
| `gitlore_relay_drain`, marker unreadable | folds an empty block under its framing line, removes it | the framing line |
| `gitlore_relay_drain`, `rm -f` refused | swallowed, returns 0 | nobody |
| all three drain call sites | bare, no guard | — |
| both write call sites | `if !`, not-staged line on `additionalContext` | the acting subagent |

It is coherent: **the drain never reports and never fails; the write fails and
its caller reports, because only the caller has a channel.** The one place that
diverged was `session-start.sh`'s guard on the drain, fixed above.

Stated once, on `gitlore_relay_write`'s contract — the boundary where a caller
learns what it owes:

```
# Reporting a non-zero return is the caller's, because only the caller has a
# channel: both hooks guard the call with `if !` and append a not-staged line
# to their own additionalContext — never systemMessage, which inside a
# subagent reaches nobody — so the loss is at least known to the one agent
# that can carry it out. gitlore_relay_drain takes no such guard anywhere: it
# returns 0 on every path.
```

**One incoherence found in the policy's *content*, fixed** — see §5b: in
`index-sync-post.sh` the not-staged line could be the sole content of a channel
whose "report above" was on a different channel entirely.

---

## 3. The two join idioms — each matches its own file, and they are equivalent

Counted, not eyeballed:

- `index-compose.sh`: **3** `${VAR:+$VAR…}` joins (the two pre-existing
  relay-fold joins plus the slice-5 one), **0** `if [ -n … ]` joins. The two
  `if [ -n "$GITLORE_COMPOSE…" ]` in that file are *guards*, not joins.
- `index-sync-post.sh`: **10** `if [ -n … ]; then …=…` joins, **0** `${:+}`
  joins.

So each addition took its own file's sole idiom. Neither is an inconsistency.

**Identical output, measured** over five inputs including the ones that could
separate them:

| `$pre` | both produce |
|---|---|
| `''` | `LINE` |
| `A` | `A\n\nLINE` |
| `A\nB` | `A\nB\n\nLINE` |
| `' '` (whitespace only) | `' '\n\nLINE` |
| `'\n'` | `\n\n\nLINE` |

`SAME` on all five. The forms differ only on an **unset** variable, which cannot
occur: `index-sync-post.sh` initialises `ctx=""` before the branch, and
`gitlore_compose_and_report` assigns `GITLORE_COMPOSE_CTX` unconditionally on
every one of its exit paths.

---

## 4. The deletion

`an unkeyed run survives a non-file squatting on a marker name` is gone from
`tests/cc_hook_index_compose.bats`, with its `# Item 3.1 slice 4, Group B`
comment. Confirmed:

- **Its fixture and cleanup went with it.** The `mkdir "$squat"` /
  `rmdir "$squat"` pair lived inside the case body; both replacement cases carry
  their own copy. No shared fixture was orphaned.
- **Nothing else in the file moved.** `git diff` on that file is the retired
  block removed plus the two slice-5 additions and nothing between them; the
  sibling `a failed relay write leaves the subagent's own report intact`, which
  the retired case sat between, is byte-unchanged.
- **No helper is orphaned.** `seed_tier_bullet` (18 uses), `seed_root_fact`
  (19), `set_tier_manifest` (7), `pre`, `feed`, `sync_feed` and
  `gitlore_relay_marker_file` all still have live callers in that file.
- **The coverage it carried is carried elsewhere.** Its residual unique
  assertion was `[[ "$output" == *"recomposed tier pointers"* ]]` over a squat
  fixture; the companion asserts exactly that, over the same fixture, as its
  paired positive.

Not revisited: the deletion was the orchestrator's call and the test review
measured it dead three ways.

---

## 5. The not-staged line's own failure modes

### 5a. Encoding, double-append, emptiness — all clear

- **Em-dash and apostrophe survive `jq -n --arg`.** Round-tripped through
  `jq -n --arg c … | jq -r '.hookSpecificOutput.additionalContext'`: **exact**,
  byte for byte. jq emits the em-dash as raw UTF-8 (`342 200 224`) rather than
  `—`, and does so **under `LC_ALL=C LANG=C` too** — checked, since a hook
  inherits whatever locale the harness has. The apostrophe is not special in
  JSON and passes through unescaped; in the source it sits inside a
  double-quoted shell string, so the shell does not see it either.
- **Double-appending is unreachable.** In both hooks the append is straight-line
  code inside `if [ -n "$agent_id" ]` → `if [ -n "$sysmsg" ]` → `if ! write`. No
  loop, no second call site, no function that could re-enter. A hook cannot
  reach the branch twice within one process, and each PostToolBatch firing is a
  fresh process.
- **It cannot make an otherwise-empty report emit JSON.** In `index-compose.sh`
  the relay branch's guard (`[ -n "$GITLORE_COMPOSE_SYSMSG" ]`) is the
  *same expression* as the emission guard 27 lines below, so the branch is only
  ever reached on a run that was already going to emit. In `index-sync-post.sh`
  the guard is `[ -n "$sysmsg" ]` and the emission guard is `[ -n "$sysmsg" ]` —
  likewise identical. Neither hook gains an emission it would not have had.
- **It *can* add a `hookSpecificOutput` key where there was none** — in
  `index-sync-post.sh` only, whose emission omits that key when `$ctx` is empty.
  Measured; and it is right, since the key is the entire point of the line. The
  object itself is emitted either way.

### 5b. Defect found and fixed: "the report above" had no antecedent

In `index-sync-post.sh`, `$ctx` can be empty while `$sysmsg` is not. The
`failed` block sets `sysmsg` alone — every other block (`replaced`, `weak`,
`refused`, `budget`) sets both. And the `failed` branch is
**the path the runbook itself names as this hook's reachable one**: "an
unwritable gitdir makes the frontmatter sync fail, produces the `failed` report,
and then the drain kills the hook before it emits it."

On that path, as handed over, the subagent's `additionalContext` contained
exactly one line — "gitlore: **the report above** could not be staged … so
repeat it in your reply or it is lost" — with nothing above it, and with the
report it names sitting on `systemMessage`, which the confinement probe measured
as reaching nobody inside a subagent. The actor is told to repeat something it
was never shown. That defeats the slice's own argument on the one branch the
slice was justified by.

Fixed with one `else` arm, keeping the specified wording verbatim:

```sh
      if [ -n "$ctx" ]; then ctx="$ctx

"; else ctx="$sysmsg

"; fi
```

Verified over both shapes: the `failed`-only report now reads
`gitlore: index→frontmatter sync failed for: p.md` / blank / the not-staged
line; the `replaced` report is unchanged.

**`index-compose.sh` needs no such fallback and did not get one.** Every branch
of `gitlore_compose_and_report` sets `sysmsg` and `ctx` together — the compose
report, orphans, dangling, the triage nudge, rc-2 and the fail-safe, all six —
so `sysmsg` non-empty implies `ctx` non-empty there. The hook's own comment
already states the converse; the asymmetric fix follows an asymmetric fact.

**This deviates from the text the runbook specified**, which was the separator
guard alone. Flagging it prominently rather than burying it: backing it out is
one line, and the surrounding wording and placement are untouched. It reds
nothing either way (§7, M4/M6 — that hook's half is unpinned by design).

---

## 6. `set -euo pipefail`, bash 3.2, BSD, stdout discipline

- **`set -u`.** `${VAR:+…}` is one of the expansion forms exempt from nounset,
  so it is safe even on an unset variable; both variables are set regardless
  (§3). No new bare `$VAR` reference anywhere in the diff.
- **`set -e`.** The only new fallible construct is `rm -f "$marker" || true`.
  The appends are pure parameter expansion and assignment. `if !` suspends
  errexit over the write exactly as `|| true` did.
- **`pipefail`.** No new pipeline in the diff.
- **bash 3.2.** `${VAR:+…}`, `[ -n … ]`, multi-line double-quoted assignment —
  all POSIX-era. No `${VAR^^}`, no `[[ =~ ]]`, no associative array, no
  `local -n`. The diff adds **no external command at all**, so BSD `sed`/`grep`/
  `find`/`mktemp`/`stat` divergence cannot arise and
  `tests/bsd_portability.bats` is owed no new lock-in.
- **Whitespace safety.** Every expansion in the diff is double-quoted; nothing
  new is split, globbed or passed unquoted. The drain's `-print0` /
  `read -r -d ''` pair is untouched.
- **Stdout discipline.** All three callers still emit exactly one JSON object
  and nothing else. Traced every new statement: the appends write to variables,
  `rm -f`'s diagnostics go to stderr, and `session-start.sh` runs the drain
  under `exec 3>&1 1>&2`, so even a stray write from it lands on stderr rather
  than the parsed channel. No new path reaches stdout.
- `shellcheck -s bash` clean on all four files; `scripts/lint-shell.sh` clean on
  137 files.

---

## 7. Mutation table

Every mutation applied **in place** to the SUT (save → mutate → run → restore),
never to a test. Suites `tests/index_sync.bats tests/cc_hook_index_compose.bats`
unless stated. Restores verified byte-identical with `diff -q` against
pre-mutation copies before the final runs.

| # | file | mutation | result | what reds |
|---|---|---|---|---|
| — | — | baseline, GREEN as handed over | **109/0** | — |
| M1 | `index-compose.sh` | not-staged append moved **before** the write (so it is part of what is staged) | **109/0** | **nothing — gap, §8** |
| M2 | `index-sync-post.sh` | same | 109/0 | nothing |
| M3 | `index-compose.sh` | not-staged line on `systemMessage` instead of `additionalContext` | **108/1** | `a failed relay write tells the subagent it was not staged`, `cc_hook_index_compose.bats:469` |
| M4 | `index-sync-post.sh` | same | 109/0 | nothing (that half is unpinned by design) |
| M5 | `index-compose.sh` | `if !` reverted to `\|\| true` | **108/1** | same case, same line — **the compose one does red** |
| M6 | `index-sync-post.sh` | `if !` reverted to `\|\| true` | 109/0 | **nothing at all.** Only `index_sync.bats` and `cc_hook_index_compose.bats` reference that hook, so this is the whole suite's verdict, not a chunk's |
| M7 | `lib/index-sync.sh` | `rm -f "$marker" \|\| true` reverted to bare | **108/1** | `the drain survives a gitdir it cannot write`, `index_sync.bats:1259`, on `[ "$status" -eq 0 ]` |
| M7b | `lib/index-sync.sh` | M7, run over `tests/cc_hook_session_start.bats` | 24/0 | nothing — the basis for §1b's zero-coverage-delta claim |
| M8 | `lib/index-sync.sh` | `-type f` dropped from the drain's `find` | **108/1** | `an unkeyed run leaves a non-marker alone`, `cc_hook_index_compose.bats:492`, on the framing assertion `[[ "$output" != *"gitlore-relay agent a1"* ]]` — the companion is the case that reds, on the assertion it exists for |
| — | — | correct implementation, restored | **109/0** | — |
| — | — | **after this review's four fixes** | **109/0** and **205/0** | — |

Each of M3, M5, M7 and M8 is a **sole** red, on the assertion the case is named
for — no upstream status check, no fixture error, no cascade.

---

## 8. Reported, not fixed — two unpinned properties

Both are test-side; `tests/cc_hook_index_compose.bats` and
`tests/index_sync.bats` are frozen, so neither is mine to close.

1. **The ordering guarantee is unpinned in both hooks (M1, M2).** Moving the
   append *before* the write — so the not-staged line is staged into the marker
   and relayed to the parent on every **successful** keyed run, carrying a false
   claim — reds nothing. The shipped ordering is correct and its comment says
   why; nothing would catch a later edit that inverted it. Closing it needs a
   case that drains a successful keyed relay and asserts the folded
   `additionalContext` does *not* contain the not-staged literal, over the same
   fixture as the existing successful-relay case. Cheap, if the orchestrator
   wants one before Phase 4.
2. **`index-sync-post.sh`'s whole relay-failure branch is unpinned (M4, M6).**
   Already stated and accepted in the runbook ("nothing in either suite squats
   that hook's marker path"). My §5b fix lands on this same unpinned branch and
   inherits its status.

Out of scope, noted in passing and **not touched**:
`scripts/lib/index-compose.sh` carries a comment claiming "every caller invokes
this function as an `if` condition, which disables errexit for the whole call" —
`index-compose.sh:66` calls `gitlore_compose_and_report` bare, and
`gitlore_compose` itself is called as `result=$(…) || compose_rc=$?`. Neither is
an `if` condition. Harmless today; worth a look whenever that file is next open.

---

## 9. Checks that passed, by name

- **`./scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats`**
  — **109 passed, 0 failed**, after every fix.
- **`./scripts/run-bats.sh tests/cc_hook_session_start.bats tests/cc_hook_add_tier.bats tests/index_compose.bats tests/cc_hook_post_tool_use.bats tests/lib_util.bats tests/cc_hook_worktree_remove.bats tests/merge_memory.bats tests/tier_discovery.bats tests/tier_divergence.bats`**
  — **205 passed, 0 failed**, after every fix.
- **`shellcheck -s bash`** on `scripts/lib/index-sync.sh`,
  `scripts/cc-hooks/index-compose.sh`, `scripts/cc-hooks/index-sync-post.sh`,
  `scripts/cc-hooks/session-start.sh` — clean.
- **`./scripts/lint-shell.sh`** — 137 files clean.
- **Mutation round** — ten mutations (§7), each applied in place and restored;
  M3, M5, M7, M8 each a sole red on its own assertion; M1, M2, M4, M6 survive
  and are reported as gaps rather than papered over.
- **Every mutation restored before the final runs** — `diff -q` against
  pre-mutation copies of all four SUT files reported identical, and the only
  surviving difference from the handed-over GREEN is this review's four fixes.
- **Comment audit** — three stale comments found and rewritten (§1); no comment
  in the four files cites `plans/`, `memory/`, a runbook, a slice identifier or
  a line number (scanned, zero hits).
- **Join-idiom equivalence** — five inputs including whitespace-only and
  newline-only, `SAME` on all five; idiom counts per file confirm each addition
  matches its own file's sole convention.
- **Encoding round-trip** — em-dash and apostrophe exact through `jq -n --arg` →
  `jq -r`, under the default locale and under `LC_ALL=C LANG=C`.
- **Emptiness analysis** — relay-branch guard and emission guard are the same
  expression in both hooks, so the not-staged line cannot create an emission; it
  can add a `hookSpecificOutput` key in `index-sync-post.sh`, which is intended.
- **Deletion audit** — retired case gone with its fixture and cleanup, nothing
  else in the file moved, no helper orphaned, its residual assertion carried by
  the companion.
- **errexit re-enumeration of `gitlore_relay_drain`** — every statement checked
  before removing `session-start.sh`'s `|| true`; the only unguarded expansion
  is `mempath="$1"`, and all three callers pass an argument.
- **`git status --porcelain`** — the four SUT files and the two frozen `.bats`
  files modified, plus the untracked slice reports;
  **nothing staged, nothing committed**. No `just` recipe run, no background
  task started or awaited.
