# Item 4.3 — report

## Files written

- `docs/changelog/2026-09-11-the-commit-path-composes-before-it-commits.md`
  (new) — title
  `# 2026-09-11 — The commit path composes before it commits (D50, D51)`, six
  paragraphs: the hole (`gitlore_compose`'s three callers, the carrier that
  ships because it is what a tier's remote serves); the placement in
  `gitlore_sync_memory_to_live` ahead of `gitlore_sync_tiers_to_live` and the
  gitlink lag it prevents; dirty-only and the FR11 boundary; the asymmetry
  between the compose refusal and the pin refusal, with the `add -A` adoption
  chain and the rc-2 restamp; per-(agent, batch) keying and the race it closes;
  the subagent relay through the keyed marker.
- `docs/changelog.md` — one newest-first bullet at the top of the list, above
  the 2026-09-07 entry. Nothing else in the file changed.

Every behavioural claim was taken from the scripts, not the hub:
`gitlore_sync_memory_to_live` in `scripts/lib/resolve.sh` (the pin guard ahead
of the compose, the rc 0/1/2/unknown arms, the `touch "$msgfile"` restamp and
its absence on the pin abort), `gitlore_index_preimage_file`,
`gitlore_compose_stamp_file`, `gitlore_relay_marker_file`,
`gitlore_relay_write`, `gitlore_relay_drain` and `_gitlore_agent_suffix` in
`scripts/lib/index-sync.sh`, and the `agent_id` reads and relay/drain blocks in
`scripts/cc-hooks/index-sync-pre.sh`, `index-sync-post.sh`, `index-compose.sh`,
`add-tier-batch.sh` and `session-start.sh`. No test count, slice number or
RED/GREEN detail appears in either surface, and neither cites `plans/` or
`memory/`.

## `check-docs-links.py`

```
$ python3 scripts/check-docs-links.py
check-docs-links: 51 decisions, 112 files scanned
  broken-link          0
  unstubbed-decision   0
  stub-without-body    0
  duplicate-decision   0
  duplicate-conclusion 0
  undefined-decision   0
  enumeration-drift    0
  delegation-drift     0
  oversized-file       0
rc=0
```

112 files scanned, one more than Item 4.1+4.2's 111 — the new entry file.

## Line counts, measured after `just format-docs`

| file | lines | cap |
|---|---|---|
| `docs/changelog/2026-09-11-…-composes-before-it-commits.md` | 71 | 400 |
| `docs/changelog.md` | 326 | 400 |

`just format-docs` exits 0, reporting `Fixed 1/80 issues in 1 file` — the one
fix is the reflow of a line in the new entry. `oversized-file` is 0, which is
the cap check itself.

## What the item text got wrong against the tree

- **The date.** The runbook names
  `docs/changelog/2026-09-06-the-commit-path-composes-before-it-commits.md`;
  execution landed on 2026-09-11, so the file carries that date. Slug unchanged.
- **`docs/changelog.md` "is well under the cap".** True, but less roomy than the
  phrasing suggests: it was at 318 lines before this bullet and is at 326 after,
  so the index has 74 lines of headroom left and an entry's bullet costs 8.
  Nothing is blocked today; the index is the file that grows every entry.

## Not done, deliberately

No `just precommit`, no `git add`, no commit. Both edits are uncommitted —
`docs/changelog.md` modified, the entry file untracked.
