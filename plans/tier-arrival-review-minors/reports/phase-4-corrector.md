# Phase 4 checkpoint review — continuation pre-landing exits

Verdict: **pass, with two Minor fixes applied to the tests and two M15 gaps
reported for the orchestrator.** The two message arms, their wording, their
ordering, the folded comment and the `compose_merged_indexes` rider are correct
as landed; the slice reviews' own checks were re-read rather than re-run, and
this pass concentrated on the two tests as one piece and on the M15 enumeration
the slice reviews could not do from inside a single arm.

Nothing committed, nothing staged. `scripts/resolve.sh` is untouched by this
review (`git status --porcelain -- scripts/` empty); the only file changed is
`tests/resolve_compose.bats`.

## Findings

### 1. Minor (fixed) — the refused-commit test did not pin the staged synthesis

`tests/resolve_compose.bats`, the test at :394. The build-failure test asserts
that the merger's staged synthesis survives its exit, in both stores; the
refused-commit test asserted `MERGE_HEAD` and the state file but not the index.
That left the more interesting half of "the merge stays prepared" unpinned on
the arm where a `git commit` actually ran: a commit refused by a hook is exactly
the case where one might expect the index to have been disturbed, and the test's
own rerun-lands assertion would still pass if the continuation had recomposed
the content from scratch instead of committing what the merger staged.

Added at `:417-420`:

```bash
  # The synthesis the merger staged survives a refused commit, in both stores:
  # `commit` leaves the index alone when a hook declines it, so the rerun below
  # lands the same content rather than a recomposed approximation of it.
  [ -n "$(git -C memory/ddaanet diff --cached --name-only -- MEMORY.md)" ]
  [ -n "$(git -C memory diff --cached --name-only -- MEMORY.md)" ]
```

Both proven non-vacuous, one at a time, by flipping `-n` to `-z`:
`not ok … (line 419)` and then `not ok … (line 420)`, each failing on its own
assertion. Restored after each.

### 2. Minor (fixed) — arm discrimination was asserted in one direction only

The build-failure test carries
`[[ "$stderr" != *"the merge commit was refused"* ]]` (`:469`), so a build
failure that also emitted the commit arm's text is caught. The refused-commit
test had no counterpart, so the leak in the other direction was unobserved.
Added at `:410-412`:

```bash
  # The refused-commit arm, not the build arm: the message was built, so a run
  # that also claimed a build failure would be emitting both arms' text.
  [[ "$stderr" != *"the merge message could not be built"* ]]
```

Proven by mutation: with a copy of `scripts/resolve.sh` taken first, the commit
arm was given the build arm's `echo` as well; the filtered run failed with
`not ok … (line 412)` on that exact assertion. `scripts/resolve.sh` was then
restored with `git checkout --` and `diff`-ed against the pre-mutation copy —
identical.

### 3. Discrimination under a future message merge — holds, in all three shapes

The dispatch asks whether the two tests would still tell the arms apart if a
later change merged the two messages. Taking the three ways that could happen:

| Change | What catches it |
|---|---|
| Both arms replaced by one shared string | Both positive assertions (`:405`, `:465`) fail: neither byte-exact line exists any more |
| Build arm's text emitted by the commit arm too | `:412` (added above) |
| Commit arm's text emitted by the build arm too | `:469` |
| Both arms folded into one helper printing one text | Same as row 1 |

With finding 2 applied, each arm's test now pins its own line, denies the
other's, and (for the commit arm) pins the order against git's reason. A change
that merged the messages cannot pass this pair silently.

### 4. Fixture duplication between the two tests — left as is, deliberately

The shared setup is three lines: `prepare_tier_merge_with_new_lines`, then
`mkdir "$BATS_TEST_TMPDIR/msgtmp"` and
`export TMPDIR="$BATS_TEST_TMPDIR/msgtmp"` (`:395-400` and `:420-423`). The
fixture call is the suite's own idiom, repeated in fourteen other tests in the
file. The `TMPDIR` pair is what makes each test's
`find "$TMPDIR" -name 'gitlore-merge-msg.*' -print -quit` assertion mean
anything — it is the private directory the assertion sweeps — and folding it
into a helper would move the setup out of sight of the assertion that depends on
it, for two saved lines across two call sites. `grep` finds no third consumer of
the pattern in the suite. Not a finding; recorded because the dispatch asks.

## M15: the pre-landing exits of `continue-after-merge`, enumerated

M15's own anchor
(`plans/unadoptable-tier-arrival/reports/deliverable-review.md:147-149`) names
two exits — a failed message build and a refused merge commit — as the ones the
merger's and the skill's "otherwise" branch misreads as post-landing. Both now
carry the shared phrase. The enumeration below covers every exit reachable
before the merge commit at `scripts/resolve.sh:321`, because Phase 6 will make
`the merge was not committed` the key the merger branches on, and any
pre-landing exit without it falls to the "otherwise" branch and is reported as
landed.

