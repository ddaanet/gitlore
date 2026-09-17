# Item 4.1 / Slice 2 — code review

Verdict: **pass, with one defect found and fixed** — the
`compose_merged_indexes` rider justified its bound with a mechanism that does
not hold, so the comment asserted something untrue about the code. The two
message lines, their ordering, the folded comment and the exit state of both
arms are correct.

## Fix applied: the rider's justification clause

`scripts/resolve.sh:105-109`, the `compose_merged_indexes` docstring.

Before:

```text
# Returns 0 otherwise. A failed staging command aborts the continuation under
# errexit, before the merge commit, which keeps the merge state for a rerun —
# with git's own text on stderr and no `gitlore:` line, since wrapping the
# command would suspend errexit around it. The caller calls it bare: an `||`
# on the call would suspend errexit across the whole body, and a failed `add`
# would then read as a tier the root could not adopt.
```

After:

```text
# Returns 0 otherwise. A failed staging command aborts the continuation under
# errexit, before the merge commit, which keeps the merge state for a rerun —
# with git's own text on stderr and no `gitlore:` line of its own. The caller
# calls it bare: an `||` on the call would suspend errexit across the whole
# body, and a failed `add` would then read as a tier the root could not adopt.
```

**The defect: `since wrapping the command would suspend errexit around it`.** In
a sentence about "a failed staging *command*", "the command" reads as the
staging command — the four `gitlore_git … add` calls at `:126`, `:156`, `:172`
and `:181`. Wrapping one of those *is* possible and *does* reach a `gitlore:`
line: `gitlore_git -C "$store" add -A || { echo "gitlore: …" >&2; exit 1; }`
suspends errexit for the wrapped command only, and errexit stays armed inside
the brace group (measured in slice 1's review), so the `exit 1` is reached
regardless. The absence of a `gitlore:` line for a staging failure is therefore
a chosen bound, not one the mechanism forces — which is what the runbook asks
the rider to state (`runbook.md:327`: "adds: a failed staging command aborts
under `errexit` with git's own text and no `gitlore:` line", with no reason
clause).

The real reason lives in the *outline* and concerns a different referent —
`outline.md:212`, "wrapping **the call** would suspend `errexit` across the
function", i.e. wrapping `compose_merged_indexes` itself. That claim is true,
and the comment's *next* sentence already carries it verbatim ("an `||` on the
call would suspend errexit across the whole body"). So the deleted clause was
both inaccurate and redundant against the sentence following it.

**`of its own` rather than a bare deletion.** The bound as written is also
globally ambiguous: `:142` emits composition's own `gitlore:` lines before the
staging calls run, so on the rc=0 path a staging failure is preceded by
`gitlore:` output. "no `gitlore:` line of its own" keeps the runbook's bound and
scopes it to the failure, which is what the merger and the skill key on.

## The rider's factual claim, traced

Verified true of `compose_merged_indexes` as written, in three parts.

1. **Every staging call is bare.** `:126` and `:156` are simple commands inside
   `if`/`elif` bodies (errexit is suspended only in a *condition* list, not in a
   branch body); `:172` is bare; `:181` is bare and also the function's last
   command. None sits on the left of `||`, in a condition, or in a pipeline. The
   function itself is invoked bare at `:290`, as the comment's own next sentence
   states — so errexit is armed throughout its body.
2. **git's own text, no `gitlore:` line.** `gitlore_git`
   (`scripts/lib/util.sh:338-355`) captures each attempt's stderr with
   `2>"$errfile"`, emits it with `cat "$errfile" >&2` after the retry loop, then
   `return "$rc"`. It prints nothing of its own, so a failed `add` puts git's
   text on stderr and nothing else. An `add` failure is not a lock error, so no
   retry intervenes.
3. **Aborts before the merge commit.** `compose_merged_indexes` is called at
   `:290`; the commit is at `:321`. Nothing between them can be reached once
   errexit fires inside the function.

Probed, rather than reasoned only — the exact shape (a bare `gitlore_git`-shaped
function called bare inside another bare function, under `set -euo pipefail`),
with the `add` pointed at a non-repository:

```text
exit=128
--- stdout        (empty: neither AFTER-ADD-MID nor REACHED-COMMIT ran)
--- stderr
fatal: not a git repository (or any parent up to mount point /)
Stopping at filesystem boundary (GIT_DISCOVERY_ACROSS_FILESYSTEM not set).
--- gitlore lines: 0
```

Both the mid-function call and the last-command call abort at the failure; git's
text is the whole of stderr; nothing downstream of the staging call runs. The
probe ran in a `mktemp -d` under `$TMPDIR` and was removed.

## Wording, byte-exact

Each of the two strings was extracted from all four carriers and `cmp`-ed
pairwise. Identical, including the `; the merge stays prepared.` tail and the
final period; `cat -A` shows no trailing whitespace.

| String | Source | Runbook | Outline | Test |
|---|---|---|---|---|
| `gitlore: the merge message could not be built, so the merge was not committed; the merge stays prepared.` | `scripts/resolve.sh:318` | `runbook.md:319` | `outline.md:187` | `resolve_compose.bats:457` |
| `gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared.` | `scripts/resolve.sh:324` | `runbook.md:324` | `outline.md:190` | `resolve_compose.bats:405` |

**Shared phrase.** `the merge was not committed` matches the merged-index gate
at `scripts/resolve.sh:136` verbatim; the three lines diverge only after it
(`the merge stays prepared.` twice, `… prepared for a new synthesis:` once), so
the merger's `the merge was not committed` key selects all three and its
sub-branch splits them on what follows. `grep` over the tree finds no fourth
carrier of either new string.

**Directive-free.** Each line is two clauses of past state plus one of standing
state. No imperative, no next command, no path, sha or identifier the reader
could act on, and no mechanism — the merger's own prose (Phase 6) supplies the
act. The build line does not claim a reason was printed, which matters because
one failure mode prints none (below).

## The folded comment

Not a finding. `scripts/resolve.sh:310-314`:

```bash
      # A refused commit or a failed message build keeps MERGE_HEAD and the
      # merge state, so a rerun lands it; only the message file is this run's
      # to remove. Removal comes first in each `||` group below: errexit stays
      # armed on its right-hand side, so a failing write to stderr there would
      # skip whatever follows it and leave the scratch file behind.
```

- **Accurate for both arms.** Both keep `MERGE_HEAD` and `gitlore-merge-state`
  (asserted at `:452-453` and `:411-412`); in both, the `mktemp` file at `:309`
  is the only artifact this run created. Both handlers are `||` brace groups
  with the `rm -f` first.
- **It still names what makes removal-first necessary** — errexit armed on the
  right-hand side of `||` — which is the whole content of the per-arm comment
  slice 1 added. Nothing was lost in the fold; the wording is a rephrasing, not
  a summary.
- **It lands where the reader of the commit arm meets the hazard.** The folded
  comment is the *nearest preceding comment* for both arms: `:310-314`, then the
  build arm at `:315-320`, then the commit arm at `:321-326`, with no other
  comment between. A reader who arrives at the commit arm (say from a grep of
  `the merge commit was refused`) is six lines below it, inside the same
  screenful, and the comment says "each `||` group **below**" rather than
  describing one group — so it does not read as belonging to the build arm
  alone. Duplicating it per-arm would restate identical reasoning twice; a
  cross-reference would be worse than the six-line distance it replaces.

## errexit and pipefail on both arms

- **Build arm.** `gitlore_merge_commit_message … > "$merge_msgfile" || { … }`.
  The function is invoked on the left of `||`, so errexit is suspended across
  its *whole body* — a failure mid-body returns rather than aborting, which is
  what lets the handler run at all. Its last command is
  `git … log --format='%s' "HEAD..$second" | sed 's/^/  /'`
  (`scripts/lib/resolve.sh:2255`), so under `pipefail` a failing `git log` makes
  the pipeline, and therefore the function, return non-zero. That is the path
  the slice's stub drives. The partial subject already written to the file is
  removed by the handler.
- **Commit arm.** `gitlore_git`'s internal `git … || rc=$?` keeps errexit happy
  and it returns `rc` after emitting the captured stderr, so the handler is
  entered with git's reason already on stderr — the ordering `:409` pins.
- **Inside each handler**, errexit is armed: the `rm -f` first is what makes the
  removal unconditional and the message the only thing a dead fd 2 can cost.
  Residual, unchanged from slice 1 and accepted there: a failing `rm -f` would
  abort with `rm`'s status and no `gitlore:` line. `rm -f` on a `mktemp`-created
  file in a writable directory has no live failure mode worth a guard, and
  inverting the order trades a certain cleanup for an uncertain message.

## State on exit

| | Build arm | Commit arm |
|---|---|---|
| status | `1` (`:446`) | `1` (`:403`) |
| message file removed | `:456` | `:410` |
| `MERGE_HEAD` | `:452` | `:412` |
| `gitlore-merge-state` | `:453` | `:411` |
| staged content | `:454-455`, both stores | not asserted; rerun lands (`:415-417`) |
| rerun lands the merge | `:463-467` | `:414-417` |

Each handler executes only `rm -f`, `echo` and `exit 1`, so staged content,
`MERGE_HEAD` and the state file cannot be touched on either path; the commit
arm's missing staged-content assertion is a test-coverage observation, not a
code defect, and adding it is outside this review's scope (the dispatch holds
the tests OUT beyond one mutation run).

