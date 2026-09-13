# Deliverable review — code partition (Layer 1)

Plan: `index-edit-propagation`. Range `b6dbe92..HEAD`, excluding 3d50a1f,
c2e7950, ae54c1b; 8523b47 included. Baseline: `outline.md` §B–D and `runbook.md`
FR-B, FR-F, FR-C, FR-D (Phases 1–3, amendments taking precedence). The review
was read-only. No suite was run. Two scratch probes ran under
`/tmp/claude-1000/dr-code-*`.

**Counts: Critical 0 · Major 5 · Minor 4**

## What checks out

- **`agent_id`, never `agent_type`.** All four consumers read
  `.agent_id // empty`: `index-sync-pre.sh`, `index-sync-post.sh`,
  `index-compose.sh` and `add-tier-batch.sh`. The keyed name is what
  `add-tier-batch.sh` drops. The falsified pre-hook comment is rewritten, and
  the residual is bounded in a comment (FR-C).
- **Id sanitisation.** `_gitlore_agent_suffix` uses `LC_ALL=C tr -c` into
  `[A-Za-z0-9-]`, so `--git-path` cannot leave the gitdir.
- **Portability.** Nothing in the change needs GNU tools or bash 4. It uses
  `find -maxdepth … '!' -name … -print0` into `read -r -d ''`, `LC_ALL=C sort`
  without `-z`, `${head:0:12}` and `$'\n'`.
- **Whitespace.** The drain enumerates markers whitespace-safely, and the
  delimiter parse runs per file.
- **Channel discipline.**
  - The commit path reports through `gitlore_say_for_agent_or_user … >&2`.
  - `gitlore_compose` and `gitlore_compose_check_pins` output is captured, not
    leaked to git's stdout.
  - `gitlore_adopt_recovered_merge` writes only to stderr.
  - The PostToolBatch hooks still emit one `jq -n` object.
- **Commit-path order** matches the runbook as amended:
  1. freshness check;
  2. per-tier stale-merge loop;
  3. pin guard (abort, no restamp);
  4. `gitlore_compose`, where rc 1 reports and proceeds, and rc 2 and `*` abort
     with `touch "$msgfile"`;
  5. `gitlore_sync_tiers_to_live`;
  6. `add -A`.
- **Squatted marker directory.** The `[ -d "$marker" ]` refusal before `mv` is
  there, so POSIX `mv`-into-directory is covered. The `.tmp` exclusion is safe,
  because a sanitised id can never contain `.`.
- **Citations.** No added line cites `plans/`, `memory/`, runbook or slice ids,
  or `file:line`. D50, D51 and D43 all resolve in `docs/`.

## Major

### M1 — `scripts/lib/index-sync.sh:155-217`: the relay write's merge is an unserialised read-modify-write on a shared temp name, and the PostToolBatch hooks run in parallel

- **Axes:** concurrency / functional correctness. **Severity:** Major.

`hooks/hooks.json` puts `index-sync-post.sh` and `index-compose.sh` on the same
`PostToolBatch` event. Claude Code runs all matching hooks **in parallel**; the
vendored `plugin-dev:hook-development` skill says so under "Parallel Execution"
and lists "Assuming Hook Order" as a pitfall.

`gitlore_relay_write` has three steps:

1. test `[ -f "$marker" ]`;
2. read both channels;
3. write the fixed path `"$marker.tmp"`, then `mv` it into place.

Nothing serialises two writers for the same agent id, so two failures follow:

- **Lost update, silent.** Both writers see no marker, and both `mv`
  successfully. The second rename replaces the first writer's report, and both
  return 0.
- **Shared temp.** Both writers open the same `$marker.tmp`. The first `mv`
  takes the inode away, so the second `mv` fails with `cannot stat …tmp`.
  - The second hook tells its subagent that the report could not be staged.
  - The parent gets only one of the two reports.
  - The bytes the second writer was still writing may be spliced into the
    installed marker.

Slice 2.5 exists to stop exactly this ordinary case: one subagent batch that
edits `MEMORY.md` with a tier mounted. The fix holds only if the hooks run one
after the other.

