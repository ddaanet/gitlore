# Batch 8 — the entry-wise index merge drops stray lines in the pointer region

## 1. Reproduction

Against unchanged code, sourcing `scripts/lib/index-compose.sh` then
`scripts/lib/index-merge.sh` and calling
`gitlore_index_merge base ours theirs MINE BASE THEIRS`:

**Case 1 — one side carries a stray non-bullet line between pointers.**

```
base/ours:  # Memory Index / (blank) / - [A](a.md) — a / - [B](b.md) — b
theirs:     # Memory Index / (blank) / - [A](a.md) — a / Stray line / - [B](b.md) — b
```

`rc=0`. Merged output:

```
# Memory Index

- [A](a.md) — a
- [B](b.md) — b
```

`gitlore_compose_check_index merged` prints nothing. The same check run on
`theirs` prints
`theirs: interleaved non-bullet line 4 inside the pointer block`.

**Case 2 — one side carries a blank line between pointers.** `rc=0`, blank line
gone, check clean.

**Case 3 — the stray line is already at base and neither side touched it.**

```
base:   - [A](a.md) — a / Stray line / - [B](b.md) — b
ours:   - [A](a.md) — a / Stray line / - [B](b.md) — b / - [C](c.md) — c
theirs: - [A](a.md) — a / Stray line / - [B](b.md) — b
```

`rc=0`, and `Stray line` is gone from the output. This is the sharpest form of
the defect: the line is in the merge base, no side edited it, and the merge
destroys it silently.

**The report is confirmed, with one addition.** The mechanism is
`_gitlore_index_merge_bullets` (`scripts/lib/index-merge.sh:70`): it rebuilds
the bullet block by iterating `gitlore_order_merge`'s merged *path* list and
emitting one line per path, so any line in the region that carries no path is
never emitted. `gitlore_merge_indexes` then `cp`s the result over the worktree
index and, at `rc -eq 0`, `git add`s it. Rule 4 of
`gitlore_compose_check_index` (`scripts/lib/index-compose.sh:294`) therefore
finds nothing at the merged-root gate in an ordinary root merge.

The addition to the report: the loss is not limited to a line one side
introduced. A stray line present on all three sides — base included — is
dropped too (case 3).

`tests/resolve_compose.bats`'s "an interleaved line in the merged root index
keeps the merge unlanded" did indeed reach rule 4 only through a duplicate
`p.md` path, and its own comment said so, calling the drop "a gap of its own".

## 2. What the design says

The docs settle this; it is not a fork.

**The precedent is in the same function, for the same reason.**
`gitlore_index_merge`'s existing refusal (`scripts/lib/index-merge.sh:131-134`):

> A side that already names one path twice is not a list of entries — keying on
> the path would collapse the pair and silently drop whichever line lost. That
> index is malformed before the merge, and `gitlore_compose_check` is what
> reports it; declining to merge leaves it intact for that check to find.

`docs/references/tier-stores.md`, D44, states the same conclusion:

> a side that already names one path twice is *declined* rather than collapsed,
> leaving the malformed index for `gitlore_compose_check` to report.

A non-blank non-bullet line inside the pointer block is the identical class:
malformed before the merge, reported by `gitlore_compose_check_index`, and
unrepresentable in a block rebuilt from a path list.

**The merged-index gate is written on the assumption that rule 4 fires here.**
`docs/references/tier-arrival-repair.md`, D52:

> Before staging, `compose_merged_indexes` exits 1 on any problem in the merged
> index — the tier's carrier for a tier merge, a duplicate, interleaved or
> welded line in root's `MEMORY.md` for a memory-root merge

and

> A defect arriving across a divergence therefore reaches the synthesis, never
> the repair.

`docs/references/index-composition.md`, D31, repeats it verbatim. A drop makes
that sentence false for the interleaved arm.

**Stray text is explicitly not normalizable.** Rule 4's own rationale
(`scripts/lib/index-compose.sh:161-162`):

> no non-blank non-bullet line inside an index's bullet region — the layout rule
> would relocate it and lose its position.