## bash 3.2 / BSD, quoting

No arrays, no `[[ ]]`, no `local -n`, no GNU-only utility on the reviewed path.
`mktemp "${TMPDIR:-/tmp}/gitlore-merge-msg.XXXXXX"` is the BSD-accepted template
form. `"$merge_msgfile"` is quoted at every use (four), so a `$TMPDIR`
containing spaces is safe and nothing splits on whitespace. Both `echo`
arguments are fixed strings with no backslash and no leading `-`. The added
comment carries no path, plan reference or line number, and no comment's first
word is `shellcheck`.

## Mutation run

One mutation, applied in place from a copy and restored; `git diff scripts/`
afterwards shows only the rider fix above.

| Mutation | Expected | Result |
|---|---|---|
| The build arm's `rm -f "$merge_msgfile"` deleted (the emission and `exit 1` kept) | the removal assertion fails | `not ok 2 … (line 456)` on `[ -z "$(find "$TMPDIR" -name 'gitlore-merge-msg.*' -print -quit)" ]`, `1 passed, 1 failed` |

Chosen over re-proving the wording line (RED already did that) because the
removal is the invariant the folded comment's errexit ordering exists to
protect, and nothing had shown it was observed. The commit arm's test passed in
the same run, confirming the mutation was arm-local.

