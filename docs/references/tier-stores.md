# Tier stores — decisions D42–D44

How each tier's own git store is committed, pinned and merged. The commit and
merge paths reach this node from outside the tiered-memory subsystem, so it
reads standalone; the subsystem's entry point is
[tiered-memory.md](tiered-memory.md).

- Stores and merges — **D42** tier commit/push lockstep is driver-side · **D43**
  a tier is pinned at its gitlink, and advancing one is a merge · **D44**
  shared-tier conflicts resolve semantically. All three assume the
  detached-at-`live` branch model, which is D41, in
  [merge-and-resolve.md](merge-and-resolve.md).

---

**D42 — Tier commit/push lockstep is driver-side, with one approval per
episode**

A tier commit rides the same before-and-alongside staircase the parent already
applies to memory, one level deeper: `gitlore_sync_tiers_to_live` commits every
dirty tier and advances its local `live` *before* memory's own `git add -A`, so
the moved gitlink is part of the memory commit rather than lagging it;
`pre-push` pushes each tier's `live` to its own remote *before* memory's, so the
pointer never goes out ahead of what it points at. Two decisions the shared
driver rests on:

*One approval summary per memory episode, not per tier.* The gate is keyed to a
single message file, and the episode's approved summary is reused verbatim as
the commit message in every store it touched. The user approves a set of
*writes*, not a set of repositories; N prompts for one decision buys no extra
information. What the approval prompt owes the user is
**grouping by destination** — a line bound for a shared tier is more public than
one bound for project memory, and that difference is the only part of the split
that carried real content.

*No recursing `pre-commit`/`pre-push` in the memory store.* Recursion is
driver-side, exactly as the parent already drives memory: the parent's hooks
call the sync function and push explicitly rather than relying on a hook one
level down. A hook-side version would re-litigate the full `--local-env-vars`
unset and the `GIT_INDEX_FILE` capture/restore at a level that needs neither,
and would force the FR11 gate to share `memory-pre-commit` with the driver — the
gate exits 0 on its first line under the blessed sentinel, so the two would
diverge by sentinel inside one hook. `memory-pre-commit` stays a pure gate and
is now *emitted into each tier as well*, since neither the parent's hooks nor
memory's own gate reach a submodule-inside-a-submodule; each tier gets its own
`gitlore.hooksDir` mirror because the wrapper's `git config` reads whichever
store it fires in.

Scope is every **mounted** tier, not only the active ones: the manifest governs
routing and composition, and silently dropping a dormant tier's writes would be
data loss rather than dormancy. Each loop guards `[ -e "$tierpath/.git" ]`
before any `git -C` — into an unchecked-out submodule that escapes to the
enclosing repo, which would have committed *memory* under the tier's name and
pushed memory's `live` to the tier's remote. Tier divergence surfaces at both
gates — the pending commit against the tier's local `live` (`head-vs-live`) and
local `live` against the tier's own remote (`head-vs-remote`) — is reported by
tier name with git's own reason, and resolves through the same merge path as
memory: each gate yields to `gitlore_yield_merge`, the state file names the
store the merge was prepared in, and the continuation finds it by walking the
stores ([workflows.md](workflows.md)).

**D43 — A tier is pinned at its gitlink; advancing one is a merge**

SessionStart checks each tier out at the commit the memory tree records for it —
`submodule update --init`, on every session and not only when the tier was never
materialized, since a clone made before this model already sits ahead of its
gitlink and has to be put back — and nothing advances it silently. One memory
commit records the root `MEMORY.md` and the tier gitlink together, so root's
tier block and the carrier index it projects are consistent *by construction*; a
tier that fast-forwarded on its own leaves root describing one commit and the
carrier holding another, and nothing downstream repairs that — composition
places lines, it does not merge them. So composition refuses instead: the down
projection compares each active tier's `HEAD` against the gitlink the memory
store's index records and writes nothing when they differ, because projecting
root's older block onto a carrier nothing adopted up overwrites approved
upstream text and reports success (D31). Taking an upstream commit is therefore
a merge, through `/gitlore:merge` or `/gitlore:push`.

**Taking is three cases, not one.** Both commands classify each store by
ancestry against the fetched `origin/live`. A remote already contained in `HEAD`
is nothing to take — local commits awaiting publication are the push's business,
and reporting them as waiting would send the user into a merge with nothing to
merge. A `HEAD` that is an ancestor of the remote is taken by
**fast-forward plus adoption**: the local `live` advances, the working tree
follows, and the arrived carrier is projected up into root's block for that
tier. No sub-agent — nothing is in dispute, and spending a synthesis on a
fast-forward would make taking upstream facts expensive enough to skip. Only a
genuine divergence prepares a merge and yields. A store with uncommitted changes
is refused rather than checked out over: the working tree may hold this
session's unapproved facts.

**Nothing to take is not nothing to do.** That first case is decided from
`HEAD`, while the ref a push sends is `live`, and a store rests detached *at*
`live` — so a `live` strictly behind a `HEAD` that contains it is a ref that
failed to keep up rather than a state anything chose, and the take advances it
with a local ff-checked `push . HEAD:live` rather than leaving it there. The
publish preflight repairs that direction the same way and in place of the drift
report it would otherwise make
([git-hooks-and-entry-points.md](git-hooks-and-entry-points.md)). The move
itself publishes nothing: every commit in `HEAD` reached it through a gate. The
producer is
a merge preparation that checked `HEAD` out at `origin/live` and could not
continue, which leaves the remote contained in `HEAD` and `live` where it was —
the store then calls itself finished on every later take while every push is
refused as a non-fast-forward. That direction is the one *repaired*.

