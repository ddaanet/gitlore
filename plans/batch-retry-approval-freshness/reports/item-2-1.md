# Item 2.1 — docs for the batch-path commit gate (D56)

## Files changed

- `docs/references/commit-gate.md` — the opening bullet list gains D56; the
  standalone-commit paragraph now says the hook runs `commit-memory.sh` **bare**
  (it still read `commit-memory.sh -F <msgfile>`, false as of `16abc35`); the
  "Both IPC files are removed only on a complete commit" paragraph is rewritten
  and split into three — the mtime gate as the same gate the parent `pre-commit`
  path runs, then the three failure states read off the store and the IPC file
  (consumed / freshness `no` / freshness `yes`), then *no summary* meaning absent
  or blank on both entry points. `## Decisions — D4, D12, D19, D22` becomes
  `… , D56`, and the D56 argument is added at the end of that section: the
  `-F <msgfile>` self-operand restamp, the bare invocation closing it, D53's
  cost-asymmetry reasoning carrying over against a per-arm status, the blank
  screen on both entry points, and the mtime-order residual. Five rejected
  alternatives appended to `## Rejected alternatives`, each ending `(D56)`.
- `docs/references/memory-entry-points.md` — the `commit-memory.sh` usage list
  in Mechanism gains the bare form and what it judges by; its guard line changes
  from "Dirty with no summary supplied → exit 1" to "dirty with the approval
  absent or blank → exit 1 …; dirty with a stale one → the sync's own refusal".
  In D16, "satisfied by construction" is scoped to the arg path and the bare
  invocation's freshness verdict is stated.
- `docs/decisions.md` — one `- **D56** — …` line under "The commit gate", and
  the five rejected alternatives appended by name to that group's `*Rejected:*`
  line.
- `docs/changelog/2026-09-24-the-batch-retry-is-judged-by-the-approval-freshness.md`
  — new, named like its siblings. Carries the narrative: the defect, what moved,
  the two refusal loops the reviews closed (zero-byte then all-whitespace), the
  mis-routed consumed-approval arm, and the two pre-existing defects the
  checkpoint flagged and did not fix.
- `docs/changelog.md` — index line at the top, in the siblings' form.

`docs/design.md` is **not** changed: its hub summary of the commit gate
enumerates no decisions. `rg D55 docs/design.md` returns one hit, in NFR12's
prose, where D55 is cited as the gate behind the line cap — the Workflows and
Architecture sections name nodes and workflows, not decision ids, so there is no
D55-shaped pattern to mirror for D56. The decision graph is carried entirely by
`docs/decisions.md` and the node, which `check-docs-links.py` confirms.

## Checker output

`python3 scripts/check-docs-links.py` — `56 decisions, 136 files scanned`, 0 in
every category: `broken-link`, `unstubbed-decision`, `stub-without-body`,
`duplicate-decision`, `duplicate-conclusion`, `undefined-decision`,
`enumeration-drift`, `delegation-drift`, `oversized-file`. (55 decisions before
this item; D56 is stubbed in the index, argued in `commit-gate.md`, and named in
that node's `## Decisions` heading, so none of the three drift checks fires.)

`python3 scripts/check-memory-hygiene.py` — `67 facts, 162 files scanned`, 0 in
every BLOCK category (`frontmatter`, `name-drift`, `first-person`,
`direct-naming`, `pre-rename`, `broken-reference`, `volatile-state`);
`deictic 15 (warn)` and `dangling-wikilink 6 (warn)` are the pre-existing
warn-level counts over `memory/`, which this item does not touch.

## `just precommit` verdict

Run in the foreground, exit 0. Checks that passed:

- `format-docs` — rumdl 0.2.60 (the `pyproject.toml` pin), `fmt` over `docs`
  and `plans`; `Found 44 issues in 14/216 files` is the MD013 residue it
  reprints and cannot rewrap, not a failure — the recipe exits non-zero only on
  rc≠0. Reflowed the four edited docs before the checkers ran.
- `check-distribution` — cached (inputs unchanged)
- `check-memory-hygiene` — as above, 0 in every BLOCK category
- `check-docs-links` — as above, 0 in every category
- `check-version` — in sync (0.8.0)
- `lint` — cached (inputs unchanged)
- `test-unit` — cached (inputs unchanged)
- `test-integration` — cached (inputs unchanged)

The four cached gates are a valid pass rather than a skipped one: this item
changes only `docs/`, which is outside `precommit_inputs`, so re-hashing each
recipe's declared inputs reproduces the gate written by the Phase 1 runs.
`check-memory-hygiene` and `check-docs-links` are uncached by design and ran in
full, which is precisely the placement a docs-only commit needs.

## Commit

`4b27cda94bb14961df425b7da2507d7de5f39450` — `docs: Item 2.1 — the batch retry
is judged by the approval's freshness (D56)` (gitmoji-prefixed 📝 by the
commit-msg hook), the five files above together. `memory/` was clean, so the
parent pre-commit hook did not block.

This report is uncommitted, as its siblings were at the same point: it names the
commit it describes, so it is swept into the next one.
