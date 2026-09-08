# Item 2.1 slice 3 — code review

Scope reviewed: `scripts/cc-hooks/index-sync-post.sh` — the two changed hunks
(the `agent_id` read at `:23` and the keyed resolution at `:31-38`) plus every
pre-existing comment in the file, and `tests/index_sync.bats` — the
`batch_payload` decoy field and the two new cases. Read-only for judgement:
`scripts/lib/index-sync.sh`, `scripts/cc-hooks/index-sync-pre.sh`,
`index-compose.sh`, `add-tier-batch.sh`, `hooks/hooks.json`, the runbook's Item
2.1 (slice 3 at `runbook.md:633`), this slice's RED / test-review / GREEN
reports, slice 2's code review, `memory/ddaanet/hook-input-schema.md`,
`CLAUDE.md` and `memory/ddaanet/shared-claude.md`.

Two edits applied, both to comments in `index-sync-post.sh`. The two lines of
implementation are correct as written and were not touched.

## Verdict — the keying itself

Correct and complete for this file. Every site that resolves, reads, copies or
removes a pre-image goes through the one keyed `$stashfile`:

| site | what it does | keyed? |
| --- | --- | --- |
| `:38` (`gitlore_index_preimage_file "$mempath" "$agent_id"`) | the file's only resolution of the name | yes, this commit |
| `:40` `[ -f "$stashfile" ] \|\| exit 0` | the baseline-present gate | yes, via `$stashfile` |
| `:42` `cmp -s "$stashfile" "$index"` | the unchanged-index test | yes |
| `:50` `rm -f "$stashfile"` | drop on the cmp-equal path | yes |
| `:54` `gitlore_index_pairs "$stashfile"` | the pre-image read | yes |
| `:157` `rm -f "$stashfile"` | the unconditional drop | yes |

