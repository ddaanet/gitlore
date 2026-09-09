# Item 3.1 slice 4 — code review (GREEN phase)

Reviewed: the working-tree diff over `scripts/lib/index-sync.sh`,
`scripts/cc-hooks/index-compose.sh`, `scripts/cc-hooks/index-sync-post.sh`,
`scripts/cc-hooks/session-start.sh`. Every claim below was measured unless it is
explicitly marked as read-and-argued.

**Headline.** The three code changes are correct and I changed none of them. All
my edits are comments: four in the library, one in `index-sync-post.sh`, and a
rewrite of `session-start.sh`'s drain comment, which four slices of edits had
left describing a mechanism that no longer holds. Two substantive findings are
reported rather than applied, both because applying them would cost something a
frozen case currently pins — §1 (the silent relay-write failure; the dispatch
reserved it) and §6 (`gitlore_relay_drain` can still abort a caller, contra its
own doc line, and the cheap fix un-pins `-type f`).

---

## 1 · Question 1 — a failed relay write is silent to everyone

**Verdict: a signal is warranted. The channel the dispatch proposes is the wrong
one, on this project's own measurement.** Not implemented, per the dispatch.

### How reachable a failed write actually is

`gitlore_relay_write` returns non-zero on three paths. Enumerated against the
code, then reduced against what the two callers have already done by the time
they reach it:

| path | reachable from production? |
|---|---|
| empty `agent_id` | **no** — both callers are inside `[ -n "$agent_id" ]` (§2) |
| `gitlore_relay_marker_file` fails (`rev-parse`) | only if the store stopped being a git repo mid-batch; both callers have already resolved `mempath` and, in the compose hook's case, already composed through that gitdir |
| the single `>` redirect fails | EISDIR, EACCES, EROFS, ENOSPC/EDQUOT |

Of the redirect's errnos, EISDIR is the one the slice's own fixture induces and
nothing in production creates: the marker path lives inside the memory gitdir,
which is hook-owned state, and no gitlore code path ever `mkdir`s there. An
unwritable gitdir, however, reaches the relay write in **both** hooks, and I had
assumed otherwise until I read the code: `gitlore_compose_write` puts its temp
file in that same gitdir, but `gitlore_compose_and_report` *catches* the
resulting rc 2, sets its `sysmsg`/`ctx` to the "could not write an index — the
memory indexes are only partly composed" report, and returns 0. So
`index-compose.sh` arrives at the relay write with a non-empty sysmsg and a
gitdir it cannot write, the write fails, and `|| true` discards precisely the
report that says the store is half-composed. `index-sync-post.sh` reaches it the
same way through its `failed` branch, and also through branches that write
nothing at all (the budget and routing-key advisories).

So: rare in cause, but on the run where it happens the report lost is one of the
most consequential either hook produces.

### Who learns, today

| observer | learns of the loss? |
|---|---|
| the subagent (the actor) | **no** — it gets its own report, with nothing marking it as unrelayed |
| the parent session | **no** — by construction: the missing report is the thing that would have told it |
| the user | **no** — a subagent's `systemMessage` never reaches them |
| anyone reading stderr | only under `--verbose` |

Silent to everyone, and it defeats FR-D on the run where FR-D applies. The
project rule ("silent-to-everyone must be fixed") is not the only thing pointing
here: `memory/ddaanet/hook-output-channels` §2 names this exact shape —
"`|| true` and a bare `|| exit 0` on a fallible command are dishonest error
paths — check status explicitly, report on `systemMessage`, exit 0" — and names
D17's index-sync hooks as where it was applied.

The escape clause in the project rule does not apply. It exempts "a path whose
signal would be inferred rather than observed", because inference produces false
alarms. Here the condition is an exit status the caller already has in hand: the
signal is observed, and it cannot false-alarm.

Worth weighing against it, and it is the strongest argument for silence: the
**drain's** analogous degrade is not silent — a marker it cannot read still
produces its framing line, so the reader sees `--- gitlore-relay agent a1 ---`
wrapped around nothing and knows an agent staged something (measured, §5). The
write's failure produces no artifact at all. That asymmetry is the argument for
closing it, not for matching it.

### The channel: `additionalContext`, not `systemMessage`

The dispatch proposes a line appended to the subagent's own `systemMessage`,
"which already reaches the actor". Per `subagent-hook-output-probe.md` it does
not, in the sense that matters:

