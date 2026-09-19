# batch9 — the changelog entry for `a5087ca..HEAD`

## Files written

- `/Users/david/code/gitlore/docs/changelog/2026-09-19-a-tier-ahead-of-its-pin-returns-to-it-and-a-stray-line-reaches-the-check.md`
  — new, 161 lines after `just format-docs`, under the 400 cap. Nine paragraphs,
  no headings, matching the two neighbouring entries' shape. Title carries
  `(D44, D50, D52)`.
- `/Users/david/code/gitlore/docs/changelog.md` — one "Newest first" index line
  at the head of the list, summarizing the entry in the neighbours' form.

Nothing else was touched. No commit, no `git add`, no branch, no test suite run.

## Corrections to the subject list, from the diffs

- **The pin guard's return is conditional, not unconditional.** The brief said
  "a tier merely ahead of its pin returns to the pin". The branch at
  `scripts/lib/index-compose.sh` fires only when the tier is *clean* and its
  local `live` contains `HEAD` (`gitlore_memory_dirty` = 0, `merge-base
  --is-ancestor "$head" "$live"`). A dirty tier, one with no `live`, and one
  whose `live` is short of or diverged from `HEAD` are all still refused where
  they stand — that is the same arm whose wording lost the hand rebuild. The
  entry states the condition.
- **There is a third outcome in that branch**: a checkout that fails leaves the
  tier untouched, folds git's own message onto the problem line, and prints the
  `checkout --detach <pin>` command. Stated.
- **The rootless notice is the compose hook's alone.** Both `PostToolBatch`
  hooks bailed on the missing index; only `scripts/cc-hooks/index-compose.sh`
  gained the reporting branch. The entry says "the compose hook now says so"
  rather than implying both.
- **The empty-`additionalContext` change is defensive, not a fix.** Batch 2
  verified no producer reaches that state today (`gitlore_compose_and_report`
  and `gitlore_relay_drain` both set either both channels or neither), and the
  tests drive the hooks through a plugin-root seam to reach it at all. The entry
  says so rather than presenting it as a bug fixed.
- **D52's role in the stray-line item is as the gate, not as the change.** Batch
  8 recorded no new decision: the refusal applies D44's existing precedent, and
  what it restores is D52's stated behaviour of the merged-index gate. The entry
  and the title attribute it that way.

## Deliberately left out

Per the brief's "leave out pure test pins and housekeeping": the `.claude/rules/shell.md`
bullet on the Bash tool suppressing `set -e`, the bats bash-4.1 assertion floor
recorded in `tests/bsd_portability.bats` and `docs/references/testing.md`, the
`plans/index-edit-propagation/recall-artifact.md` repointing of four retired
memory files, the behind-arm retry-push wording pin, the `cp -p` mode pin, the
`hash-object --no-filters` CRLF pin, and the spaced-path pin-guard cases. Also
left out: the one-sentence addition to `skills/memory-writing/SKILL.md` in
`96e7dfe` (a relocated fact leaves the store in the change that lands it in its
owner) — real guidance, but it belongs to the memory-writing skill's own thread
rather than to this run's subjects. Flagging it in case you want it folded in.

## Checker results

- `just format-docs` — rc 0, `Fixed 4/43 issues in 1 file`: the new entry
  rewrapped. No other file changed.
- `python3 scripts/check-docs-links.py` — rc 0, `54 decisions, 122 files
  scanned` (121 before; the new entry is the extra file), every one of the nine
  counters at 0, `oversized-file` included.
