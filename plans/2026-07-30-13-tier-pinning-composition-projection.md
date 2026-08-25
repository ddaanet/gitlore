# Tiers are pinned at the gitlink; advancing one is a merge

## The model

A memory commit records `MEMORY.md` and the tier gitlink together, so root's
tier block and the tier's carrier index are consistent by construction. Keep
them that way:
**a tier is checked out at its recorded gitlink and never fast-forwarded.**

`SessionStart` ff's the memory root and checks tiers out from their gitlinks.
Nothing advances a tier silently. When a tier's remote is ahead the user has two
ways to take it — `/gitlore:push` (reconcile and publish) or `/gitlore:merge`
(reconcile only) — and both go through the merge resolution that exists.

Today `scripts/cc-hooks/session-start.sh:207` fetches `live:live` and `:241`
checks out `--detach live` unconditionally, so a tier routinely outruns the
gitlink root's index agrees with. When root's index also moved, both artifacts
have left a common base and nothing merges them: composition applies its
precedence rule (`scripts/lib/index-compose.sh:386-390`) and reverts upstream,
while the resolver reports `state is healthy` because the tier and its remote
agree. It also leaves `memory/` dirty — a moved gitlink is ` M <tier>` to
`git status`, which `gitlore_memory_dirty` (`scripts/lib/util.sh:215`) reads —
so the next session skips root's own `merge --ff-only live` at
`session-start.sh:165`. A tier ff suppresses root's ff.

Observed 2026-07-29 in the `/gitlore:push` dogfood: a local index compaction and
an upstream `grep -qF` trigger addition had both moved the same line. The merge
sub-agent resolved it correctly in the tier; the continuation's compose then
replaced the result with root's text. A *new* upstream fact reached root in the
same pass, because a path root lacks takes the carrier's line (`:389`).

## Where the three-way belongs

**In the merge, and it stays there.** `_gitlore_index_merge_bullets`
(`scripts/lib/index-merge.sh:61-90`) keys entries on the pointer path, takes
presence by set difference against base (`:66-73`), runs the text three-way per
entry — identical sides, then each side against base — and emits diff3 markers
only for an entry both sides moved apart (`:77-87`). Preamble and trailer merge
as prose through `git merge-file --diff3`.

**Not in composition.** `gitlore_compose_tier_bullets` carries the same
path-keyed presence rule at `:378-384`, but the base read at `:365-374` keeps
only paths and discards the text — `base.bullets` is created empty at `:334-337`
and never filled — so there is no per-entry diff3 left to run and `:386-390`
takes root's text unconditionally. It is the merge's skeleton with the text
comparison removed, and with tiers pinned root and carrier cannot diverge
outside a merge, so it has nothing to merge. Two projections replace it:

- **Down** — in-session, run by `PostToolBatch` and `SessionStart`. Project
  root's ACTIVE tier lines into each carrier, de-prefixed. A dormant tier is
  untouched: root does not represent it, so root has no authority over its
  carrier.
- **Root layout** — same pass. Hoist each active tier's block above the project
  lines in manifest order and drop inactive-tier lines. A reorder, so
  `gitlore_compose_and_report:477` stays true: the in-session pass still never
  changes a line's text.
- **Up** — project the adopted carrier into root's tier block, once, at the
  tier-adoption step inside the merge command.

One disambiguation the down projection needs, because "root lacks this path" is
otherwise ambiguous. For a path the carrier has and the working root does not,
look at root at `HEAD`:

- present there → root deleted it → drop it from the carrier, which is the
  contract `tests/index_compose.bats:354` and `:391` assert;
- absent there → nobody authored it in root, so it is a dormant-tier line or a
  direct carrier write → keep it, and name it in the report.

One lookup against a commit git already holds. `refs/gitlore/compose-base` goes
with the merge it served.

## Steps

**1. Composition becomes two projections.** Add `gitlore_compose_down` and
`gitlore_compose_up`; delete `gitlore_compose_tier_bullets`,
`gitlore_compose_save_base` (`:568-598`) and the ref read at `:365-374`. Keep
`gitlore_order_merge` — `index-merge.sh` uses it, and root's layout pass still
merges order. Drop the audit-chain cases at `tests/index_compose.bats:588-731`
and the `up`-mode assertion at `tests/resolve_compose.bats:84`.

The `git -C "$mempath/$tier"` at `:365-373` lacked the
`[ -e "$mempath/$tier/.git" ]` guard the `save_base` loop has at `:674`;
deleting both removes the exposure.

Tests, each turned red by mutation:
- root and carrier hold different text for one path; the adoption puts the
  **carrier's** text in root. Uncovered today.
- a root-authored tier line reaches the carrier, and removing it from root drops
  the carrier copy (`:316`, `:354`, `:391` must stay green).
- a dormant tier's carrier survives two consecutive passes. This is the
  pre-existing drop: mirror-down iterates `$mounted` while splice-up iterates
  `$active`, so `save_base` records a carrier holding the dormant paths against
  a root splice-up already stripped them from, and the next pass reads
  `b=1, o=0, t=1` and deletes them — against the contract at `:429-431`.
  Reproduce by appending a second `gitlore_compose memory` to
  `tests/index_compose.bats:444`.
- a carrier-only path with no counterpart in root at `HEAD` is kept and
  reported.
- idempotence: compose twice, the second writes nothing.

**2. The merge command adopts the tier.** The adoption step does not exist
today. `continue-after-merge` commits in the merged store and ff's its `live`
(`scripts/resolve.sh:157-183`); it never records the new gitlink in the memory
store — that rides the parent's pre-commit lockstep, by design — and
`compose_merged_indexes` (`:93-115`) runs a generic whole-tree `compose … up`,
then `git add -A` in the *tier*, so root's index write is not even staged.
Replace that with a per-adopted-tier up projection, staged in the memory store.
A memory-store merge needs no up pass at all: root's `MEMORY.md` is one of the
files git merged, so the propagation is already in the merged content.

**3. `SessionStart` pins tiers.** Drop the `live:live` fetch and the
`checkout --detach live`, and run `submodule update` unconditionally rather than
only when `.git` is absent (`:189`) — existing clones already sit ahead of their
gitlink, so removing two lines pins nothing by itself. Keep fetching
`origin live` read-only (it moves no local ref) so a tier whose remote is ahead
can be named: one `systemMessage` saying upstream facts are waiting and that
`/gitlore:push` or `/gitlore:merge` takes them. The unfinished-merge arm at
`:229-239` stays. `scripts/add-tier.sh:214,226` mounts a tier for the first
time, where there is no gitlink yet — leave it.

**4. `/gitlore:merge`.** Same gates, state file, memory-merger sub-agent and
adoption step as push; it stops after the local `HEAD:live` ff and skips
`push origin live` (`scripts/resolve.sh:176-182`). `/gitlore:resolve` stays the
hook-triggered repair path.

Record in `docs/design.md`: tiers pinned at the gitlink, advancing one is a
merge, the three-way belongs to the merge and composition is two projections,
and the `HEAD` lookup that disambiguates a deletion. Then update
`memory/ddaanet/reference_gitlore_tier_merge_direction.md`, whose manual
up-application steps 2 and 3 replace, in the same parent commit.