**The other direction is a take, and a checkout is what breaks it.** A tier's
`live` ahead of a `HEAD` sitting at the pin holds commits the memory store never
recorded — a tier commit advances both refs together, so the two part only when
the memory side loses the moved gitlink afterwards (a merge preparation checks
the memory store out and rewrites its index), and the next SessionStart pins
`HEAD` back while `live` keeps what was approved. Nothing reports it: `live` is
invisible to the take's ancestry test and to SessionStart's, both of which read
`HEAD`. Neither ref may be moved onto the other — rewinding `live` discards
approved commits, and moving `HEAD` alone takes the tier off the commit the
store records, which is precisely the state the down projection refuses. So the
publish gate's bare "put `HEAD` back on `live`" remedy is the one that breaks
the store, and a tier is sent to the take instead. `gitlore_adopt_advanced_live`
runs the same fast-forward-plus-adoption a remote arrival gets, sourced from the
local ref and moving no ref at all, at the head of every take and from the
publish preflight; `gitlore_adopt_tier_into_root` is the tail the two share. The
preflight runs the *whole* take pass rather than adopting the one tier, for the
reason the behind-tier branch gives: it goes root-first, and a tier's
bookkeeping commit would otherwise meet an equally-behind root's upstream one as
a divergence.

The memory root is excluded from that adoption. It has no pin above it —
SessionStart checks it out at `live` and the parent's gitlink is allowed to lag
(D46) — so there a `live` ahead of `HEAD` is answered by the checkout the
session would make anyway, which is what the gate names for the root and only
the root. A `HEAD` and `live` that have each moved since they last agreed are
reported and left untouched at every level, because which one was intended is
not recoverable from the refs.

The tier fetch stays, **read-only**: `fetch origin live` with no refspec moves
no local branch, and its only job is to let SessionStart *name* a tier whose
remote is ahead or has diverged, by comparing `HEAD` and `FETCH_HEAD` for
ancestry. Ancestry rather than a refusal message, because a fetch that attempts
no ref update is refused for nothing — and ancestry is what distinguishes an
upstream arrival from local commits merely awaiting their lockstep push, which
must not be reported as waiting. A prepared merge is detected *before* anything
checks out: `git checkout`, which `submodule update` runs, unlinks `MERGE_HEAD`
and `MERGE_MSG` silently and on success, so a tier mid-merge is skipped entirely
and said so on both channels. A tier that arrived attached to a branch is
detached in place (no ref argument, so the commit does not move) — the branch
model has no working branch, and a commit made on one would advance a ref the
lockstep never reads.

The recomposition that follows is **committed by the take itself** (D49, in
[merge-and-resolve.md](merge-and-resolve.md)): the moved gitlink and the
recomposed root index land in a canned bookkeeping commit
(`Update MEMORY.md for <tier> tier merge.`) that advances memory's local
`live`, so an explicit take leaves the store clean. The parent-level gitlink
still floats to the next parent commit, as every memory advance leaves it. One
path degrades: a root store that held unapproved work *before* the take gets
no canned commit — the pair includes `MEMORY.md`, whose recompose folds in
whatever unapproved index edits the episode already held — and falls back to
the staged-pair discipline below.

**On the degraded path, the moved gitlink is staged.** `submodule update`
checks a tier out at the sha the superproject's **index** holds, not the one
its HEAD records, so the pin and a floating gitlink are only compatible while
the move is in the index. Every advancing path therefore stages the pair —
`MEMORY.md` and the tier — before its bookkeeping commit, and keeps the staged
pair when that commit is refused: the fast-forward-plus-adoption branch of
`gitlore_merge_stores`, and the merge continuation, which stages *after* its
merge commit because that commit does not exist before it. The **mount** is a
third such path and stages the gitlink alone: `submodule add` records the
remote's default branch and `/gitlore:add-tier` then detaches the tier at
`live`, so the gitlink moves while the root index it feeds is written by the
compose that follows and floats as ordinary dirt. Left in the working tree
alone, the move survives exactly until the next `SessionStart`, which walks
the tier back to the pre-merge commit while the recomposed root index — an
ordinary file write, not a gitlink — survives to describe facts the carrier no
longer holds. Nothing reports it: the command that landed the merge exited 0,
and the session that reverted it calls the tier clean. Staging is what makes
the pin idempotent instead of destructive.

**D44 — Shared-tier conflicts resolve semantically; memory merges as prose,
indexes entry-wise**

Two repos inserting into a tier's `MEMORY.md` concurrently are resolved the same
way as any memory divergence — the semantic memory-merger sub-agent, which
merges both insertions without duplicating them. A `merge=union` driver is
deliberately *not* used: it concatenates blindly and would leave duplicate
pointer lines needing a cleanup pass. And because each index occupies a distinct
filename namespace — the root holds bare project paths, each tier carrier only
that tier's filenames — composed blocks never share a path across indexes
either. So no duplicate-pointer residue arises on any path and no dedup pass is
needed. No append-only constraint is imposed; conflicts are expected rare (the
more global a tier, the more stable it presumably is).

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
collapsed, leaving the malformed index for `gitlore_compose_check` to report.
Because the pass resolves an index in the worktree without staging it,
`conflicted_files` in the state file is the union of git's unmerged entries and
`gitlore_conflicted_indexes`. Its chunks carry **git's own labels** — `HEAD` for
the authoritative side (checked out detached by the prepare) and the incoming
commit's sha — rather than a vocabulary of gitlore's own, so one merge never
presents the sub-agent with two namings of the same two sides. That is one
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
files, still runs `git add -A`, and still stops for approval.

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