**Probe** (`/tmp/claude-1000/dr-code-relay-race.sh`: two concurrent
`gitlore_relay_write mem a1 …`, then one drain, with the gitdir path holding a
space):

| Start timing | Iterations missing one report | Signalled as a write failure | Silent loss |
|---|---|---|---|
| Simultaneous | 165 / 300 | 163 | 2 |
| Second writer delayed 0–49 ms at random | 6 / 300 | all | — |

**Stale comment.** The drain comment at `:299-301` says hooks "within one
session are sequential". That is false for same-event hooks, and it is the
premise the design leans on.

**Failure scenario.** A subagent re-texts a root index line in a store with a
tier mounted. Both hooks finish within a few milliseconds of each other. The
parent receives the `recomposed tier pointers` block but not
`reset frontmatter to match MEMORY.md`. In the silent interleaving, nobody
learns that report existed.

**Fix direction.**
- Take a per-agent `mkdir` lock (atomic on BSD and GNU) around read, merge and
  `mv`.
- Use a per-writer temp (`"$marker.tmp.$$"`). The drain's `'!' -name '*.tmp'`
  would then need to become `'*.tmp*'`.

### M2 — `scripts/lib/index-sync.sh:280-308`: the drain reads, then removes, with no atomic claim, so it loses a write that lands in between and can unlink an in-flight temp

- **Axes:** concurrency / atomicity. **Severity:** Major.

The drain runs `_gitlore_relay_sysblock "$marker"`, then
`_gitlore_relay_ctxblock "$marker"` (two separate `awk` opens), then
`rm -f "$marker"`, then `rm -f "$marker.tmp"`.

Parent-side and subagent-side hooks do run concurrently. The outline's own §C
evidence is a subagent pre-hook and a parent pre-hook 243 ms apart, and a
background subagent keeps running while the parent takes batches. So a
subagent's `gitlore_relay_write` can `mv` a merged marker into place between the
drain's reads and its `rm`:

- **Before both reads:** the drain folds the old content and deletes the new
  file. That subagent's latest report is lost, and its write returned 0, so
  nobody is told.
- **Between the two reads:** the parent's sysmsg carries the old body and its
  ctx carries old plus new. The user never sees the new body.

The `rm -f "$marker.tmp"` at `:308` can also unlink the temp a concurrent writer
for the same agent is still filling. That writer's `mv` then fails. This one is
at least signalled to the subagent, but the report is lost for the parent.

The comment at `:295-307` justifies the scoped removal as safe against another
session's in-flight temp. It does not consider the same agent writing again
while the parent drains, which is the concurrency C and D exist for.

**Failure scenario.** A background subagent edits the index twice in quick
succession while the parent's own index-editing batch ends. The parent's drain
reads marker v1, the subagent installs v2 (v1 plus its second report), and the
drain removes v2. The second report reaches no one.

**Fix direction.** Claim before reading: `mv "$marker" "$marker.drain.$$"`, a
rename that can lose nothing. Then read and remove the claimed file. Drop the
`.tmp` removal, or do it only under M1's lock.

### M3 — `scripts/cc-hooks/index-compose.sh:46,64` and `scripts/cc-hooks/index-sync-post.sh:40,42`: the parent-side drain sits behind the hooks' own no-change exits, so the common foreground-subagent report does not reach the parent session

- **Axes:** functional completeness / conformance (FR-D). **Severity:** Major.

The unkeyed drain (`index-compose.sh:100`, `index-sync-post.sh:284`) is reached
only after the parent's own batch left a stamp or pre-image **and** changed the
index. `index-sync-pre.sh` is registered on `Write|Edit|Bash` only, so the
parent batch that issued the `Agent`/`Task` call has no baseline and exits
before the fold. That batch is the natural moment for a relay to land.

In the ordinary flow the report waits for one of two things:

- a later parent batch that edits the root index itself, which may never happen;
  or
- the next `SessionStart`. That is startup, resume, clear or compact — a later
  session or a context reset, not the parent session that dispatched the
  subagent.

