# Item 2.1 slice 3 — RED

Two cases added to `tests/index_sync.bats`, in a new "driven end to end" section
between the "TWO index edits in one batch" e2e case and "both index-sync hook
scripts are executable". `batch_payload` gained an optional `TEST_AGENT_TYPE`
(mirrors `TEST_AGENT_ID`/`TEST_SESSION_ID`: unset/empty omits the field,
non-empty adds it) — needed so a payload with no `agent_id` still carries the
`agent_type` decoy the dispatch requires. `pre_stdin` needed no change; both
cases drive `$PRE` directly with a hand-built `jq -n` payload, the same idiom
the existing "pre: a payload carrying agent_id…" case already uses.

## Command

```
bats -f "leaves a subagent's pre-image intact|then consumes its keyed pre-image" tests/index_sync.bats
```

```
1..2
ok 1 a parent post-hook leaves a subagent's pre-image intact
not ok 2 the subagent's own post-hook then consumes its keyed pre-image
# (in test file tests/index_sync.bats, line 693)
#   `[ "$output" = 'description: "new hook"' ]' failed
```

Full suite (`scripts/run-bats.sh tests/index_sync.bats`):
**70 passed, 1 failed** — the one case above, no collateral damage to the other
70 (69 from slice 2's committed state, plus this slice's 2, minus the 1 genuine
red).

## Per case

### 1. `a parent post-hook leaves a subagent's pre-image intact`

**Passes already, and is an expected pass, not a forced red** — flagged
explicitly per the dispatch rather than forced. `index-sync-post.sh` today
resolves only `gitlore_index_preimage_file "$mempath"` (no agent argument),
which is the bare path. The subagent's pre-hook (keyed, from slice 2) never
wrote that bare path — it wrote only `gitlore-index-preimage-a1` — so the
parent's post hook finds nothing at `[ -f "$stashfile" ] || exit 0` (`:32`) and
exits immediately, before touching any file. The keyed file surviving and the
hook emitting no output are both true *by accident*: slice 2's pre-hook change
already stopped the parent and the subagent from sharing a path, so there is
nothing left in this exact scenario (parent carries no `agent_id`, today and
after slice 3 both resolve the identical bare name) for slice 3's post-hook
change to affect. This is the same shape slice 1 and slice 2 each carried once —
the RED report's job is to say so rather than force a red that isn't there.