## Slice 1's carry-forward, honoured

Slice 1's review left one item for this slice: keep the removal first and put
the new `echo` after it, rather than the "prints … to stderr before removing"
order the runbook then carried. The implementation does (`:316-319`), and the
runbook was reworded to match (`:320-322`, "The removal comes first because
`errexit` stays armed inside a `||` brace group"). No divergence remains.

## Checks that passed

1. Both strings byte-exact across source, runbook, outline and test.
2. Shared `the merge was not committed` phrase matching `:136`.
3. Directive-free wording, no identifiers.
4. git's reason precedes the gitlore line on the commit arm; the build arm needs
   no ordering pair (a real build failure's reason comes from plain `git` on
   unredirected stderr, and the stub's failure is silent by construction).
5. The folded comment accurate for both arms and reachable from both.
6. The rider's three factual claims, traced and probed.
7. Exit state on both arms.
8. errexit/pipefail interaction on both arms, including why the LHS function
   body runs with errexit suspended.
9. bash 3.2 / BSD portability and quoting.
10. `shellcheck -x scripts/resolve.sh` clean.

## Bats counts after the fix

| File | Result |
|---|---|
| `tests/resolve_compose.bats` | 24 passed, 0 failed |

`GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/resolve_compose.bats`,
foreground, unpiped. No second file was run: the fix is comment-only, so it
cannot change behaviour in any suite. `just precommit` not run — the
orchestrator owns it.

## Files changed

- `/Users/david/code/gitlore/scripts/resolve.sh` — the `compose_merged_indexes`
  docstring rider: the inaccurate
  `since wrapping the command would suspend errexit around it` clause removed,
  the bound scoped with `of its own`.

Nothing committed, nothing staged. No UNFIXABLE items, no design call required.
