## Brief: two gitlore defects — hook install after `exec`, and compose reverting a tier merge

2026-07-30

Both found while mounting the shared `ddaanet` tier into `claude-plugin-dev`.
Both reproduced and diagnosed; neither is speculative. gitlore 0.4.3, loaded
from `~/.claude/plugins/cache/ddaanet/gitlore/0.4.3`.

### Decisions

- Both defects are real and worth fixing in gitlore itself, not worked around
  per-repo. Each one silently produced a wrong result that looked like success.
- Defect 1 was fixed locally in `claude-plugin-dev` only, by hand. That repair
  is not the proposed upstream fix — it is a one-repo unblock.
- Defect 2 was repaired by hand after the fact. Nothing in gitlore detected it.

### Defect 1 — installer appends its hook line after an existing `exec`

`claude-plugin-dev/.git/hooks/pre-commit` already existed with body:

```sh
#!/bin/sh
exec just precommit
```

The installer appended, producing:

```sh
#!/bin/sh
exec just precommit

# gitlore: managed
exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"
```

`exec` replaces the process, so the gitlore line is unreachable dead code.

Symptom: commits succeed and the project gate runs, so everything looks
healthy — but `gitlore_sync_memory_to_live` never runs. A parent commit was
made recording the memory gitlink at its pre-migration SHA, with the entire
migration left uncommitted in the submodule worktree. No warning at install
time, and none at commit time.

Masking factor: `pre-push` had no pre-existing content, so it was written
gitlore-only and worked. Push-path behaviour therefore looked correct while
the commit path was dead.

Relevant: `.gitlore.precommitCommand` in `.claude/settings.json` is NOT run by
the pre-commit hook. Per `scripts/cc-hooks/post-tool-use.sh` it is only a
string prefix used to decide whether to emit the dirty-memory nudge. So the
installer cannot assume it may replace an existing hook body — the project's
own gate lives there and must survive.

Local unblock applied (not the proposed fix): drop `exec` from the first line
and chain, `just precommit || exit 1`.

Suggested upstream behaviour: detect that the existing hook body reaches an
`exec` (or simply that gitlore's line is not the first executable statement)
and refuse to install silently — warn, or interpose so both run.

### Defect 2 — composition reverts an incoming tier merge

Sequence, all on `memory/ddaanet` (the shared tier):

1. `git push` in the parent → pre-push emitted `memory merge prepared`
   (`flavor=head-vs-remote`). Upstream had advanced 8 commits, including
   `bc58a4e` "Restore lost index triggers, compact MEMORY.md, document the
   process" — a 59+/57− rewording of the carrier index.
2. `gitlore:resolve` → `memory-merger` → continuation. Merge committed as
   `d8abfe5` and pushed to `origin/live`. **The merge was correct**: carrier
   diff vs `origin/live` was 8 insertions, 0 deletions — upstream's compaction
   preserved, our 8 new pointers added.
3. Composition then ran and rewrote `memory/ddaanet/MEMORY.md`: 56 insertions,
   56 deletions against `origin/live`. It mirrored the *store's* root
   `MEMORY.md` wording down over the carrier, overwriting 56 of upstream's
   compacted lines with the pre-compaction text. Example:

```
after compose: …FOUR classes (TUI-local / harness-action queued / plugin-command own-turn / prose injected into the running turn)
upstream:      …FOUR classes (TUI-local/harness-action-queued/plugin-command-own-turn/prose-injected-mid-turn)
```

The `PostToolBatch` notice states: "Composition moves or drops lines; it never
changes a line's text." That is false in effect — substituting root's version
of an existing line is a text change to the carrier.

It escaped history only by luck: the merge had already been committed and
pushed, so the revert sat uncommitted in the worktree and was caught by
diffing against `origin/live`.

Collateral: root index was 25621 bytes, over the 25600 loader budget and
therefore truncating. Upstream's compaction is what brought it to 24222. The
revert reintroduced the overflow.

This trap is already documented in the tier itself
(`ddaanet/reference_gitlore_tier_merge_direction.md`) — root is canonical,
compose only pulls up lines root is *missing*, so a tier fast-forward leaves
root stale and the next compose reverts upstream. Known, but nothing in the
tooling prevents, detects, or warns.

Suggested upstream behaviour: after a merge into a tier, treat the merged
carrier as canonical for lines root already holds and propagate up; or at
minimum refuse and report when composition would change the text of an
existing carrier line, rather than doing it silently.

### Constraints

- The resolver reported healthy throughout defect 2. Neither defect surfaces
  through any existing gitlore check.
- Reproduction requires a repo with a pre-existing `pre-commit` (defect 1) and
  a tier that has advanced upstream since the local clone (defect 2).

### Rejected approaches

- Removing `exec just precommit` outright — drops the project's quality gate,
  since `precommitCommand` does not cause the hook to run it.
- Hand-editing the reverted carrier back — root is canonical, so the next
  compose would revert it again. Root had to be corrected first.

### Additional context

Repair actually applied in `claude-plugin-dev`: restored the carrier from
`d8abfe5`, rebuilt root's `ddaanet/` block from that carrier (paths
re-prefixed), kept the one project-local pointer. Verified after: identical
pointer sets (104), no wording drift, 104/104 files indexed, root 24222 bytes.
