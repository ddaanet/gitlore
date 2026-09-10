# Item 1.3 slice 2 — GREEN report

Both suites green (85/85, up from 132/134 on the wider set — see below), all
three ambient worlds identical. `tests/` carries no diff beyond what RED and the
test review already left (`git diff --stat tests/` unchanged: 101/156
insertions, matching the test-review's own tree-state section). Nothing staged,
nothing committed.

## Change 1 — the ahead-of-the-pin branch

`scripts/lib/index-compose.sh:333-349`, `gitlore_compose_check_pins`. New branch
between the mid-merge test and the existing sideways/diverged message, keyed on
ancestry:

```bash
if git -C "$tierpath" rev-parse -q --verify "${pinned}^{commit}" >/dev/null \
   && git -C "$tierpath" merge-base --is-ancestor "$pinned" "$head"; then
  problems="${problems}tier '$tier' is checked out at ${head:0:12}, ahead of the pin the memory store records at ${pinned:0:12}: it advanced without composing, and projecting the root index onto it would overwrite what it holds. There is no automatic remedy: inspect and stage the gitlink by hand, or return the tier to the pin, which discards the commits it carries ahead of it.
"
  continue
fi
```

**The `merge-base` guard.** Rather than capture-and-match on the rc-128
`fatal:`, I guarded with `rev-parse -q --verify "${pinned}^{commit}"` first: if
the pin were a genuine ancestor of HEAD, it would necessarily already be an
object in the tier's local database (every ancestor of a checked-out commit is),
so a pin absent from the tier's object DB can never be the ahead case — the
guard removes the expected-miss case entirely rather than suppressing git's
message on it. This follows the file's own existing convention
(`pinned=$(git … rev-parse -q --verify ":$tier") || continue` two lines above
the loop). No `2>/dev/null` and no capture variable ever reach the output.

**Wording.** Both truncated shas, "ahead", "discard" (as "discards") all present
on the tier's own report line; `checkout --detach` and `/gitlore:merge` never
appear anywhere in `gitlore_compose`'s output for this branch — verified by the
test's own negative assertions rather than by inspection alone. I did not print
a `git checkout --detach` command for the "return to the pin" remedy, per your
instruction that naming the cost is not the same as printing the command.

## Change 2 — the wrapper's remedy clause, with a conflict flagged

`scripts/lib/resolve.sh:1004-1029`. I could **not** implement this exactly as
specified: "drop the wrapper's remedy clause" breaks
`tests/commit_memory.bats:220` (a born-green regression pin you told me must
stay green), which asserts the agent arm contains the literal phrase
`"Return the tier to its pin with the command above"` for the sideways case —
and that phrase is still accurate there, since the sideways problem line prints
a real checkout command.

What I did instead: kept "Return the tier to its pin with the command above"
(true for sideways and diverged; a mid-merge tier never reaches this wrapper at
all — `gitlore_guard_stale_merge_state` catches it a few lines earlier), and
dropped only the `/gitlore:merge`-take clause, which is the piece your message
argued is unambiguously wrong regardless of cause (`/gitlore:merge` reports
nothing to take for a tier that is itself ahead of its own pin — Item 1.3's own
finding). Full diff of the sentence:

Before:
> gitlore: composing would have overwritten what that tier holds, and committing
> would have adopted the move silently. Return the tier to its pin with the
> command above, or run /gitlore:merge to take its content properly, then retry
> the commit — the approved summary is still in place.

After:
> gitlore: composing would have overwritten what that tier holds, and committing
> would have adopted the move silently. Return the tier to its pin with the
> command above, then retry the commit — the approved summary is still in place.

The user arm is untouched:
> gitlore: composing would have overwritten what that tier holds. Open this
> project in Claude Code and ask it to repair the memory store, then retry.

**Residual defect, not fixed, flagged in a comment at the edit site
(`resolve.sh:1013-1023`):** for an abort whose *only* problem is an ahead tier,
"the command above" now points at nothing — that problem line names no runnable
command by design (your instruction: name the cost, don't print the checkout).
No current test catches this because the two ahead tests in
`tests/commit_memory.bats` only inspect the extracted `tier 'ddaanet'` line,
never the wrapper's surrounding prose. Fixing it fully means the wrapper
choosing per-tier wording, which re-derives a decision
`gitlore_compose_check_pins` already made per cause — exactly the "second cause
analysis" you said not to do — or a `tests/` change, which I'm not authorized to
make. Your call whether this rides a slice 3 or the wording above is acceptable
as a partial mitigation.

**Header.** Left unweakened, per your instruction. "A tier was moved off the
commit the memory store records for it" still reads correctly for an ahead tier
— moving forward off the pin is still "off the commit the store records", and no
test needed adjusting.

## Test results

`scripts/run-bats.sh --jobs 1 tests/index_compose.bats tests/commit_memory.bats`:

- Before Change 1 (scripts/ reverted via `git stash`, tests/ as RED left them):
  **132 passed, 2 failed** — the same two failures the RED/test-review reports
  recorded (`index_compose.bats:395` and `commit_memory.bats:266`, wider-set
  line numbers).
- After both changes: **134 passed, 0 failed.**

Wider set
(`tests/index_compose.bats tests/commit_memory.bats tests/resolve.bats tests/resolve_recovery.bats tests/tier_divergence.bats`):
same before/after — 132→134, all failures in the two target files, nothing else
moved.

Three ambient worlds, target pair only, all identical:

| world | result |
| --- | --- |
| `CLAUDECODE=1` | 85 passed, 0 failed |
| `env -u CLAUDECODE` | 85 passed, 0 failed |
| `env CLAUDECODE=0` | 85 passed, 0 failed |

## shellcheck

`shellcheck scripts/lib/index-compose.sh scripts/lib/resolve.sh` — clean, no
output.

## Tree state

```
$ git status --porcelain
 M scripts/lib/index-compose.sh
 M scripts/lib/resolve.sh
 M tests/commit_memory.bats
 M tests/index_compose.bats
?? plans/index-edit-propagation/reports/item-1-3-s2-red.md
?? plans/index-edit-propagation/reports/item-1-3-s2-test-review.md

$ git diff --name-only tests/
tests/commit_memory.bats
tests/index_compose.bats
```

`git diff --stat tests/` is unchanged from the test-review's own tree-state
section (101/156 insertions) — I made no edits under `tests/`. Nothing staged,
nothing committed.