| # | Exit | Where | Says "the merge was not committed"? |
|---|---|---|---|
| 1 | `gitlore: not installed` | `:35` | No — by construction: no store, so no prepared merge to speak of |
| 2 | `gitlore: no merge state file in memory or any tier` | `:42-43` | No — by construction: there is no merge |
| 3 | `gitlore: merges are prepared in more than one store …` | `:49-52` | **No — gap, see below** |
| 4 | `gitlore: merge state at <file> does not name a usable store.` | `:57-58` | **No — gap, see below** |
| 5 | errexit abort on `memroot=`, `found=`, `statefile=`, `mempath=`, `flavor=`, `publish=` | `:39, 40, 54, 55, 60, 63` | **No — silent, see below** |
| 6 | `gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:` | `:136-138` | **Yes** |
| 7 | errexit abort on a failed staging `gitlore_git … add` | `:126, 156, 172, 181` | No — **by decision**, stated as the bound in the `compose_merged_indexes` rider (`:105-109`) and in the outline's *Residual* |
| 8 | errexit abort on `merge_msgfile=$(mktemp …)` | `:309` | **No — gap, see below** |
| 9 | `gitlore: the merge message could not be built, …` | `:315-320` | **Yes** (this phase) |
| 10 | `gitlore: the merge commit was refused, …` | `:321-326` | **Yes** (this phase) |

Everything from `:327` on is post-landing and outside M15.

Two non-exits checked and cleared while enumerating, so they are not left
implicit:

- `dangling=$(gitlore_compose_dangling "$memroot")` (`:143`) is an unguarded
  command substitution under `errexit`, but the function cannot return non-zero:
  it ends with `return 0`, its inner `path=$(…) || continue` and
  `grep -qxF … && continue` are both errexit-exempt shapes, and
  `gitlore_tier_paths` likewise always returns 0. No silent abort here.
- `root_dirty_before=$(gitlore_root_dirty_beyond_pair …)` (`:297`) cannot fail
  either: its only `git` call sits in an `if` condition, so a git failure is
  read as "clean" and the function always returns 0. Worth knowing that it
  swallows a git failure into `0`, but that is pre-existing and is not an exit.

### Gap A (reported, not fixed) — a failed `mktemp` exits 1 silently, one line above the two new arms

`merge_msgfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-merge-msg.XXXXXX")` at `:309`
is bare under `errexit`. Probed on the same shape, in a `mktemp -d` scratch
under `$TMPDIR`, removed afterwards:

```text
mktemp: failed to create file via template ‘…/gitlore-merge-msg.XXXXXX’: No such file or directory
exit=1
```

— exit **1**, mktemp's own text, no `gitlore:` line, and the commit never
reached. This is a pre-landing exit indistinguishable to the merger from a
landed merge once Phase 6 keys on the phrase, and it shares its failure domain
(`$TMPDIR` unwritable, full, or removed under the run) with the two arms this
phase just gave lines to. It is silent **by oversight, not by decision**: the
outline's *Residual* paragraph names only the staging failure, and neither the
runbook nor the outline mentions `mktemp`.

Unlike the staging failure, it is not forced by `errexit` either — the `mktemp`
is a command substitution in an assignment, so
`merge_msgfile=$(mktemp …) || { echo … >&2; exit 1; }` reaches a `gitlore:` line
the same way the two arms below it do. Cheapest of the gaps to close, and
adjacent to the code this phase already touched.

Not fixed here: the dispatch forbids adding a message the runbook does not ask
for, and the runbook's Item 4.1 names two arms.

### Gap B (reported, not fixed) — two `load_continuation_state` refusals speak, but not in the key

Exits 3 and 4 do print a `gitlore:` line and do leave the merge(s) prepared, so
a human reading the output is not misled. The merger is: post-Phase-6 its branch
splits on `the merge was not committed`, and neither line carries it, so both
land in "otherwise" and get reported as a merge that committed. Exit 3's own
text (`land or abort one of them before continuing.`) says enough to a human,
and exit 4's does not say anything about the merge's fate at all.

Exits 1 and 2 are a different case and need nothing: reaching either means there
is no prepared merge to make a claim about, so the shared phrase would be a
false statement rather than a missing one.

Exit 5 — a `jq` failure on a malformed state file, or a failing
`gitlore_memory_path` / `gitlore_stores_with_merge_state` — aborts with the
helper's own text and no `gitlore:` line. Note that `:56`'s guard covers jq
*printing* an empty store but not jq *failing*, which is the malformed-JSON
case. Same class as Gap A, lower reachability.

Whether Phase 6's prose should instead be written so that only a line it
recognises means "landed" — an allow-list rather than the current deny-list — is
an orchestrator call, and would close Gaps A and B together without adding a
message anywhere. Recorded as a design item, deliberately unfixed.

## Scope honoured

`agents/memory-merger.md` and `skills/resolve/SKILL.md` were read (to judge what
the "otherwise" branch will key on) but not edited; `scripts/lib/resolve.sh` was
read for `gitlore_merge_commit_message`'s failure shape and not edited. No
earlier phase's code was touched.

## Bats counts after the fixes

| File | Result |
|---|---|
| `tests/resolve_compose.bats` | **24 passed, 0 failed** |

`GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/resolve_compose.bats`,
foreground, unpiped, one file at a time.
`shellcheck -x tests/resolve_compose.bats` clean. `just precommit` not run — the
orchestrator owns it. The two filtered runs in between were mutations, each
restored and re-verified.

No other suite was run: the change is test-only and confined to one file.

## Files changed

- `/Users/david/code/gitlore/tests/resolve_compose.bats` — the refused-commit
  test gains a build-arm denial (`:410-412`) and the two staged-synthesis
  assertions (`:417-420`).

## UNFIXABLE

None.

## Design decisions left unfixed

1. **Gap A** — a `gitlore:` line for a failed `mktemp` at
   `scripts/resolve.sh:309`. Outside Item 4.1's two named arms; cheap and
   adjacent.
2. **Gap B** — exits 3, 4 and 5 of `load_continuation_state`, and the
   allow-list-vs-deny-list shape of Phase 6's merger prose that would cover them
   and Gap A at once.
3. The staging abort's silence (exit 7) stands as the documented bound; no
   change proposed.