`grep -n 'preimage\|stashfile' scripts/cc-hooks/index-sync-post.sh` returns
exactly those plus the prose mention at `:18`; no literal pre-image path
fragment appears anywhere in the file. `grep -rn preimage scripts/` confirms the
only other consumer is `index-sync-pre.sh`, already keyed by slice 2 —
`index-compose.sh` and `add-tier-batch.sh` handle the compose *stamp*, which is
slice 4 and untouched here. The failure mode the test review flagged for this
slice ("keying the lookup and forgetting the removal") does not occur, and both
`rm -f` sites are exercised by the new cases: `:50` by case 1's second phase
(the parent's own baseline matches the index, so the cmp-equal branch runs) and
`:157` by case 2 (the index differs, so the propagation path runs).

`// empty` with no `agent_type` fallback matches `index-sync-pre.sh:40` byte for
byte, and nothing downstream separates empty from absent —
`_gitlore_agent_suffix` short-circuits on an empty `$1` and yields the bare
name. Probed rather than assumed (jq-1.7, `set -euo pipefail`):
`{"agent_id":"a1"}` → `a1`; `{"agent_id":null}`, `{"agent_id":""}`, `{}` and
`{"agent_type":"gp"}` → empty, i.e. today's unsuffixed name. The read sits after
`session=$(jq -r …)` at `:22`, so a malformed payload already aborts one line
earlier and this read adds no new abort path.

## Major — the new comment pointed at a rationale that is not there

**Applied.** `scripts/cc-hooks/index-sync-post.sh:31-37`. The comment as
committed ended:

```sh
# baseline its own batch — parent or that one subagent — owns. Never
# agent_type; see index-sync-pre.sh for why.
```

`index-sync-pre.sh` contains no such rationale. `grep -rn 'agent_type' scripts/`
returns **nothing** — the string does not occur in any script in the repo. The
reason lives in `tests/index_sync.bats:130-140` and in
`memory/ddaanet/hook-input-schema.md`; slice 2's code review recorded it in its
own report and deliberately did not put it in the pre-hook.

The failure it produces is the one the project's comment rules exist for: the
no-fallback rule is the single constraint of this item that a later maintainer
is most likely to "simplify" (it looks like a missing fallback, not a deliberate
one), and the comment sends whoever checks it to a file that says nothing about
it. They either re-derive the reason or conclude the constraint is folklore. A
pointer that reads as a citation and resolves to nothing is a claim made from
the hub rather than the node.

Replaced with the reason stated in place, in the same words the test file uses,
pointing at the test that pins it:

```sh
# baseline its own batch — parent or that one subagent — owns. `agent_id` and
# never `agent_type`: only the first is subagent-only, while the second also
# appears on the main thread of an `--agent` session, so keying on it would
# send a parent batch looking for a name only a subagent's pre-hook ever
# writes. Pinned by the agent_type decoy in tests/index_sync.bats.
```

Kept inside the file under review rather than adding the rationale to
`index-sync-pre.sh` (slice 2, closed) to make the pointer resolve. See "Not
fixed" below for the shared-home question slice 4 will face.

The citation points at `tests/index_sync.bats`, not at
`memory/ddaanet/hook-input-schema.md` where this reviewer first sent it. The
memory node is where the schema fact is *recorded*, but it is a tier file: it
reaches this tree through a submodule gitlink and a mounted tier, so it is not
part of what the plugin distributes and no other comment in `scripts/` cites one
— the sole precedent, `scripts/lib/util.sh:442`, cites `docs/design.md`. The
test is in-repo, ships, and is what actually *pins* the fact, so a reader who
follows the pointer gets a failing assertion rather than a claim. No
`docs/references/` node covers the `agent_id`/`agent_type` distinction today; if
slice 4 or Item 3.1 gives it one, that becomes the better target.

## Minor — the stale-pre-image bound became over-general

**Applied.** `scripts/cc-hooks/index-sync-post.sh:43-49`. The cmp-equal branch
ended with "This bounds a stale pre-image to a single batch." That sentence was
true before this commit, when one bare name served every agent and therefore
every batch consumed whatever was there. After keying it over-claims: only the
owning agent ever resolves that name, so a keyed pre-image whose subagent died
mid-batch is consumed by *nothing* and stays on disk — the residual
`index-sync-pre.sh:54-58` bounds at one pair per dead subagent. The GREEN report
calls the change "per (agent, batch) rather than per batch, a strengthening"; it
strengthens the *misuse* bound (that file can never become another agent's
baseline) and weakens the *lifetime* bound the sentence is about.

It matters because the pre-hook's residual paragraph ends "the same bound
index-sync-post.sh already puts on a stale pre-image" — a reader following that
reference landed on a sentence that does not cover the dead-subagent case at
all. Now:

```sh
  # over-propagate. This bounds a stale pre-image to a single batch of the
  # agent that owns it — the only agent that ever resolves this name. A keyed
  # file whose subagent died mid-batch is stranded instead of reused, the
  # residual index-sync-pre.sh bounds.
```

## Test integrity — run, not read

### The `agent_type` decoy discriminates, through case 1's positive control

Mutated the SUT in place to `jq -r '.agent_id // .agent_type // empty'` — the
fallback the slice rejects — and ran the two cases:

```
1..2
not ok 1 a parent post-hook leaves a subagent's pre-image intact
# (in test file tests/index_sync.bats, line 689)
#   `[ ! -f "$(gitlore_index_preimage_file memory)" ]' failed
ok 2 the subagent's own post-hook then consumes its keyed pre-image
```

So the decoy bites exactly where the test review said it does — the second phase
of case 1, where the parent has a baseline of its own and the fallback sends it
looking for `gitlore-index-preimage-general-purpose`, which nothing wrote,
stranding the bare file. **Case 2 does not discriminate the fallback** and
cannot: its subagent payload carries `agent_id:"a1"`, which wins under `//`, and
its parent phase has no baseline to consume. The positive control is therefore
load-bearing on its own, not belt-and-braces — this is the assertion that pins
*which* name the parent resolved, and it is the only one in either case that
does.

### Both cases claim their reason honestly

Mutated the resolution back to `gitlore_index_preimage_file "$mempath"` — the
pre-change production file exactly:

```
1..2
ok 1 a parent post-hook leaves a subagent's pre-image intact
not ok 2 the subagent's own post-hook then consumes its keyed pre-image
# (in test file tests/index_sync.bats, line 712)
#   `[ "$output" = 'description: "new hook"' ]' failed
```

Case 2 fails against unchanged production code on the assertion it claims
(`memory/a.md` still reads `description: OLD`). Case 1 passes against unchanged
code — which is what the RED report declares in full, flagged as an expected
pass rather than dressed up as a red, and which is structurally unavoidable: a
payload with no `agent_id` resolves the identical name before and after this
commit, so nothing about the parent's own path can red on the change itself. Its
value is the mutation class above, and the RED report's own glob-any-keyed -file
mutation. No defect; recording it so the TDD audit reads it as a stated decision
rather than a hole.

### Whitespace and a hostile agent id, end to end

Not judged by reading. Added a temporary case driving the real pre-hook and the
real post-hook with `agent_id='a 1/../../x'` — a space, path separators and `..`
— asserting the propagation completes, the keyed file is removed, and no
`gitlore-index-preimage*` file exists outside the memory gitdir. It passes:
`_gitlore_agent_suffix`'s `LC_ALL=C tr -c 'A-Za-z0-9-' '_'` (slice 1's, pinned
by slice 2's boundary case) is reached by both hooks and nothing in this file
bypasses or re-splits it — `$agent_id` is assigned from a command substitution
and passed quoted, and `$stashfile` is quoted at all six sites above.

Re-ran that probe plus the two committed cases with
`TMPDIR="/tmp/claude-1000/space dir"`, so the gitdir path itself contains a
space: 3/3 pass. The probe was then removed and `tests/index_sync.bats` restored
— see "Restore proof".

## Not fixed, and why

- **The budget nudge is keyed on `session_id`, not on the agent** (`:175`,
  `gitlore_index_budget_nudge_file "$mempath" "$session"`). A subagent shares
  its parent's `session_id`, so the first post-hook run to cross the threshold —
  the subagent's — emits the advisory into a channel confined to that subagent
  and `touch`es the once-per-episode marker, after which the parent never warns.
  Real, and reachable now that a subagent's post hook does work instead of
  exiting at the baseline gate. **Belongs to Item 3.1**, whose whole subject is
  that a subagent's `systemMessage` and `additionalContext` never reach the
  parent, and whose relay marker is the mechanism that fixes it. Not this
  slice's to invent, and keying the nudge per agent here would be the wrong fix
  (it would emit the advisory twice, both times invisibly).
- **The four consumers each carry their own `jq -r '.agent_id // empty'` read.**
  The runbook prescribes exactly that ("each of the four consumers gains a new
  `jq -r '.agent_id // empty'` read"), and a one-line read does not earn a
  helper. What does want one home is the *rationale* I inlined above: slice 4
  adds two more consumers, and three copies of the same five-line paragraph is
  the point at which it should move to the header of
  `gitlore_index_preimage_file` / `gitlore_compose_stamp_file` in
  `scripts/lib/index-sync.sh` with the consumers pointing there. Flagged for
  slice 4's author, not done here — it edits slice 1's closed file and this
  commit does not yet create the duplication.
- **`:18` ("the pre-hook's stash … its presence says a watched call ran this
  batch") and `:154-156` (the unconditional `rm -f`: "a later post-hook run
  would diff a fresh index against this ancient baseline").** Checked
  explicitly, per the dispatch. Both remain true as written for every run that
  reaches them — the stash each describes is the one this hook resolves, which
  is now its own agent's, and the keyed framing is stated at the resolution 20
  lines above. Adding "of this agent" to each would be churn against sentences
  that are not false.
- **Pre-existing: a deleted `MEMORY.md` strands the baseline.**
  `[ -e "$index" ] || exit 0` (`:29`) returns before the resolution, so a stash
  survives the index being removed and the same agent's next batch would diff a
  re-created index against it. Unchanged in shape by this commit (it was the
  same hazard on the bare name) and outside Item 2.1.

## Checks that passed, by name

- `scripts/run-bats.sh tests/index_sync.bats` — **71 passed, 0 failed**, after
  the two comment edits. Same figure as GREEN.
- `bats -f "…leaves a subagent's pre-image intact|…then consumes its keyed pre-image" tests/index_sync.bats`
  — 2 passed on the restored tree, after both mutation rounds.
- Mutation M1 (`.agent_id // .agent_type // empty`) — case 1 reds at
  `tests/index_sync.bats:689`; output quoted above.
- Mutation M2 (resolution back to one argument, i.e. the pre-change file) — case
  2 reds at `tests/index_sync.bats:712`; output quoted above.
- Hostile-agent-id probe (`a 1/../../x`) driving `$PRE` then `$POST` — passes,
  including the assertion that nothing was written outside the memory gitdir.
- Spaced-gitdir run, `TMPDIR="/tmp/claude-1000/space dir"` — 3 passed (the two
  committed cases plus the probe).
- jq behaviour matrix — six payload shapes under `set -euo pipefail`, table
  above.
- `shellcheck -s bash scripts/cc-hooks/index-sync-post.sh` — exit 0.
- `just lint` after the edits — `lint-shell: 137 files clean`, exit 0 (unchanged
  file count; nothing added or left behind).
- `grep -n 'preimage\|stashfile'` over the SUT and `grep -rn 'preimage'` over
  `scripts/` — the site table above; no unkeyed resolution remains anywhere.
- `grep -rn 'agent_type' scripts/` — no hits, which is the evidence for the
  Major finding.
- File mode after editing: `100755`, unchanged. Longest added comment line 78
  chars (the file's 591-char maximum at `:209` is a pre-existing report string).

## Restore proof

```
$ sha256sum scripts/cc-hooks/index-sync-post.sh   # before the mutation rounds
fa2b7c0d50e65e5f07df342a031bc48c6482fc8da73f5ed1220238bb2cc9752e
$ git checkout HEAD -- scripts/cc-hooks/index-sync-post.sh
$ sha256sum scripts/cc-hooks/index-sync-post.sh   # after restore, before my edits
fa2b7c0d50e65e5f07df342a031bc48c6482fc8da73f5ed1220238bb2cc9752e
$ git status --porcelain -- tests/
(no output)
```

The temporary bats probe was appended to `tests/index_sync.bats`, run, then
removed with `git checkout -- tests/index_sync.bats`;
`git status --porcelain -- tests/` is empty, so the committed test file is
byte-identical to HEAD. The scratch copy under `/tmp/claude-1000` was diffed
against the restored file (identical) and deleted. No fixture left behind.

## Files touched

- `scripts/cc-hooks/index-sync-post.sh` — comments only, two hunks, unstaged.
- `plans/index-edit-propagation/reports/item-2-1-s3-code-review.md` — this
  report, untracked.

Nothing staged, nothing committed.

## Gate note

`scripts/cc-hooks/` is a `precommit_inputs` gated input, so this review's edit
invalidates the sentinels the GREEN run left. As of this report:

```
.git/gitlore/gates/lint                2958410583 1086561   (re-run here, current)
.git/gitlore/gates/test-unit           1318920462 1086124   (stale)
.git/gitlore/gates/test-integration    1318920462 1086124   (stale)
.git/gitlore/gates/check-distribution  2633811882 496566    (stale)
```

The orchestrating session's commit needs a fresh `just precommit` in the
foreground. `just precommit`, `just test-unit` and `just test-integration` were
not run here, per the dispatch.

## Out of scope, untouched

- `scripts/lib/index-sync.sh` (slice 1, closed) and `index-sync-pre.sh` (slice
  2, closed) — read only.
- `index-compose.sh`, `add-tier-batch.sh`, `tests/cc_hook_index_compose.bats`,
  `tests/cc_hook_add_tier.bats` — slice 4. Read only, to confirm they touch the
  compose stamp and not the pre-image.
- `tests/index_sync.bats` — reviewed at RED and again here; mutated only via the
  temporary probe, restored byte-identical.
- `docs/`, `memory/`, and everything under `plans/` other than this report.