The system refuses even to *relocate* such a line inside a compose. The take's
repair (D52 rule 2) moves it verbatim to just after the last bullet and reports
the move by name; "Every other line keeps its bytes and relative order." Nothing
in the design permits dropping one, anywhere.

**Blank lines get the opposite answer, and the docs settle that too.**
`gitlore_compose_root_bullets` (`scripts/lib/index-compose.sh:797`) and
`gitlore_compose_down` both rebuild the bullet region from bullets alone, so a
blank line inside it is already normalized away by every compose pass. Rule 4
excludes blanks deliberately (`[ -n "${line//[[:space:]]/}" ]`). The merge
dropping a blank line is the normalization the rest of the system performs, not
a defect.

**Option (a) — preserve stray lines in place — is refused by D37.** The path
sequences are "paths only, never bullet text", and a stray line has no path and
no stable offset once the surrounding bullets have been reordered, added or
deleted by the merge. Preserving it would need a positional model the design
rejects.

So: **option (b), decline with rc 2**, on the existing precedent. The merged
root then carries git's own line-wise result with the stray line intact, and the
merged-index gate refuses the landing, keeping the merge prepared for a new
synthesis — exactly what D52 describes.

This is the application of D44 and D52 as written, not a new decision. No
`docs/decisions.md` entry; the node (`docs/references/tier-stores.md`, D44) is
updated.

## 3. What I did

**`scripts/lib/index-merge.sh`** — added `_gitlore_index_merge_has_stray`
(returns 0 when a side's bullet region holds a non-blank line that is not a
pointer bullet) and called it in `gitlore_index_merge`'s existing per-side
refusal loop, beside the duplicate-path check. Same `rm -rf "$tmpd"; return 2`
shape, and the comment block above the loop now carries both rules and the
blank-line exclusion.

**`docs/references/tier-stores.md`** — D44's declined-side sentence extended
with the stray-line rule, why the merged block cannot hold such a line, the
consequence for the merged-index gate (cross-linked to D52), and the deliberate
blank-line asymmetry.

**`tests/index_merge.bats`** — three tests in the `--- refusal ---` section.

**`tests/resolve_compose.bats`** — the misleading arrangement fixed. "an
interleaved line in the merged root index keeps the merge unlanded" no longer
carries a duplicate `p.md`; the stray line alone now reaches the gate, which is
what the test is named for. Its comment states the real mechanism.

## 4. Red and mutation evidence

**Red 1 — `tests/index_merge.bats:257`,
"a side with a stray non-bullet line inside its pointer block is declined".**
Against unchanged `scripts/lib/index-merge.sh`:

```
not ok 21 a side with a stray non-bullet line inside its pointer block is declined
# (in test file tests/index_merge.bats, line 257)
#   `[ "$status" -eq 2 ]' failed
```

**Red 2 — `tests/index_merge.bats:266`,
"a stray line every side inherited from the base is declined too".**

```
not ok 22 a stray line every side inherited from the base is declined too
# (in test file tests/index_merge.bats, line 266)
#   `[ "$status" -eq 2 ]' failed
```

Both fail on their own assertion (`[ "$status" -eq 2 ]`), with the merge
returning 0.

**Mutation 1 — "a blank line between bullets is normalized away, not declined"
(`tests/index_merge.bats:271`) was green from birth.** Subject had uncommitted
edits, so `scripts/mutate-and-run.sh` refuses; mutated and inverted by hand.
Mutation: in `_gitlore_index_merge_has_stray`, replace
`[ -n "${line//[[:space:]]/}" ] || continue` with `:` — i.e. let the stray rule
catch blank lines too. Result: **KILLED**.

```
not ok 23 a blank line between bullets is normalized away, not declined
# (in test file tests/index_merge.bats, line 275)
#   `[ "$status" -eq 0 ]' failed
```

Restored and verified byte-for-byte against a pre-mutation copy (`cmp -s`).

**Mutation 2 — the rewritten `tests/resolve_compose.bats` test.** Mutation:
delete the `_gitlore_index_merge_has_stray` call line from
`gitlore_index_merge`'s refusal loop, which is the unfixed behaviour. Result:
**KILLED**.

```
not ok 21 an interleaved line in the merged root index keeps the merge unlanded
# (in test file tests/resolve_compose.bats, line 657)
#   `[ "$status" -eq 1 ]' failed
```

The continuation exits 0 and lands the merge, because the stray line was merged
away. This is the end-to-end form of the defect: without the fix, the rewritten
test shows the merge landing a root index the gate was meant to refuse.
Restored and verified byte-for-byte.

## 5. Suites run

Grep for the changed scripts and their function names
(`index-merge.sh`, `gitlore_index_merge`, `gitlore_merge_indexes`,
`_gitlore_index_merge_bullets`, `gitlore_index_merge_paths`,
`gitlore_index_paths_in`, `gitlore_conflicted_indexes`) names
`tests/resolve_compose.bats` and `tests/index_merge.bats` directly, plus
`scripts/add-tier.sh` and `scripts/lib/resolve.sh` as sourcing callers. I ran
every suite that reaches either, plus the requested three. All foreground, one
at a time.

| Suite | Result |
| --- | --- |
| `tests/index_merge.bats` | 23 passed, 0 failed |
| `tests/resolve_compose.bats` | 29 passed, 0 failed |
| `tests/add_tier.bats` | 38 passed, 0 failed |
| `tests/cc_hook_add_tier.bats` | 12 passed, 0 failed |
| `tests/cc_hook_index_compose.bats` | 32 passed, 0 failed |
| `tests/commit_memory.bats` | 38 passed, 0 failed |
| `tests/index_compose.bats` | 90 passed, 0 failed |
| `tests/merge_commit_hygiene.bats` | 10 passed, 0 failed |
| `tests/merge_memory.bats` | 42 passed, 0 failed |
| `tests/push_behind_vs_diverged.bats` | 21 passed, 0 failed |
| `tests/push_rejection_discriminator.bats` | 9 passed, 0 failed |
| `tests/resolve.bats` | 8 passed, 0 failed |
| `tests/resolve_both_flavors.bats` | 4 passed, 0 failed |
| `tests/resolve_merge_briefing.bats` | 8 passed, 0 failed |
| `tests/resolve_merge_local.bats` | 4 passed, 0 failed |
| `tests/resolve_merge_remote.bats` | 3 passed, 0 failed |
| `tests/resolve_recovery.bats` | 23 passed, 0 failed |
| `tests/tier_divergence.bats` | 20 passed, 0 failed |
| `tests/integration_replay_guard.bats` | 7 passed, 0 failed |
| `tests/global_shim.bats` | 5 passed, 0 failed |
| `tests/bsd_portability.bats` | 3 passed, 0 failed |
| `tests/plugin_distribution.bats` | 15 passed, 0 failed |
| `tests/lint_shell.bats` | 3 passed, 0 failed |
| `tests/check_docs_links.bats` | 43 passed, 0 failed |

Docs: `just format-docs` rewrapped the edited paragraph
(`Fixed 1/40 issues in 1 file`). `python3 scripts/check-docs-links.py` reports
54 decisions, 121 files, zero findings in all nine categories.

## 6. Left uncommitted

```
 M docs/references/tier-stores.md
 M scripts/lib/index-merge.sh
 M tests/index_merge.bats
 M tests/resolve_compose.bats
```

No new files, no changelog entry (the sibling batch commits on this plan carry
none), no `docs/decisions.md` change.

## 7. For my human partner

Nothing is waiting on a ruling. Two behaviour changes worth knowing about, both
intended:

- A divergence merge over an index that already carries a stray non-bullet line
  — including one nobody in this merge touched, sitting in the merge base — now
  refuses to land and sends the merger back for a new synthesis. The remedy is
  one edit to the named line. This is the same shape the duplicate-path refusal
  has had all along, and it is what D52's gate describes; before this change
  such a merge landed with the line silently deleted.
- The entry-wise pass now declines more often, which means git's line-wise
  result stands more often. That result can itself carry a duplicate pointer —
  the accepted trade the existing duplicate refusal already makes, and the
  merged-index gate catches it.