- `PROBE-SYSMSG` appeared in the subagent's own JSONL as a `hook_system_message`
  attachment and **nowhere else** — not the parent transcript, not the parent's
  stdout stream — and the subagent model never quoted it.
- `PROBE-ADDCTX` was delivered to the subagent as a `<system-reminder>`, and the
  subagent model **narrated it unprompted** in its final report — which is the
  only path by which anything leaves a subagent.

The whole value of the signal is that the actor can carry the fact to the parent
in its own reply. That needs the model channel. On `systemMessage` the line
lands in a transcript no one reads.

### Proposed change (not applied)

Both hooks, since both take `|| true` and the defect is identical. Replace the
`|| true` with an `if !` (which suspends errexit over the function body the same
way) and append to the ctx the hook is about to emit.

`scripts/cc-hooks/index-compose.sh`:

```sh
if ! gitlore_relay_write "$mempath" "$agent_id" "$GITLORE_COMPOSE_SYSMSG" "$GITLORE_COMPOSE_CTX"; then
  GITLORE_COMPOSE_CTX="${GITLORE_COMPOSE_CTX:+$GITLORE_COMPOSE_CTX

}gitlore: the report above could not be staged for the parent session — the relay marker could not be written. A hook's output inside a subagent reaches no one else, so repeat it in your reply or it is lost."
fi
```

`scripts/cc-hooks/index-sync-post.sh`, in that file's own join idiom:

```sh
if ! gitlore_relay_write "$mempath" "$agent_id" "$sysmsg" "$ctx"; then
  if [ -n "$ctx" ]; then ctx="$ctx

"; fi
  ctx="${ctx}gitlore: the report above could not be staged for the parent session — the relay marker could not be written. A hook's output inside a subagent reaches no one else, so repeat it in your reply or it is lost."
fi
```

Three notes on it. The imperative wording is correct here rather than a
violation of the no-actionable-phrases rule: that rule governs DENY channels,
and this is a directive channel whose whole point is that the agent acts
(`hook-output-channels` §7, "Scope"). Appending *after* the write is deliberate
— the line describes the staging failure, so it must not itself be staged. And
in `index-sync-post.sh` the append makes `$ctx` non-empty, which is what gets
`additionalContext` emitted at all on the `failed`-branch shape where ctx would
otherwise be empty — the reachable case identified above.

---

## 2 · Question 2 — the empty-id guard's blast radius

**No other caller exists.** `grep -rl gitlore_relay_write` over the whole repo
excluding `.git/` and `plans/` returns seven files: the four SUT files and the
three `.bats` files. In `session-start.sh` the only occurrence is inside a
comment. Nothing in `commands/`, `agents/`, `skills/`, `hooks/`,
`scripts/install/`, `scripts/hook-manager/`, `plugin-dev/` or `docs/` calls it.

Both production call sites are inside `if [ -n "$agent_id" ]`
(`scripts/cc-hooks/index-compose.sh:82`,
`scripts/cc-hooks/index-sync-post.sh:257`), so the guard cannot fire in
production at all. Every test call passes a non-empty id except the guard's own
case in `tests/index_sync.bats`.

**Nothing relied on the previous behaviour.** With an empty id the write landed
on the bare `gitlore-relay` name, which the drain's `-name 'gitlore-relay-*'`
never enumerates — a file nothing folds and nothing removes. The guard removes
only that.

**The sanitisation cannot smuggle an id past the guard.** Measured directly
against `_gitlore_agent_suffix`:

| input | suffix |
|---|---|
| `///` | `-___` |
| `..` | `-__` |
| `a b` | `-a_b` |
| `x\ny` | `-x_y` |
| `""` | *(empty)* |

