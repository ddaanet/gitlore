# Split `git-hooks-and-entry-points.md`, and move the adoption paragraph

Both jobs are done. `just format-docs` and `python3 scripts/check-docs-links.py`
are clean, every counter 0. Nothing is committed; the only staged change is the
`git mv` rename.

## Final shape

**`docs/references/git-hooks.md`** (189 lines, renamed from
`git-hooks-and-entry-points.md` with `git mv`, so history follows)

- title `# Git hooks — decisions D46, D50`
- opening paragraph: the two hooks, what makes them stand down, the gitlink
  invariant; names `memory-entry-points.md` for the callable equivalents and
  says the shared bodies (`gitlore_sync_memory_to_live`, `gitlore_push_stores`)
  are described there; keeps the pointers to `commit-gate.md` and FR11
- summary bullets: *The pointer* — **D46**; *The commit path* — **D50**
- `## Mechanism` → `### Git Hooks`, `### The gitlink and `live`` (both verbatim)
- `## Decisions — D46, D50` with a two-clause intro, then the D46 and D50 bodies
- `## Rejected alternatives` — the amend, the compose refusal, the off-pin
  report

**`docs/references/memory-entry-points.md`** (237 lines, new)

- title `# Memory entry points — decisions D16, D20`
- opening paragraph: the two callable scripts and the `push` skill, each doing
  with no parent operation in flight what a hook does inside one, through a body
  it shares with that hook; names `git-hooks.md` for the hooks and their order,
  and `commit-gate.md` for the approval gate
- summary bullet: *Entry points* — **D16** · **D20**
- `## Mechanism` → `### Memory Commit Entry Point`,
  `### Memory Push Entry Point` (including the no-remote-publishes-tiers-anyway
  paragraph and the placeholder-url blockquote), `### The `push` skill` (all
  verbatim)
- `## Decisions — D16, D20` with its own intro, then the D16 and D20 bodies
- `## Rejected alternatives` — the three D16 counterparts

**`docs/decisions.md`** (146 lines) — one group became two adjacent groups in
the same slot, **Git hooks** then **Memory entry points**, each with its own
node pointer, conclusion stubs and `*Rejected:*` line. Every conclusion line
keeps its exact wording; only the two group headline sentences are new, because
one of them had to stop describing both halves.

**`docs/references/merge-state-recovery.md`** (96 lines) — gains the adoption
paragraph, placed directly after the four-case classification list and before
the artifacts paragraph: the list's first case is *A merge landed*, which is the
only case that adopts, and the artifacts paragraph elaborates the last two.

## The six rejected alternatives, and how each was attributed

Attribution is by the decision each one argues *against*, read from its own
body, not by which mechanism it mentions.

| Alternative | Goes to | Why |
| --- | --- | --- |
| Amending a tagged parent commit to re-pin memory after a `pre-push` merge | `git-hooks.md` | body closes `(D46)`; it is the repair D46 refuses |
| A refusal that instructs the agent to run compose | `git-hooks.md` | body closes `(NFR4, D50)`; the counterpart of D50's "compose refusal only reports" |
| Reporting an off-pin tier and committing through it | `git-hooks.md` | body closes `(D50)`; the counterpart of D50's fatal pin refusal |
| Triggering a memory commit through a parent commit | `memory-entry-points.md` | body closes `(D16)` — "the standalone entry point sidesteps all of it". **This one contradicts the dispatch**, which listed it under the hooks half. It names the hook's parent-commit requirement, but what it argues against is D16's standalone entry point, so it travels with D16. |
| Reimplementing the sentinel, `push HEAD:live` and merge-state logic in a caller | `memory-entry-points.md` | body closes `(D16)`; the counterpart of "the logic stays in `commit-memory.sh`" |
| A caller that pre-writes the commit-message file | `memory-entry-points.md` | body closes `(D16)`; the counterpart of D16's arg-driven contract |

That makes it three and three rather than the four/two the dispatch expected.

## New `D<n>`? No.

