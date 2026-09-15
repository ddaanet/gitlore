# Item 2.3 code review

Commit under review: `3287a66`. Scope: `scripts/lib/resolve.sh`
`gitlore_merge_one_store` and the `behind` arm of `gitlore_push_stores`. Fixes
applied in the working tree, uncommitted.

REFACTOR-NEEDED: none. UNFIXABLE: none.

## Findings

### Major: a failed adoption hid the fetch failure (fixed)

Each early return ran `gitlore_adopt_advanced_live ... || return 1` before its
own report. A tier that was both dirty (adoption refused) and unreachable
reported only the adoption. The user fixed that, reran, and only then learned
the remote was unreachable. The same applied to the no-remote tier return.
Verified: the new test "a failed adoption does not hide a failed fetch" fails
against `3287a66` on the `could not fetch tier 'ddaanet'` assertion.

Fix: `gitlore_merge_one_store` now resolves the remote first (URL check, then
fetch, then `origin/live` read into `remote`, with `fetched` recording the fetch
result). It then has a single adoption call site:

```sh
if [ -z "$remote" ] || [ -z "$live" ] || ! git -C "$store" merge-base --is-ancestor "$live" "$remote"; then
  gitlore_adopt_advanced_live "$mempath" "$store" "$tier" || adopt_rc=1
fi
```

After that come the three reports, unchanged in text and in return code. The
no-live return passes on `$adopt_rc`, and the take path stops with
`[ "$adopt_rc" -eq 0 ] || return 1` before `head` is read. This also removes the
three duplicated adopt-then-return tails the review brief asked about, and it
states the runbook rule ("adopt unless the fetch succeeded and `live` is
contained in `origin/live`") as one condition. The rewritten comment above it is
present tense and cites no plan item.

Status routing after the fix:

- **No-remote tier or failed fetch:** both messages print, and the function
  returns 1.
- **Remote with no `live`:** "nothing to take" prints, and the function returns
  1 if the adoption failed, 0 otherwise.
- **Reachable remote:** the function returns 1 with only the adoption's message.
  This is the committed behaviour, and it is guarded: mutating the check away
  reds "a refused live update after the repair leaves no trace".

### Minor: reusing the refusal classifier in the `behind` arm (fixed)

The GREEN claim holds. `gitlore_classify_refusal` tests `pushed` ⊆ `target`
first, so equal refs print `behind`, and `ahead` means strict ancestry only.
Diverged refs and an unreadable ref printed `diverged` or `unknown`, and the arm
then `continue`d silently. After a successful take neither case is reachable: a
diverged take returns 1 first, and both refs were read by the classification
just above. Still, a silent `continue` followed by memory recording an
unpublished gitlink is the lockstep failure this item exists to prevent. Calling
a refusal classifier where nothing was refused also misreads.

Replaced with
`if ! git -C "$tierpath" merge-base --is-ancestor live origin/live`. It asks the
question directly, mirrors the new test in `gitlore_merge_one_store`, and in any
unreachable state it pushes and reports instead of continuing silently.
Behaviour is identical in the reachable states: with equal refs it does not
push, and with a strict repair it pushes. The comment is rewritten: the old one
said lockstep holds "before this loop moves on to the next tier". The
requirement is actually "before memory's push records it".

### Observations (no change)

- **Retry refusal message.** The runbook fixes the retry's refusal message to
  the outer `*)` text, "failed, and not because of divergence". If another
  consumer pushes between the take and the retry, the refusal is a
  non-fast-forward and that wording is inaccurate. git's own `(fetch first)`
  line is appended, and a rerun of `/gitlore:push` takes and republishes, so I
  left it as specified.
- **Plain `/gitlore:merge` publishes nothing.** `scripts/merge-memory.sh` only
  calls `gitlore_merge_stores`. `gitlore_merge_one_store` touches a remote only
  through `fetch`; its other ref moves are `push .` (local) and checkouts. The
  reorder changes only whether the local adoption runs before the fast-forward.
  When it is skipped, the fast-forward takes origin's commits instead, and
  `head` is still the pin that the adoption's walk-back needs.
- **Merge-base errors.** A `merge-base` error (exit 128) in the adoption
  condition counts as "not contained" and adopts. That is the conservative side
  and matches the pre-item behaviour.
- **Shell hygiene.** The `if`/`elif`/`||` conditions have no errexit holes.
  Nothing is bash-3.2-specific. Every expansion is quoted. There is no
  `2>/dev/null`.

## Tests

Mutation checks (each saved under a checked `$TMPDIR`, mutated, run, restored,
`cmp`-verified):

| Mutation | Result |
| --- | --- |
| `3287a66`: drop adoption before fetch-failure return | slice 4 red |
| `3287a66`: always adopt (drop ancestry test) | slice 3 red |
| `3287a66`: no retry push in `behind` arm | slice 2 red |
| `3287a66`: drop adoption before no-remote return | **no test red** (gap) |
| fixed: `if false` on the `behind` retry | slice 2 red |
| fixed: always adopt | slice 3 red |
| fixed: `\|\| adopt_rc=1` → `\|\| return 1` | new test B red |
| fixed: drop `[ "$adopt_rc" -eq 0 ] \|\| return 1` | "a refused live update after the repair leaves no trace" red |

Tests written, both cheap and in `tests/merge_memory.bats`:

- **A. "a tier with no remote still adopts local live and reports the missing
  remote".** Closes the no-remote gap. It is red against `3287a66` with that
  adoption dropped.
- **B. "a failed adoption does not hide a failed fetch".** A dirty stranded tier
  with an unreachable remote. It is red against `3287a66`.

Gap described, not written: the "remote has no `live`" return. It needs a fetch
of `origin live` that succeeds yet leaves no `refs/remotes/origin/live`, i.e. a
remote with no fetch refspec covering it. A missing remote branch fails the
fetch instead. The state is contrived and the path pre-dates this item.

## Verification

`scripts/run-bats.sh`, `GITLORE_GIT_RETRY_SCHEDULE=0`, after the fixes:

- `tests/merge_memory.bats`: 35 passed, 0 failed
- `tests/push_behind_vs_diverged.bats`: 14 passed, 0 failed
- `tests/tier_divergence.bats`: 19 passed, 0 failed
- `tests/resolve_compose.bats`: 9 passed, 0 failed
- `tests/push_memory.bats`: 12 passed, 0 failed
- `tests/push_rejection_discriminator.bats`: 9 passed, 0 failed
- `tests/commit_memory.bats`: 35 passed, 0 failed

`commit_memory.bats` ran concurrently with the four-file batch above it, which
went against the one-suite-at-a-time rule. Both runs came back green. After
that, only a comment was rewrapped; `shellcheck` and `bash -n` pass, and the
four merge-memory tests touching this path were rerun green.

`shellcheck scripts/lib/resolve.sh tests/merge_memory.bats`: clean.

Changed files: `/Users/david/code/gitlore/scripts/lib/resolve.sh`,
`/Users/david/code/gitlore/tests/merge_memory.bats`.
