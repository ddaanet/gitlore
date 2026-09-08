# Item 2.1 slice 2 — code review

Scope reviewed: `scripts/cc-hooks/index-sync-pre.sh` — the three changed lines
(`:40-42`) and the comment rewrite at `:44-49`. Read-only for judgement:
`scripts/lib/index-sync.sh`, `scripts/cc-hooks/index-sync-post.sh`,
`index-compose.sh`, `add-tier-batch.sh`, `tests/index_sync.bats`,
`hooks/hooks.json`, the runbook's Item 2.1 and its four slices, the outline's
FR-C row, this slice's RED / test-review / GREEN reports, slice 1's code review,
and `plans/index-edit-propagation/recall-artifact.md` with the memory files it
names.

One edit applied, to the comment block. The three lines of implementation are
correct as written and were not touched.

## Verdict — the comment's truth as of slice 2

Asked for explicitly by the dispatch, so it leads.

**The comment as committed was false for the case it exists to describe, and no
wording of that invariant can be true at slice 2.** The invariant belongs to the
pre/post *pair*, and slice 2 converts only the pre half.

Traced against the scripts, not inferred:

- `index-sync-pre.sh:41-42` (as committed) resolves
  `gitlore-index-preimage-<id>` and `gitlore-compose-stamp-<id>` when the
  payload carries `agent_id`.
- `index-sync-post.sh:30` still calls `gitlore_index_preimage_file "$mempath"`
  with **one** argument, so it resolves the bare `gitlore-index-preimage`; `:32`
  then does `[ -f "$stashfile" ] || exit 0`.
- `index-compose.sh:32` likewise resolves the bare `gitlore-compose-stamp` and
  `:33` exits on its absence. `add-tier-batch.sh:75` `rm -f`s the bare stamp.

So, after slice 2 alone:

| claim in the committed comment | true at slice 2? |
| --- | --- |
| "a parent batch ending mid-subagent no longer consumes the subagent's baseline" | **yes** — the parent's post hook removes only the bare pre-image, and the subagent's keyed file is a different path |
| "each keys its own file" | **yes** — of the *pre* hook |
| "an existing one here always belongs to the batch in flight of this agent" | **no** — for a subagent, nothing consumes or removes the keyed pair, so an existing keyed file may be from any earlier batch of that agent, and `:55`'s `[ -f "$stash" ] && exit 0` then preserves an arbitrarily stale baseline |

The behavioural consequence, worth stating plainly for the orchestrator: between
this commit and slice 3, a subagent's index edit does **not** propagate at all —
its own post hook finds no bare pre-image and exits at `index-sync-post.sh:32`,
and its compose stamp is never consumed either. That is a strictly worse outcome
for a subagent than before slice 2 (where it propagated, and merely raced the
parent). It is the expected shape of a mid-item TDD slice — slice 3 closes it —
but the item must not be considered shippable at slice 2, and the comment must
not read as though it were.

The rewrite also silently dropped the *reason* the original invariant held —
"Each post hook removes its own file at batch end (even when nothing was
touched)" — and put keying in its place. Keying is not the reason; it only adds
the "of this agent" qualifier. Removing the removal clause left the `if` at
`:59` with no stated justification at all.

**Resolution taken:** the invariant is what justifies the `if` immediately below
it, so dropping it for two commits is not an option; and the runbook itself
prescribes the end-state wording for this slice (`runbook.md:566-571`). The
comment therefore keeps the per-agent framing but now names the coupling it
rests on, in the text, instead of asserting an accomplished fact — which is
unambiguous at slice 2 (a reader can check the three named files and see the
other half is not there yet) and stays correct and useful after slice 4, as a
standing constraint on anyone who later un-keys a consumer.

## Major — the comment asserted an invariant slice 2 does not deliver

**Applied.** `scripts/cc-hooks/index-sync-pre.sh:44-58`. The universal claim is
replaced by the claim plus its precondition, and the split-out true half is
stated separately:

```sh
# baselines are keyed per agent, so a parent batch ending mid-subagent consumes
# and removes its own bare pair only. An existing file here therefore belongs to
# the batch in flight of this agent — an invariant the consuming hooks hold up
# jointly, and it stands only while index-sync-post.sh, index-compose.sh and
# add-tier-batch.sh resolve the SAME keyed name and drop the baseline they
# consumed at batch end, even when nothing was touched.
```

