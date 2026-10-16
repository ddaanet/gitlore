# Option H rewrite, final run — report

VERDICT: PASS. Nothing pushed; no repository under `/Users/david/code` changed.
Scratch root `/tmp/claude-1000/identity-rewrite-h2` (tmpfs). Push and crossing
commands: `push-commands.md`. Maps and gitlink logs: `maps/`. Method scripts
(from the scratch run, `W` updated): `scripts/`.

## Method

- `--mirror --no-local` clones of the three local repos (tier, memory store,
  gitlore), so the maps cover the local-only commits: gitlore 22519aa and
  `tier-triage-nudge`, memory `main`'s 22 commits ahead of `origin/main`.
  Remote-tracking refs and the tier's `refs/gitlore/compose-base` (7f4c65d, not
  on `live`) were deleted from the mirrors before filtering.
- tier: `git filter-repo --mailmap`. memory: the same plus
  `--commit-callback scripts/cb.py` remapping gitlinks at `ddaanet` through the
  tier map. gitlore: the same, remapping `memory` through the memory map.

## Results

| store | commits | changed ids | wrong identities after | old → new tip |
|---|---|---|---|---|
| tier | 351 | 320 | 0 | live 914c501 → 9103be7; main 7969ec8 kept |
| memory | 211 | 211 | 0 | live a116ed6 → 3878a6d; main daf5f59 → a46bdd2; origin/main 497ac39 → daf75b5 |
| gitlore | 647 | 617 | 0 (commits and 23 taggers; v0.6.0 lightweight) | main 22519aa → 3498182; origin/main e993b49 → 09e6ad8; tier-triage-nudge 76f9d8b → 17a1bb3 |

- Before: tier 55 `T <t@e.c>` authors; memory 73 T authors, 209 `gitlore@local`
  committers; gitlore 382 T, 11 T taggers.
- Per-ref commit counts equal on every branch and tag; union counts equal.
  Memory and tier `main` ancestors of `live`.
- `verify-pairs.py`: BAD 0 — dates identical, messages identical modulo embedded
  ids remapped, trees identical or differing only at the gitlink with
  tree-identical child commits, every tag and tip mapped.
- Tag objects: 24 tags, headers and bodies identical apart from tagger.
- UNMAPPED gitlinks, the same three the scratch run explained: memory 17ae38c →
  tier cabd7c6 (a discarded local compose, in no tier history); gitlore f4c6df5
  `memory` and 666ee3a `plugin-dev/memory` → 59ed770 (vendored toolkit
  snapshot). Left unchanged.

## Rehearsal

`record-rewrite.sh` against local bare copies of the two store remotes: 320 and
211 lines, `version` 1, no identity line; a rerun adds nothing. Then the archive
and force-pushes to those copies and to a copy of the gitlore remote, and
section 4 of `push-commands.md` on a copy of this checkout: `cross-rewrite.sh`
crossed the tier then the memory store; the parent reset left a clean tree, 0
wrong identities on all three, and a rerun of both crossings printed
`nothing to cross`. The first attempt exposed that a plain parent `git fetch`
recurses into submodules and fails on 59ed770; the commands carry
`--no-recurse-submodules`.

Section 5's per-clone block, run verbatim (path substituted) on a copy of craft
against the rehearsal tier remote: crossed, committed memory through the 0.10.0
`commit-memory.sh`, committed the parent through craft's 0.9.0 hooks, printed
`crossed-and-committed`. Pushes not rehearsed. GitHub: 24 releases, none draft,
before the run.

## Tier redo, 2026-10-16

The tier remote's `live` moved 914c501 → 9662781 (adfc641, 9662781: correct
identity) before the push. A fresh mirror of the remote, rewritten the same way,
reproduces all 351 earlier map lines byte for byte and adds two (adfc641 →
e8efd4d, 9662781 → 6895476; trees equal; e8efd4d's parent 9103be7). The memory
store and gitlore mirrors stay valid: their remotes and local refs did not move,
and their gitlinks reach only the unchanged part of the tier map. The earlier
tier mirrors are kept as `tier-{before,after}-914c501.git`.

Section 5 rehearsed again on a copy of cwd-safety (0.6.0 config, staged handoff
files, pending `memory` pointer) against a fresh rehearsal tier remote carrying
the 322-line record. It first failed: `commit-memory.sh` resolves its libraries
from `gitlore.hooksDir`, so the 0.10.0 script sourced 0.6.0's `util.sh`
(`gitlore_approval_present: command not found`). With `CLAUDE_PLUGIN_ROOT`
exported it passed under `env -i`: a parent commit touching only `memory`, the
other staged files left staged, tier pinned with 0 T commits.

## Carried forward

- Changelog ids, from the final maps: `27042ce` → `dd7419d`, `431faf7` →
  `38868ca` (gitlore); `ea39932` → `5cd6cfd`, `2800e0e` → `6e456cf` (tier).
- `plans/ddaanet-identity-rewrite/commit-map` is the scratch run's tier map and
  is stale; `maps/tier-commit-map` supersedes it.
- `record-rewrite.sh`'s no-op message says `on origin` even when the remote was
  given as a URL.