`printf -- '-%s'` emits a leading `-` unconditionally, and `tr` maps every byte
of a non-empty input to some byte, so
**a non-empty id always yields a non-empty suffix**. The empty suffix is
reachable only from the empty/absent id the guard already refuses. An
all-disallowed id becoming a run of `_` therefore does not matter: it is keyed,
it stays inside the gitdir (which is the sanitisation's whole purpose), the
drain folds it and removes it, and the framing line names a mangled id. The only
residual is the non-injectivity two ids differing solely outside `[A-Za-z0-9-]`
would hit, which `_gitlore_agent_suffix`'s own comment already records as
unreachable from real agent ids.

One coherence note, not a defect: `gitlore_relay_marker_file mem ""` still
returns the unsuffixed name, which nothing can now write and nothing drains.
That is correct — the helper shares `_gitlore_agent_suffix`'s contract with two
siblings (`gitlore_index_preimage_file`, `gitlore_compose_stamp_file`) that do
use the unsuffixed name for the main thread, and a frozen slice-1 case pins it.

---

## 3 · The mutation round

Every mutation applied **in place** to the working-tree SUT, run over all three
suites, then restored and confirmed with `cmp` against a pre-mutation copy of
each file (not `git diff --stat`, which cannot distinguish a line swap).
Baseline against the GREEN tree as submitted: **131 passed, 0 failed**.

| # | mutation | file | result | cases that red |
|---|---|---|---|---|
| — | baseline (GREEN tree as submitted) | — | **131/0** | — |
| M1 | empty-id guard moved **after** the marker resolution, still before the write | `lib/index-sync.sh` | **GREEN** | — |
| M2 | empty-id guard moved **after** the write | `lib/index-sync.sh` | **RED 2** | `relay_write refuses an empty agent id` (`index_sync.bats:1104`, `[ ! -e "$bare" ]`) and `relay_write refuses a squatted marker path` (`:1134`, status) |
| M3 | `\|\| true` removed | `cc-hooks/index-compose.sh` | **RED 1** | `a failed relay write leaves the subagent's own report intact` (`cc_hook_index_compose.bats:432`, status) |
| M4 | `\|\| true` removed | `cc-hooks/index-sync-post.sh` | **GREEN** | — |
| M4b | M4, run over the 8-suite regression set | ″ | **GREEN, 181/0** | — |
| M5a | drain's `\|\| sysblock=""` removed | `lib/index-sync.sh` | **RED 1** | `an unreadable marker costs the relay, not the hook` (`index_sync.bats:1206`, status) |
| M5b | drain's `\|\| ctxblock=""` removed, sysblock guard intact | `lib/index-sync.sh` | **RED 1** | same case, same line |
| M6 | drain's `rm -f` made conditional on both reads succeeding (strand-the-marker) | `lib/index-sync.sh` | **RED 1** | same case at `:1212`, `[ ! -e "$marker" ]` |
| M7 | `-type f` dropped from the drain's `find` | `lib/index-sync.sh` | **RED 1** | `an unkeyed run survives a non-file squatting on a marker name` (`cc_hook_index_compose.bats:454`, status) |
| M7c | M7 **plus** `rm -f "$marker" \|\| true` | `lib/index-sync.sh` | **GREEN** | — |
| — | the tree as I leave it | — | **131/0** and **181/0** | — |

**M1 is a non-finding, recorded so it is not re-derived.** Nothing discriminates
the guard's position relative to the marker resolution, and nothing should:
`gitlore_relay_marker_file` on an empty id is a pure `rev-parse` with no side
effect. M2 is the position that matters, and it is pinned twice — by the
"without writing" assertion and, separately, by the squat case, because a
trailing `[ -n "$agent_id" ] || return 1` returns 0 and masks the redirect's
failure.

**M4 — the unpinned fix, stated plainly.** Removing `|| true` from
`index-sync-post.sh` reds **nothing**: not one case in the three slice suites,
and not one in the 8-suite regression set either (181/0 with the mutation
applied). The fix is right anyway, and the mechanism is not a matter of opinion
— measured directly on the same library function under the same
`set -euo pipefail`:

```
--- bare call:      <redirect fails>; rc=1, "AFTER" never printed
--- with || true:   <redirect fails>; "AFTER" printed, rc=0
```

M3 is the same mechanism pinned in the sibling hook. So the correct summary is:
the fix is correct and unpinned, and no test in the repository would notice its
removal.

**M7 — `-type f` is still load-bearing, but for a different reason than its
comment claimed.** M7 reds; M7c (the same mutation with the `rm` made tolerant)
is green. So with the reads now tolerant, the *whole* of what `-type f` buys the
test is that `rm -f` never meets a directory. The old comment attributed it to
`awk` and `rm` jointly; that is now half-false and is one of the comments I
rewrote (§4).

---

## 4 · Check 3 — the five relay functions as one mechanism

Read together, the accumulated comments had four defects. All fixed; every fix
is a comment, and `diff` over the non-comment lines of all four files against
the GREEN-phase SUT is empty.

1. **Contradiction (`gitlore_relay_drain` header).** It read "a caller that
   passed an empty id anyway would strand a file … — the guard is at the call
   sites, not here." This slice moved that guard into `gitlore_relay_write`. The
   sentence now names the refusal instead.
2. **Stale mechanism (the drain's `-type f` comment).** It claimed `awk` and
   `rm` both take the hook down on a directory. The reads tolerate it now; only
   the `rm` does. Measured by M7/M7c, and the comment now says exactly that.
3. **Stale mechanism (`session-start.sh`'s drain comment).** It justified
   `|| true` entirely by the `awk` exit-2 path, which the drain now absorbs by
   itself — so as written it argued for a guard against something that no longer
   happens. Rewritten to name what the guard actually still catches: the `rm -f`
   path (§6). This is the only file in the diff the GREEN phase did not touch;
   the orchestrator will now be committing it.
4. **Incomplete contract (`gitlore_relay_write` header,
   `_gitlore_relay_sysblock` header).** The first did not mention the empty-id
   refusal it now performs; the second said both callers "screen for" an
   unopenable marker "rather than hand it a path it cannot read", when both now
   also *tolerate* one. Both updated.

Overlap trimmed rather than deleted: the write's `|| old_…=""` comment used to
compare its trade to the drain's `-type f` — a different mechanism — and now
points at the drain's identical `|| …=""`; the drain's comment states what
`-type f` does *not* cover and why the removal still happens, which the write's
does not carry. Each comment keeps a reason the other does not.

`_gitlore_agent_suffix`'s "the three helpers above" is still accurate (preimage,
compose stamp, relay marker), and the two-readers-not-one-parameterised-program
paragraph is untouched and still true.

---

## 5 · Check 4 — failure-mode parity

Both degrade rather than abort, and the comments now agree with the code in
both. Measured on a scratch store, not read:

| | `gitlore_relay_write` on a mode-0200 marker | `gitlore_relay_drain` on a mode-0200 marker |
|---|---|---|
| return | **0** | **0** |
| effect | both merge reads fail, marker **overwritten** with this run's report only | both block reads fail, **empty block folded** under the framing line |
| what is lost | whatever was already staged (`S1`/`C1` gone; marker holds `S2`/`C2`) | the marker's body |
| marker afterwards | present | **removed** |
| any artifact of the loss | **none** | the framing line, wrapped around nothing |
| stdout | untouched | untouched (0 bytes) |
| stderr | two `awk: … (Permission denied)` lines | two `awk: … (Permission denied)` lines |

Consistent in the property that matters — neither ever costs the calling hook
its own report — and the difference in *what* is lost falls out of the two
operations rather than a design divergence. The last row of the table is the
input to §1: the drain's degrade leaves a trace, the write's leaves none.

---

## 6 · Finding reported, not applied — `gitlore_relay_drain` can still abort its caller

`scripts/lib/index-sync.sh` documents the drain as "Always returns 0". It does
not. With the gitdir made unwritable and a marker present, the bare
`rm -f "$marker"` fails and propagates under a caller's errexit — measured:

```
rm: cannot remove '…/mem/.git/gitlore-relay-a1': Permission denied
outer rc=1        # the statement after the drain never ran
```

This is the same failure class the slice exists to close — a permissions problem
in the gitdir costing a hook its whole report — one line below the read the
slice made tolerant. `session-start.sh` is protected by its `|| true`; the two
PostToolBatch hooks call the drain bare. It is reachable through
`index-sync-post.sh` in particular: on an unwritable gitdir that hook's
frontmatter sync fails, is caught, and produces the `failed` report — and then
the drain kills the hook before it emits it, so the very report telling the user
their descriptions are now stale is the one lost.

**Why I did not apply the one-token fix.** `rm -f "$marker" || true` closes it,
and I measured the cost: that is exactly M7c, which is **green**. Adding it
makes `-type f` un-pinned by any test in the repository — the frozen case
`an unkeyed run survives a non-file squatting on a marker name` stops
discriminating it. The project rule for fixing a verified defect on sight is
conditioned on the fix *removing nothing*, and this one removes a frozen case's
discrimination, so it is my human partner's call rather than mine.

What I did instead: corrected the drain's own doc line to state the residual,
and rewrote `session-start.sh`'s comment so the surviving `|| true` is justified
by the path that still exists rather than the one that no longer does.

If the fix is taken, the companion that restores the coverage is one assertion
on the existing squat fixture — that after an unkeyed run the marker
**directory** still exists and the report carries no framing line naming it —
which pins `-type f` by what it is actually for (not framing and not removing a
non-marker) rather than by an abort it will no longer cause.

---

## 7 · Checks 5-7

**`set -euo pipefail`, bash 3.2, BSD (check 5).** `x=$(cmd) || x=""` is safe
under `set -u`: the assignment happens before the `||`, so `x` is always set —
never a reference to an unset variable, and the failed substitution assigns the
empty string. `|| true` on a function call does suspend errexit for the whole
function body, as the comments claim, and I have it by measurement rather than
by reading the manual: under M5a the drain's unguarded read fails, yet
`tests/cc_hook_session_start.bats`'s case stays green — only possible because
errexit was disabled *inside* the drain by `session-start.sh`'s `|| true`, while
the same mutation reds `tests/index_sync.bats`'s synthetic bare caller. Nothing
in the diff is GNU-only: `[ -n ]`, `||`, `printf` and `rm -f` only.
`tests/helpers/bsd-stubs.bash` shadows `sed`, `grep` and `mktemp`, none of which
the diff uses, so `tests/bsd_portability.bats` is owed no new lock-in.

**Stdout discipline (check 6).** No new path reaches stdout. Each hook has
exactly one `jq -n` (`index-compose.sh`, `index-sync-post.sh`) or one
`emit_session_json` (`session-start.sh`), each followed by `exit 0`.
`_gitlore_relay_sysblock`/`_gitlore_relay_ctxblock` print, and every call site
captures them in `$(…)`; `find`'s output feeds a `read` loop; `rm -f` prints
nothing on success. On the awk-failure path specifically, measured: the drain
wrote **0 bytes** to stdout while both `awk` diagnostics went to stderr. The
frozen cases parse each hook's stdout with `jq` and pass.

**Style (check 7).** No comment in the diff cites `plans/`, `memory/`, a runbook
or slice identifier, or a line number — checked over every added line of
`git diff -- scripts/`. One offender was in the GREEN submission and is gone:
`index-sync-post.sh` carried "Unpinned: no case in this file's suite squats the
marker path", a coverage note rather than mechanism, and one that rots the
moment a case is added. Its content is in §3 of this report, which is where it
belongs.

---

## 8 · Checks that passed, by name

- `./scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats tests/cc_hook_session_start.bats`
  — **131 passed, 0 failed**, against the tree as I leave it.
- `./scripts/run-bats.sh tests/cc_hook_add_tier.bats tests/index_compose.bats tests/cc_hook_post_tool_use.bats tests/lib_util.bats tests/cc_hook_worktree_remove.bats tests/merge_memory.bats tests/tier_discovery.bats tests/tier_divergence.bats`
  — **181 passed, 0 failed**.
- `shellcheck -s bash` over `scripts/lib/index-sync.sh`,
  `scripts/cc-hooks/index-compose.sh`, `scripts/cc-hooks/index-sync-post.sh`,
  `scripts/cc-hooks/session-start.sh` — clean.
- `./scripts/lint-shell.sh` — **137 files clean**.
- Ten mutation runs (M1, M2, M3, M4, M4b, M5a, M5b, M6, M7, M7c), each applied
  in place and restored, each restore verified with `cmp` against a pre-mutation
  copy.
- `diff` over the non-comment lines of all four SUT files against the
  GREEN-phase copies — **empty**: every edit of mine is a comment.
- `git status --porcelain` — the four SUT files, the three frozen `.bats` files
  untouched by me, and the plan reports. Nothing staged, nothing committed.
- Errexit mechanism probe: a bare `gitlore_relay_write` on a failing redirect
  under `set -euo pipefail` kills the script (rc 1, the following statement
  never runs); with `|| true` it continues and the script exits 0.
- Degrade probe: drain over one mode-0200 marker and one directory squat — rc 0,
  framing line with empty body, marker removed, squat untouched, 0 bytes on
  stdout.
- Write-parity probe: second write onto a mode-0200 marker — rc 0, marker
  overwritten with the new report only.
- `rm`-abort probe: drain with the gitdir made unwritable — the caller dies at
  rc 1 (§6).
- `_gitlore_agent_suffix` over five inputs, confirming a non-empty id always
  yields a non-empty suffix (§2).
- Caller sweep: `grep -rl gitlore_relay_write` over the repo excluding `.git/`
  and `plans/` — seven files, no production caller outside the two guarded hook
  branches.

**Nothing committed; the tree is dirty and unstaged.** Note for the
orchestrator: `scripts/cc-hooks/session-start.sh` now appears in the diff
(comment only) where the GREEN phase left it untouched.