**Made non-vacuous by mutation**, per the dispatch's instruction to add whatever
assertion distinguishes "left it alone because it keys correctly" from "left it
alone because it found nothing." The plausible wrong fix this guards against: a
post-hook that, finding no bare stash, falls back to *any* keyed pre-image file
present in the gitdir rather than checking it belongs to the batch's own agent
id — which reopens exactly the race the item exists to close (a parent's post
hook consuming a subagent's baseline). Applied in place to
`scripts/cc-hooks/index-sync-post.sh:30-32`:

```sh
stashfile=$(gitlore_index_preimage_file "$mempath")   # absolute
if [ ! -f "$stashfile" ]; then
  found=$(find "$(dirname "$stashfile")" -maxdepth 1 -name 'gitlore-index-preimage-*' -print -quit 2>/dev/null)
  [ -n "$found" ] && stashfile="$found"
fi

[ -f "$stashfile" ] || exit 0   # no baseline → no watched call, nothing to diff
```

Run against the mutation:

```
$ bats -f "leaves a subagent's pre-image intact" tests/index_sync.bats
1..1
not ok 1 a parent post-hook leaves a subagent's pre-image intact
# (in test file tests/index_sync.bats, line 670)
#   `[ -z "$output" ]' failed
```

Death is on the "no output" assertion — genuine detection, not an error. I also
checked the second assertion independently discriminates, by temporarily
swapping the two assertions' order (via a scratch copy, restored after) and
re-running against the same mutation:

```
$ bats -f "leaves a subagent's pre-image intact" tests/index_sync.bats
1..1
not ok 1 a parent post-hook leaves a subagent's pre-image intact
# (in test file tests/index_sync.bats, line 670)
#   `[ -f "$(gitlore_index_preimage_file memory a1)" ]' failed
```

So the mutated hook actually propagated the wrong change (a non-empty
`systemMessage`) and removed the keyed file — either assertion alone would have
caught it. The committed case keeps the original order (`[ -z "$output" ]`
before the `-f` check), matching the dispatch's stated ordering.

An earlier attempt to reproduce this outside the bats fixture (a hand-rolled
`git init`/`git submodule add` scratch harness) gave misleading results —
`gitlore_cd_project_root`/`gitlore_has_submodule` never resolved the ad hoc
repo, so neither hook ran at all and both files came back "absent" for the wrong
reason. Discarded; the bats fixture (`make_parent_with_memory`) is the
trustworthy harness and is what the numbers above come from.

### 2. `the subagent's own post-hook then consumes its keyed pre-image`

**FAILED on its assertion, genuinely.** Continuation of case 1's scenario: after
the parent's post hook runs (and, per case 1, leaves the keyed file alone), the
subagent's own post hook — `agent_id: "a1"` — runs. Today's `index-sync-post.sh`
still resolves the bare `stashfile`, which was never written (the pre-hook wrote
only the keyed one), so this run also hits `[ -f "$stashfile" ] || exit 0` and
exits without propagating. `$status -eq 0` holds (the hook ran and exited 0
cleanly); death is on `[ "$output" = 'description: "new hook"' ]` (`:693`) —
`memory/a.md` still reads `description: OLD`, a clean assertion failure, not an
error or missing symbol. The case also asserts the keyed file is gone afterward
(`[ ! -f "$(gitlore_index_preimage_file memory a1)" ]`); GREEN has to flip both,
same shape as slice 2's case 1.

## Restore

```
$ git checkout -- scripts/cc-hooks/index-sync-post.sh
$ git status --porcelain -- scripts/
(no output)
$ sha256sum scripts/cc-hooks/index-sync-post.sh
1a657eb305e46d72c7696a7c8a84f5ecf574f5ec9b340494bdbbcc4c075b2ce4  scripts/cc-hooks/index-sync-post.sh
```

Re-ran both cases after restore (shown in the combined run above): case 1 passes
again, case 2 still reds the same way.

## Checks that passed, by name

- `bats -f "leaves a subagent's pre-image intact|then consumes its keyed pre-image" tests/index_sync.bats`
  — 1 expected pass (verified non-vacuous by mutation), 1 genuine red.
- `scripts/run-bats.sh tests/index_sync.bats` — 70 passed, 1 failed (this
  slice's one red case), no regression elsewhere.
- Mutation of `index-sync-post.sh`'s stash-resolution (glob-any-keyed-file
  fallback) — case 1 reds on `[ -z "$output" ]`, and independently on
  `[ -f "$(gitlore_index_preimage_file memory a1)" ]` when the two assertions'
  order is swapped in a scratch copy.
- `shellcheck -s bash tests/index_sync.bats` — exit 0.
- `scripts/lint-shell.sh` — `lint-shell: 137 files clean`.
- `git status --porcelain -- tests/ scripts/ plans/` — `M tests/index_sync.bats`
  only.
- `git status --porcelain -- scripts/` after the mutation round-trip — empty.
  SUT restored byte-identical to HEAD (sha confirmed above).

## Out of scope, untouched

- `scripts/cc-hooks/index-sync-post.sh` — read, then temporarily mutated and
  restored; ends byte-identical to HEAD. It must not learn to read `agent_id` in
  this dispatch, and does not.
- Every other consumer under `scripts/cc-hooks/` and `scripts/lib/index-sync.sh`
  — read only, unchanged.
- Slice 4's cases; `tests/cc_hook_index_compose.bats`;
  `tests/cc_hook_add_tier.bats`.
- `docs/`, `memory/`, and everything under `plans/` other than this report.

Nothing committed. `just precommit` not run, per the dispatch.