Two things changed beyond the qualifier. "no longer consumes the subagent's
baseline" became "consumes and removes its own bare pair only", because the
former is one clause away from reading as "the subagent's edit is now safe",
which is exactly what is not true this commit. And the batch-end removal clause
the rewrite had deleted is restored, since it — not the keying — is what makes
an existing file a *current* one.

## Major — the item's stranded-file residual bound was missing

**Applied.** The item requires it (`runbook.md:573-577`) and slice 1's code
review located its two homes as `index-sync-pre.sh:43-47` (this slice) and
`index-sync-post.sh:35-38` (slice 3). Slice 2 rewrote the first of those and did
not add the bound. Added as the comment's second paragraph:

```sh
# One residual, bounded rather than swept: a subagent that dies mid-batch leaves
# its keyed files behind, and the next batch of that same agent id consumes and
# deletes them. An agent id is not reused, so the leftovers are one pair per dead
# subagent, not unbounded growth — the same bound index-sync-post.sh already puts
# on a stale pre-image.
```

Wording follows the item's own ("consumed and deleted by the next batch of the
same agent id"; "not unbounded growth") and points at the model the item names.

## Assessed, no defect — the new `jq` read's failure modes

`agent_id=$(jq -r '.agent_id // empty' <<<"$payload")` under
`set -euo pipefail`. Probed rather than reasoned about (jq-1.7 on this box):

| payload | result |
| --- | --- |
| `{"agent_id":"a1"}` | rc 0, `a1` → keyed path |
| `{"agent_id":null}` | rc 0, empty → bare path |
| `{"agent_id":""}` | rc 0, empty → bare path (jq prints an empty line for `"" // empty` since `""` is truthy; `$( )` strips it) |
| `{}` (absent) | rc 0, empty → bare path |
| `{"agent_id":123}` | rc 0, `123` |
| malformed (`{not json`) | jq prints a parse error, exits 5; the assignment trips errexit and the shell exits 5 |

`null`, absent and `""` are therefore indistinguishable at the call site and all
three give today's unsuffixed names through `_gitlore_agent_suffix`'s empty
short circuit — the contract the runbook states and the "stamps the bare path"
case pins.

**No regression on the abort path.** It is the same shape as the file's two
existing reads, `tool=$(jq -r '.tool_name // empty' <<<"$payload")` (`:19`) and
`file=$(jq -r '.tool_input.file_path // empty' <<<"$payload")` (`:30`), and
those run *first* — a malformed payload or an absent `jq` (rc 127) aborts at
`:19` and never reaches `:40`. The new read is strictly downstream of a
successful parse of the same string, so the only way it can abort where the old
ones did not is a `jq` that parses `.tool_name` and fails on `.agent_id`, which
does not exist. The hook is `PreToolUse` (`hooks/hooks.json:28-34`), where only
exit 2 blocks the tool; an errexit abort exits 5, non-blocking, and drops the
stdout JSON — the same behaviour `:19` already has.

## Assessed, no defect — whitespace and quoting

- `agent_id` is assigned from a command substitution (no word splitting on
  assignment) and passed quoted at both `:41` and `:42`.
- `stash` and `stamp` are likewise assigned from command substitutions and
  quoted at every downstream use: `:59` (`[ ! -f "$stamp" ]`), `:60`
  (`> "$stamp"`), `:61`, `:64` (`[ -f "$stash" ]`), `:68`
  (`cp "$index" "$stash"`), `:72`, `:73`. A gitdir path containing spaces
  survives all of them.