The 400-line cap is not a numbered decision — it is stated in the
`check-docs-links.py` docstring, gated by `oversized-file`, and recorded in
`docs/changelog/2026-08-25-docs-nodes-capped-at-400-lines.md`; `grep` finds no
`D<n>` for it in `docs/decisions.md` or `docs/design.md`. The cap's own wording
already prescribes the remedy ("split it along a need-time seam rather than
raising the cap"), so choosing the seam applies an existing rule. No decision is
taken, inverted or narrowed here: D16, D20, D46 and D50 keep their conclusions
and their arguments verbatim, and the highest id in use stays D51.

## Where each inbound link now points

| Link | Now | The sentence that decided it |
| --- | --- | --- |
| `docs/decisions.md` group pointer | both, one per group | the group itself split |
| `docs/design.md` §Branch Model | `git-hooks.md` | "…the gitlink invariant is in X" — `### The gitlink and `live`` stays with the hooks |
| `docs/design.md` §Components | both | "Orderings, contracts and the placeholder-remote marker are in X" spanned both halves, so it is now two clauses: hook orderings and the gitlink contract → `git-hooks.md`; the two scripts, the `push` skill and the placeholder marker → `memory-entry-points.md` |
| `docs/references/tier-stores.md` | `memory-entry-points.md` | "The publish preflight repairs that direction the same way and in place of the drift report it would otherwise make (X)" — the publish preflight is argued in `### The `push` skill` |
| `docs/references/index-composition.md` | `git-hooks.md` | "…commit path, on a dirty store, before the commit … (D50, X)" — D50 stays with the hooks |
| `docs/references/commit-gate.md` | both | "The git hooks and the two callable scripts that carry a commit or a push out are in X" spanned both halves; now one clause each |

`grep -rn 'git-hooks-and-entry-points' docs/` returns only
`docs/changelog/2026-08-25-docs-nodes-capped-at-400-lines.md:23` and
`docs/changelog/2026-08-28-a-refused-release-push-is-resolved-not-amended.md:23`,
both untouched.

## The `gitlore_adopt_recovered_merge` move

Verified against `scripts/lib/resolve.sh` before writing either half. What the
function does, and what the new prose claims:

- it is called only from `gitlore_recover_landed_merge`, in both of its success
  branches — so the *landed merge* case is the one that adopts
- it composes the tier's carrier up (`gitlore_compose_up "$super" "$rel"`) and
  then `git -C "$super" add -- MEMORY.md "$rel"`
- a non-zero up projection prints and returns 0 having staged nothing
- it fires for a tier alone: superproject present, superproject carries a root
  `MEMORY.md`, and the store's path relative to the superproject is not that
  superproject's own `submodule.<name>.path` — the clause that keeps the memory
  root's own recovery out of the user's project index
- best effort, no commit of its own: a staging failure prints the repair command

The node paragraph states all of that as its own prose, cites D43 for the
adopt-a-tier-ahead-of-its-pin shape and D50 for why the ordering is
load-bearing. In `git-hooks.md`, D50 keeps only the invariant — staging alone
returns the enclosing index to agreement with the tier's HEAD, which is the
disagreement the pin check reads, so every adopting path composes up first or
stages nothing — with a link to `merge-state-recovery.md` for the mechanism.
Seven lines became eight, none of them naming the function.

## Changelog

`docs/changelog/2026-09-11-the-hooks-node-splits-from-the-entry-points.md` (41
lines) plus its bullet at the top of `docs/changelog.md`, which is **335 lines**
after `format-docs`, up from 326, against the 400-line cap.

## Line counts after `just format-docs`

| File | Lines |
| --- | --- |
| `docs/references/git-hooks.md` | 189 |
| `docs/references/memory-entry-points.md` | 237 |
| `docs/references/merge-state-recovery.md` | 96 |
| `docs/decisions.md` | 146 |
| `docs/design.md` | 282 |
| `docs/changelog.md` | 335 |
| `docs/changelog/2026-09-11-the-hooks-node-splits-from-the-entry-points.md` | 41 |
| `docs/references/commit-gate.md` | 266 |
| `docs/references/tier-stores.md` | 252 |
| `docs/references/index-composition.md` | 315 |

## `check-docs-links.py`

```
check-docs-links: 51 decisions, 114 files scanned
  broken-link          0
  unstubbed-decision   0
  stub-without-body    0
  duplicate-decision   0
  duplicate-conclusion 0
  undefined-decision   0
  enumeration-drift    0
  delegation-drift     0
  oversized-file       0
```

Exit 0, no `orphan-reference` warning: both halves are linked from
`docs/decisions.md` by their `references/` paths.

## Git state

Staged: the rename alone, from `git mv`. `git status --short`:

```
 M docs/changelog.md
 M docs/decisions.md
 M docs/design.md
 M docs/references/commit-gate.md
RM docs/references/git-hooks-and-entry-points.md -> docs/references/git-hooks.md
 M docs/references/index-composition.md
 M docs/references/merge-state-recovery.md
 M docs/references/tier-stores.md
?? docs/changelog/2026-09-11-the-hooks-node-splits-from-the-entry-points.md
?? docs/references/memory-entry-points.md
?? plans/index-edit-propagation/reports/split-hooks-node.md
```

The `R` is the staged rename; the `M` beside it is the unstaged content edit to
the renamed file. Nothing else was added. `just precommit` was not run.

## Found against the tree

1. **One rejected alternative was listed under the wrong half** in the dispatch
   — *Triggering a memory commit through a parent commit* argues D16, so it went
   with the entry points. Detailed above.
2. **`just format-docs` re-wrapped a file outside scope.** The recipe wraps
   `plans/` as well as `docs/`, and it rewrote
   `plans/index-edit-propagation/reports/tdd-audit.md` (71 lines reflowed, no
   content change). I reverted it with `git checkout --`, so that file is back
   to its committed state. The next `format-docs` — including the one
   `just precommit` runs first — will reflow it again; it needs a commit of its
   own, or to ride whichever commit owns that report.
