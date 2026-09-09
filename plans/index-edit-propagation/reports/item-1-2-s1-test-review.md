# Item 1.2 slice 1 — test review

Verdict: **fixed and still red.** One real coverage gap (the hook case did not
assert the carrier the runbook asks it for), one comment stating a property the
assertion under it cannot observe. Both applied. No wrong-reason red found.

## 1. Mechanical check — reproduced

`scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`,
run before any edit of mine:

```
not ok 12 a tier moved off its pin aborts the commit
# (in test file tests/commit_memory.bats, line 184)
#   `[ "$status" -ne 0 ]' failed
not ok 30 the parent pre-commit hook aborts on an off-pin tier
# (in test file tests/git_hook_pre_commit.bats, line 241)
#   `[ "$status" -ne 0 ]' failed

bats: 32 passed, 2 failed
```

Both listed tests FAILED on an assertion. Neither PASSED, neither ERRORed, and
neither died on a missing symbol — matching the RED report. Nothing else in
either suite moved.

## 2. Death-point check — how each post-death-point assertion was executed

Both tests die on `[ "$status" -ne 0 ]`, so everything after it was written and
unverified. I executed every one of those assertions, in two worlds, from a
throwaway `tests/zz_scratch_review.bats` (deleted before this report; it is not
in the tree).

- **World A — unchanged code.** The same fixture, the same `run`, then each
  assertion invoked individually through a `probe` wrapper that reports
  PASS/FAIL instead of aborting the body under errexit. This proves each
  assertion *evaluates* rather than erroring, and shows what it evaluates to in
  the red.
- **World B — a patched abort.** A throwaway copy of the plugin root at
  `/tmp/claude/greenroot` (every top-level entry symlinked back to the repo,
  `scripts/` a real copy), with the runbook's `gitlore_compose_check_pins` call
  and its two message arms inserted at the `gitlore_sync_memory_to_live` call
  site, driven through `CLAUDE_PLUGIN_ROOT`. Nothing under the repo's `scripts/`
  was touched — `git diff --exit-code scripts/` is clean, checked after the run.
  The two assertion blocks were then run **verbatim** against that copy.

Results, per assertion:

| assertion | World A (unchanged code) | World B (patched abort) |
|---|---|---|
| `[ "$(git -C memory rev-parse HEAD)" = "$head_before" ]` | evaluates, FAIL — HEAD advanced | PASS |
| `[ "$(git -C memory rev-parse ":ddaanet")" = "$pin_before" ]` | evaluates, FAIL — pin moved `d2c4cd03…` → `40b73344…` | PASS |
| `assert_bullets memory/ddaanet/MEMORY.md "- [shared](shared.md) — stale hook"` | evaluates, PASS | PASS |
| `[ -f "$(gitlore_commit_msg_file memory)" ]` | evaluates, FAIL — consumed by the commit that landed | PASS |
| `[ "$(gitlore_commit_msg_freshness memory)" = "yes" ]` | evaluates, FAIL — reads `absent` | PASS (reads `yes`) |
| `$stderr` header fragment | evaluates, ABSENT | PRESENT |
| `$stderr` `is checked out at` | evaluates, PRESENT | PRESENT |
| `$stderr` agent remedy fragment | evaluates, ABSENT | PRESENT |
| hook: HEAD / `:ddaanet` / carrier | evaluate, FAIL / FAIL / (carrier reads `stale hook`) | PASS / PASS / PASS |

### `:ddaanet` resolves — the errexit hazard the dispatch named is not present

Captured with the `rev-parse` outside `run` and errexit lifted, printing its rc:
pre-run `rc=0 out=d2c4cd035d7ab5a7febbde57209f30a41dd55856`, post-run `rc=0` in
both worlds and through both entry points. `make_tier_in_memory` commits the
submodule add, so the gitlink is in memory's index throughout; the fixture never
reaches a state where `:ddaanet` is missing. No assertion here can die instead
of failing.

### `assert_bullets` matches and discriminates

Executed against the fixture: PASS, with the actual block printed as
`- [shared](shared.md) — stale hook` — em dash and single spaces as written.
Discrimination proved by rewriting the carrier to
`- [shared](shared.md) — fresh hook` (what a completed compose leaves) and
re-running the same call: FAIL, while the same helper against its own text
PASSes. So the assertion is not satisfied by the file merely existing or by the
bullet region being non-empty.

### `gitlore_commit_msg_freshness` — discriminates, but not for "No restamp"

It is **not vacuous**. Against unchanged code it reads `absent` (the commit
lands and `gitlore_sync_memory_to_live` consumes `$msgfile`), so the assertion
fails; against the patched abort it reads `yes`. It also fails against an abort
placed late enough for the compose or `gitlore_sync_tiers_to_live` to have
written into `memory/` first.

What it cannot see is the specific thing the runbook's **No restamp** paragraph
forbids. I built a second patched root with `touch "$msgfile"` added to the
abort arm and ran the same assertions: `msgfile exists` PASS, `freshness` reads
`yes`, assertion PASS — identical to the un-restamped arm. That is not a fixable
fixture, it is an unobservable difference: reaching this arm means the freshness
gate upstream already read `yes`, so a restamp cannot change any later answer,
and on a successful commit the file is deleted anyway. The mtime route is closed
too — `_gitlore_mtime` is whole-second (`stat -c %Y` / `stat -f %m`), the `-m`
path creates `$msgfile` *inside* the run so there is no pre-run mtime to compare
against, and a same-second restamp would be invisible.

Rather than manufacture a distinction with no consequence, I replaced the
comment above the assertion, which claimed it pinned "No restamp", with what it
actually pins: the approval surviving the abort, plus an explicit note that a
`touch` in the abort arm satisfies it identically and why that is sound. The
behaviour the runbook cares about — the retry is not refused for a change nobody
made — is pinned.

### The three `$stderr` fragments — character-checked against their sources

Checked mechanically (`str in source`), not by eye:

| fragment | source | exact substring? |
|---|---|---|
| `moved off the commit the memory store records for it` | runbook header text | yes |
| `is checked out at` | `scripts/lib/index-compose.sh:341`, the live problem line | yes (1 occurrence) |
| `Return the tier to its pin with the command above` | runbook agent-remedy text | yes |

Two further points on these:

- The header fragment cannot be satisfied by `gitlore_compose_check_pins`' own
  output. Its mid-merge line reads
  `sits off the commit the memory store records for it`; `moved off …` appears
  nowhere in `scripts/`. Confirmed by substring check against the whole file.
- `is checked out at` is already present in World A, so on its own it
  discriminates nothing in the red — its job is to prove the problem lines were
  *forwarded*, not swallowed. I proved it does that: a third patched root that
  emits the header with `$pin_problems` dropped makes the fragment ABSENT while
  the header stays PRESENT. It fails on its own against a header-only
  implementation.

## 3. Coverage against the runbook

**Gap found and fixed.** The runbook asks the hook case for "the unchanged
`:ddaanet` gitlink **and the unchanged carrier**". It asserted the gitlink and
HEAD, and not the carrier. Added to `tests/git_hook_pre_commit.bats`
(`the parent pre-commit hook aborts on an off-pin tier`):

```bash
assert_bullets memory/ddaanet/MEMORY.md '- [shared](shared.md) — stale hook'
```

The worktree carrier, not `HEAD:MEMORY.md`: the abort means nothing was
committed on either side, and `seed_tier_bullet` only ever writes the worktree,
so the tier's `HEAD:MEMORY.md` is the pre-seed file and would pin nothing about
what composition was stopped from doing. That reasoning is in the comment.
Executed in World B — it runs and passes; discrimination is the same
`assert_bullets` result recorded above.

**The hook fixture reaches the guard for the right reason.** This was the check
most at risk, since that case writes its own `$msgfile` rather than going
through `-m`. Measured on the fixture immediately before `run bash "$HOOK"`:
`gitlore_memory_dirty memory` = `1` and `gitlore_commit_msg_freshness memory` =
`yes`. So it is not redding on an unapproved-summary refusal. Confirmed
positively as well: the hook's output in World A is the
`tier composition refused` block carrying `tier 'ddaanet' is checked out at …`,
i.e. it reached `gitlore_compose` and the pin condition, and in World B it is
the new off-pin header. The `$msgfile` is written after the tier's empty commit
and after both seeds, so it is the newest file — the ordering the neighbouring
compose case's comment calls for.

Everything else the runbook lists for slice 1 is present: exit code, unchanged
HEAD, unchanged `:ddaanet`, carrier, `$msgfile` existence, freshness, and the
three fragments; and the fixture is Item 1.1 slice 3's off-pin induction
verbatim.

## 4. Wrong-reason hunting

- **Isolation.** Each case gets its own `setup_tmp_repo`; both were also run
  alone in the scratch file with the same outcome. No cross-test state.
- **`--separate-stderr` targeting.** The message arms are asserted on `$stderr`,
  and `gitlore_say_for_agent_or_user` prints to stdout with the call site
  redirecting `>&2`. Confirmed empirically in World B that the block lands in
  `$stderr`, not `$output` — an assertion on the wrong stream would have been
  silently ABSENT.
- **`CLAUDECODE=1` selects the agent arm.** Confirmed: the agent remedy
  sentence, not the user one, appears in World B.
- **Substring-satisfied-by-another-line.** Ruled out for the header and remedy
  fragments (unique to the new text, absent from `scripts/`), and explicitly
  accounted for on `is checked out at`.
- **Deleted test.**
  `an off-pin compose refusal is reported and does not abort the commit` is
  gone, not left alongside its replacement, and it is the only test removed.
- Note for slice 2, not acted on here: the rc-1 agent remedy sentence
  `This commit also stages each tier at the commit its worktree is on now` lost
  its only assertion with that deletion. The runbook has slice 2's manifest case
  re-pin it; if that slips, the sentence ships unasserted.

## 5. Files changed by this review

- `tests/git_hook_pre_commit.bats` — added the carrier assertion and its comment
  to `the parent pre-commit hook aborts on an off-pin tier`.
- `tests/commit_memory.bats` — replaced the "No restamp" comment above the
  freshness assertion with what that assertion pins and what it cannot see.
- `plans/index-edit-propagation/reports/item-1-2-s1-red.md` — refreshed the
  stale `git diff --stat` block and the one-line description of the hook case.

`scripts/` untouched: `git diff --exit-code scripts/` clean.

## 6. Re-run after the fixes

`shellcheck -s bash tests/commit_memory.bats tests/git_hook_pre_commit.bats` —
exit 0, no findings.

`scripts/run-bats.sh tests/commit_memory.bats tests/git_hook_pre_commit.bats`:

```
not ok 12 a tier moved off its pin aborts the commit
# (in test file tests/commit_memory.bats, line 184)
#   `[ "$status" -ne 0 ]' failed
not ok 30 the parent pre-commit hook aborts on an off-pin tier
# (in test file tests/git_hook_pre_commit.bats, line 241)
#   `[ "$status" -ne 0 ]' failed

bats: 32 passed, 2 failed
```

Still red, still on an assertion, still the same two cases and no others.
Nothing committed; `just precommit` and the full suite were not run, per the
dispatch.