FR-D reads "reports produced inside a subagent reach the parent session". The
runbook notes this (slice 2: "a marker is not necessarily drained by the very
next parent-side batch; slice 3 is the backstop"). But that backstop fires in a
different session, so the requirement is unmet for the case the outline was
written about: a subagent composes and the parent never learns of it.

**Failure scenario.** The parent dispatches a subagent. The subagent edits
`memory/MEMORY.md`, which composes and re-texts a carrier. The subagent returns,
and the parent carries on with code edits and commits. No relayed report appears
in the parent session. It surfaces in whatever session next fires SessionStart,
attributed to an agent id that session never saw.

**Fix direction.** In both hooks, drain unkeyed runs before the stamp/stash
early exits (or in one of them, to avoid double folding). The cost is one
`rev-parse --absolute-git-dir` plus one `find` per parent batch.

### M4 — `scripts/lib/resolve.sh:1000-1021` with `:1091-1100`: the pin guard permanently refuses a retry after gitlore's own partial commit, with no correct gitlore remedy

- **Axes:** functional correctness / robustness (a regression FR-F introduced).
  **Severity:** Major.

`gitlore_sync_tiers_to_live` commits inside each dirty tier, which moves the
tier's HEAD. Only the later `gitlore_git -C "$mempath" add -A` stages that move
into memory's index. Anything that stops the run between the two leaves the tier
HEAD ahead of the pin its memory index records, with the approved `$msgfile`
kept:

- a failed tier `live` advance that is not a divergence (`:907-913`);
- a second tier's commit failing after the first landed;
- `add -A` or the memory `commit` failing after the retries run out on an
  `index.lock`;
- Ctrl-C or OOM during the hook.

Before Item 1.2, the retry's `add -A` adopted the move and the commit completed.
Now the pin guard runs first and aborts with `gitlore_compose_check_pins`' new
ahead-of-pin line, "There is no automatic remedy: inspect and stage the gitlink
by hand, or return the tier to the pin, which discards the commits it carries
ahead of it".

- The only option that moves anything is the destructive one: it discards the
  user-approved tier commit.
- The by-hand option is correct here, but only by luck (see M5).
- Every later commit in the session aborts the same way.
- The next SessionStart re-pins the tier, which walks the committed facts out of
  its worktree.

**Failure scenario.** A memory commit writes tier `ddaanet` and commits it. The
memory `add -A` then hits an `index.lock` that an IDE's `git status` holds past
the ~10 s retry schedule, and the hook returns 1. The agent retries. It gets "a
tier was moved off the commit the memory store records for it … ahead of the
pin" and follows the remedy to return the tier to its pin, so the approved fact
edit is gone from the tier.

**Fix direction.** The guard cannot tell "gitlore committed this tier in this
episode" from "the tier moved behind root's back". The options:

- stage each tier's gitlink immediately after its commit inside
  `gitlore_sync_tiers_to_live` (D43's last-act rule, one level down); or
- have the guard accept a tier whose commits ahead of the pin carry the gitlore
  commit sentinel or message.

### M5 — `scripts/lib/index-compose.sh:349`: the ahead-of-pin remedy "stage the gitlink by hand" is the silent overwrite the guard exists to stop

- **Axes:** functional correctness / error signalling (NFR2). **Severity:**
  Major.

`scripts/lib/resolve.sh:279-291` states the invariant: staging a tier that is
ahead of its pin, without first composing up, "turns [the refusal] into a silent
overwrite". The next down compose writes root's older text over the carrier. The
only safe adoption is compose-up, then stage the pair.

The new ahead-of-pin message offers the unsafe half as its first remedy, gives
no command, and says nothing about composing up. `gitlore_adopt_recovered_merge`
leans on this same message: its compose-up failure branch (`resolve.sh:330`)
says "the next gate refuses the tier instead", and that refusal is this line.

**Failure scenario.**
1. A landed tier merge re-texts a line root also holds, and root's index cannot
   take it: `gitlore_compose_up` returns 1, so the recovery leaves the gitlink
   unstaged.
2. The next commit aborts with the ahead-of-pin line.
3. The agent does as told: `git -C memory add ddaanet`, then retries.
4. The pin guard passes. `gitlore_compose` projects root's older text over the
   carrier. `gitlore_sync_tiers_to_live` commits that inside the tier, and
   `pre-push` publishes it. The upstream fact is destroyed without a refusal.

Item 1.3's own slice-1 code review measured this destruction for staging alone.

**Fix direction.** Name the safe adoption, or say explicitly that staging alone
overwrites the tier's text at the next compose. A remedy that must not be
followed as written is worse than none.

## Minor

### m1 — `scripts/lib/resolve.sh:990, 996-997, 1027, 1091-1100`: the approval is left stale on failure paths after the tree was written, and the "No restamp" comment is falsified

- **Axes:** robustness / stale comment. **Severity:** Minor.

The `touch "$msgfile"` restamp covers only the rc-2 and `*` arms. Three other
paths write under `$mempath` after the freshness check and then return 1 without
restamping:

- **Per-tier guard loop (`:990`).** It runs `gitlore_recover_landed_merge`,
  whose `checkout --detach` and `gitlore_compose_up` write tier and root files.
  If the pin guard then aborts, the approval is stale. Two cases reach this:
  compose-up failed by design (so the tier stays unstaged), or another tier is
  off its pin.
- **Successful compose (`:1027`).** If `gitlore_sync_tiers_to_live`, `add -A` or
  `commit` then fails, the carrier it wrote is newer than the approval.

In each case the retry is refused as stale and asks for a new approval covering
nothing new, though the abort text says "the approved summary is still in
place".

The comment at `:996-997` ("this writes nothing, so the tree is no newer than
$msgfile") was true of the guard itself. It stopped being true of the run once
Item 1.3 put writes in the loop just above it.

**Scenario.** Tier A holds a stale-no-merge-head landed merge that the root
index cannot take, and tier B is off its pin. The commit recovers A (checkout
writes), then aborts on B. After B is fixed, the retry demands re-approval.

### m2 — `scripts/lib/resolve.sh:318-343`: the recovered-merge adoption composes up even when the memory index already records the tier's HEAD

- **Axes:** functional correctness / idempotency. **Severity:** Minor, because
  the window is narrow.

`gitlore_adopt_recovered_merge` has no `":$rel" == HEAD` short-circuit.

A continuation can be killed after it staged the gitlink and made the
bookkeeping commit (`scripts/resolve.sh:227-232`) but before
`gitlore_clear_merge_state`. That leaves a stale-no-merge-head store whose merge
is already adopted and pinned. The next gate's recovery takes the "HEAD already
carries the merge" branch and still runs `gitlore_compose_up`. That replaces
root's whole block for the tier with the carrier's text, reverting any
root-index edit made to that tier's lines since.

On the commit path this runs inside the per-tier loop, after the freshness
check. The reverted edit is therefore the approved one the commit is about to
record, and the only trace is a composed-lines echo on stderr.

**Fix direction.** Return early when
`git -C "$super" rev-parse -q --verify ":$rel"` equals the store's HEAD.

### m3 — `scripts/lib/resolve.sh:341`: the printed staging command is not verbatim-runnable on a spaced path

- **Axes:** whitespace safety. **Severity:** Minor.

``Run `git -C %s add -- MEMORY.md %s` `` interpolates `$super` and `$rel`
unquoted. With a project at `/Users/x/my project`, the pasted command runs
`git -C /Users/x/my project/memory add …`, which fails. The message it belongs
to exists to prevent a silent pointer reset.

This copies the precedent at `:1687`, which has the same defect. The
neighbouring `gitlore_recover_*` messages quote `\"$abs\"`.

### m4 — `scripts/lib/index-sync.sh:236` and `scripts/cc-hooks/session-start.sh:398`: markers are keyed by agent only, so any session's parent-side run or SessionStart drains another live session's reports

- **Axes:** concurrency / functional correctness. **Severity:** Minor.

The drain enumerates every `gitlore-relay-*` in the shared memory gitdir.
Consider two Claude Code sessions in the same checkout, or a `/compact` or
resume while a background subagent is live. Either session's unkeyed
PostToolBatch run or SessionStart folds and removes the other's subagent
markers. The report goes to the wrong conversation, framed with an agent id it
never dispatched, and the right one never gets it.

The design already keys nudge markers by `session_id`, and a relay marker could
carry the same field.
