# Tier conflicts — decision D44

How two writers' concurrent changes to a shared tier are merged: the semantic
merger for memory files, the entry-wise pass for index files, and the briefing
the merger sub-agent is given. Read it while debugging a tier merge, the
index-merge pass or the merger's inputs. The tier's commit, push and pinning are
in [tier-stores.md](tier-stores.md); the divergence path that calls the merge is
in [merge-and-resolve.md](merge-and-resolve.md).

- Tier merges — **D44** shared-tier conflicts resolve semantically; memory
  merges as prose, indexes entry-wise

---

**D44 — Shared-tier conflicts resolve semantically; memory merges as prose,
indexes entry-wise**

Two repos inserting into a tier's `MEMORY.md` concurrently are resolved the same
way as any memory divergence — the semantic memory-merger sub-agent, which
merges both insertions without duplicating them. A `merge=union` driver is
deliberately *not* used: it concatenates blindly and would leave duplicate
pointer lines needing a cleanup pass. And because each index occupies a distinct
filename namespace — the root holds bare project paths, each tier carrier only
that tier's filenames — composed blocks never share a path across indexes
either. So no duplicate-pointer residue arises on any of gitlore's own paths,
and no dedup pass is needed there; an arrival from a writer outside gitlore that
carries one is repaired by the take (D52). No append-only constraint is imposed;
conflicts are expected rare (the more global a tier, the more stable it
presumably is).

**Memory files merge as prose with a base section; index files merge as
entries.** `gitlore_prepare_merge` runs git's own three-way with
`merge.conflictStyle=diff3`, so every conflict the sub-agent reads carries the
`|||||||` base — which side *changed* a line is unknowable from two versions
alone, and that is precisely the judgement a semantic merge asks for. Index
files then go through a second, entry-wise pass (`scripts/lib/index-merge.sh`),
because an index is a list of records keyed by pointer path and a line-wise
merge reads it as prose. That misreading fails in both directions: two sides
inserting **different** facts at the same offset conflict textually although
nothing is in dispute, and two sides inserting the **same path** at different
offsets do not conflict at all and yield a duplicate pointer — the state
`gitlore_compose_check` refuses on, so the silent textual success is what
strands the store. The entry-wise pass keys on the path and applies D34's
presence rule (at base → survives iff both keep it; new since base → survives if
either adds it), resolves text against the base, and emits a diff3 chunk only
for a path both sides moved apart. It runs on **every** index in the merge, not
only the ones git flagged, since the duplicate arises from a merge git considers
clean; a side that already names one path twice is *declined* rather than
collapsed, leaving the malformed index for `gitlore_compose_check` to report. A
side carrying a non-blank non-bullet line inside its pointer block is declined
for the same reason: the merged block is rebuilt from the merged path list, so a
line carrying no path has nowhere to land, and merging it away would exit 0 on
the defect rule 4 of `gitlore_compose_check_index` exists to refuse — leaving
the merged-index gate (D52, in [tier-arrival-repair.md](tier-arrival-repair.md))
nothing to find. Declined, git's line-wise result stands with the line in it. A
*blank* line there is not that: composition rebuilds every bullet region from
its bullets alone, so the pass normalizes one away exactly as the rest of the
system does. Because the pass resolves an index in the worktree without staging
it, `conflicted_files` in the state file is the union of git's unmerged entries
and `gitlore_conflicted_indexes`. Its chunks carry **git's own labels** — `HEAD`
for the authoritative side (checked out detached by the prepare) and the
incoming commit's sha — rather than a vocabulary of gitlore's own, so one merge
never presents the sub-agent with two namings of the same two sides. That is one
argument at the call site, against a sentence in `agents/memory-merger.md`
reconciling the two: a configuration that removes the need for agent-facing
prose beats the prose.

**The merger sub-agent is briefed with both side diffs and the tree.** Alongside
the state file, `gitlore_prepare_merge` writes three read-only artifacts into
the store's gitdir — `gitlore-merge-mine.diff` (base→authority),
`gitlore-merge-theirs.diff` (base→pending) and `gitlore-merge-tree` (`ls-files`)
— named in the state file as `mine_diff`, `theirs_diff` and `tree`. The merged
worktree shows the outcome but not the intent, and re-deriving the intent is
work the sub-agent would otherwise do with git commands it should not be
running. `gitlore_clear_merge_state` is the single remover for the state file
and all three, so a briefing cannot outlive its merge and be read against the
next one. **`No conflict.` is an explicit valid answer** for the sub-agent:
divergence is a git fact, not a semantic one, and a merge whose two sides say
compatible things is the common case. It is a finding to check, not an admission
that the work was skipped — the agent still reads both diffs and the changed
files, still stages them by explicit path, and still stops for approval.

## Rejected alternatives

**An append-only constraint on shared-tier indexes.** Unnecessary. Concurrent
insertions merge through the same semantic path as any memory divergence, and
distinct per-index namespaces prevent cross-index collision, so conflicts
resolve without constraining where the agent may insert (D44).

**A `merge` driver plus `.gitattributes` for the entry-wise index merge.** The
driver has to be configured per *clone* — `memory/`, every tier, every linked
worktree's tier clone — and when the pin goes stale git falls back to a text
merge **silently**, which is the exact failure the entry-wise pass exists to
prevent. gitlore drives every memory merge itself, so the pass has a guaranteed
call site and no per-clone configuration (D44).

**`**/MEMORY.md merge=union` plus a dedup-by-path pass.** The union driver
concatenates blindly and manufactures the duplicate lines the dedup then cleans
— solving a problem it creates (D44).