- `<<<"$payload"` is quoted, so the payload is not re-split or globbed.
- Residual, pre-existing and unchanged: `$( )` strips trailing newlines, so a
  gitdir path ending in a newline would lose it. Slice 1's guard already keeps
  the *agent id* from introducing an interior newline into the name
  (`_gitlore_agent_suffix`'s `LC_ALL=C tr -c`).

## Assessed, no defect — bash 3.2 and BSD portability

- `<<<` is a bash 3.x herestring, already used three times in this very file
  (`:19`, `:30`, and now `:40`) and in seven other scripts under `scripts/`
  (`index-sync-post.sh`, `index-compose.sh`, `plugin-upgrade-batch.sh`,
  `post-tool-use.sh`, `nudge-reset.sh`, `worktree-drift.sh`, plus three under
  `scripts/lib/`). Established, not new.
- The change introduces no `sed`, `grep`, `find`, `mktemp` or `stat` call, so
  there is no new GNU-ism for `tests/helpers/bsd-stubs.bash` to catch. `jq -r`
  and `//` are jq syntax, platform-independent.
- No new `${...}` parameter expansion; nothing touches `"$@"`/`"$*"` under
  `set -u`, the known bash-3.2 trap.

## Discrimination check (in-place mutation)

Saved the SUT to `/tmp/claude-1000/index-sync-pre.sh.save`, mutated in place,
ran, restored. `tests/index_sync.bats` was never edited or moved.

- **M1 — drop the `"$agent_id"` argument** from both `:41` and `:42` (i.e. back
  out slice 2's behaviour, keeping the read):

  ```
  not ok 1 pre: a payload carrying agent_id stamps the keyed path, not the bare one
  # (in test file tests/index_sync.bats, line 156)
  #   `[ -f "$(gitlore_index_preimage_file memory a1)" ]' failed
  ok 2 pre: a payload with no agent_id stamps the bare path
  ```

- **M2 — read `.agent_type` instead of `.agent_id`** (the fallback the GREEN
  report says it rejected):

  ```
  not ok 1 pre: a payload carrying agent_id stamps the keyed path, not the bare one
  # (in test file tests/index_sync.bats, line 156)
  #   `[ -f "$(gitlore_index_preimage_file memory a1)" ]' failed
  not ok 2 pre: a payload with no agent_id stamps the bare path
  # (in test file tests/index_sync.bats, line 171)
  #   `[ -f "$(gitlore_index_preimage_file memory)" ]' failed
  ```

  Both cases carry `agent_type:"general-purpose"`, so reading it keys the
  main-thread payload too and the bare-path case fails as well. The pair pins
  `agent_id` specifically, not "some agent field".

Restore proof:

```
$ sha256sum scripts/cc-hooks/index-sync-pre.sh   # before M1
73b9b5cd5e7747f789fe4369a690b278b400f6b7fdeb4571d7b1d19f608af22e
$ sha256sum scripts/cc-hooks/index-sync-pre.sh   # after restore
73b9b5cd5e7747f789fe4369a690b278b400f6b7fdeb4571d7b1d19f608af22e
$ diff /tmp/claude-1000/index-sync-pre.sh.save scripts/cc-hooks/index-sync-pre.sh
(no output)
$ git status --porcelain -- scripts/
 M scripts/cc-hooks/index-sync-pre.sh
```

The single `M` is this review's comment edit; `git diff` shows the comment block
and nothing else, and the file keeps mode `100755`.

## Checks that passed, by name

- `scripts/run-bats.sh tests/index_sync.bats` — **69 passed, 0 failed**, after
  the fix. Same figure as GREEN.
- `bats -f "stamps the keyed path|stamps the bare path" tests/index_sync.bats` —
  2 passed on the restored tree, after both mutation rounds.
- `shellcheck -s bash scripts/cc-hooks/index-sync-pre.sh` — exit 0.
- `scripts/lint-shell.sh` — `lint-shell: 137 files clean` (unchanged count; no
  file added or left behind).
- Mutation harness M1 / M2 above, each with the failing assertion line.
- `jq` behaviour matrix above — six payload shapes plus a malformed one, run
  under `set -euo pipefail` in a subshell, exit codes captured.
- `git diff` / `git status --porcelain -- scripts/ tests/` — one file modified,
  `tests/` clean, no throwaway fixture left behind.
- Hook-event check: `hooks/hooks.json:28-34` registers this script under
  `PreToolUse` with matcher `Write|Edit|Bash` — the basis for the exit-code
  claim above.
- Line width: longest line in the edited file is 92 chars (`:41`, pre-existing);
  every added comment line is ≤ 80.

## Gate note

`scripts/cc-hooks/` is a `precommit_inputs` gated input, so this review's edit
invalidates the sentinels that currently read:

```
.git/gitlore/gates/lint                339038738 1081257
.git/gitlore/gates/test-unit           339038738 1081257
.git/gitlore/gates/test-integration    339038738 1081257
.git/gitlore/gates/check-distribution  2398497780 495654
```

The orchestrator's commit needs a fresh gate run. `just precommit` was not run
here, per the dispatch.

## Out of scope, untouched

- `tests/index_sync.bats` — reviewed at RED; read and run, never edited.
- `scripts/lib/index-sync.sh` — slice 1, closed. Read only.
- `scripts/cc-hooks/index-sync-post.sh` (slice 3), `index-compose.sh` and
  `add-tier-batch.sh` (slice 4), including their comments — read only, to
  establish what the bare paths still do.
- `tests/cc_hook_index_compose.bats`, `tests/cc_hook_add_tier.bats`.
- `docs/`, `memory/`, and everything under `plans/` other than this report.

Nothing committed.
