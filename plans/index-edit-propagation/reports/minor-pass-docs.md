# Minor documentation pass

Nine items, each verified against the named source (`scripts/lib/resolve.sh`,
`scripts/cc-hooks/session-start.sh`, `scripts/git-hooks/pre-commit`) before
editing.

## Item 1 — docs/references/git-hooks.md

Steps 3 and 4 merged into one step 3, and the old step 5 renumbered to 4:

> 3. **Sync memory** through the shared `gitlore_sync_memory_to_live`: memory's
> own stale-merge guard, the FR11 dirty/freshness gate, each mounted tier's
> stale-merge guard, `gitlore_stage_landed_tiers` (adopting a tier a previous
> run committed inside but never recorded — the retry of a half-landed commit,
> D50), the pin guard (`gitlore_compose_check_pins`, aborting on an off-pin
> tier), down composition (`gitlore_compose`; rc 1 reports and continues, rc 2
> aborts), `gitlore_sync_tiers_to_live` (each dirty tier: `add -A`, write its
> landing record, commit, advance its local `live`, so the gitlink the memory
> commit is about to record has already moved (D42), onto composed carrier
> content (D50)), memory's own `add -A`, removing the landing records,
> `GITLORE_MEMORY_COMMIT=1 commit -F <msgfile>`, and removing the message file,
> then `push . HEAD:live` fast-forward-only. Divergence prepares a merge and
> yields (`gitlore_yield_merge`), exiting 1.
> 4. **Stage the gitlink** into the index git handed the hook — …

Verified the order against `gitlore_sync_memory_to_live`
(scripts/lib/resolve.sh:959) and its caller `scripts/git-hooks/pre-commit`.

## Item 2 — docs/changelog/2026-09-11-…-composes-before-it-commits.md

(a) `dirty/freshness gate → pin guard → compose → tier commits → add -A → …` (b)
"…stages its report in `gitlore-relay-<agent_id>`, another untracked `gitlore-…`
file in the memory gitdir, and the next unkeyed…"

## Item 3 — docs/decisions.md

(a) D50: "the commit path composes a dirty store before it commits; a pin
refusal aborts, a compose refusal only reports" (b) D50 *Rejected:* "… · staging
each tier gitlink right after its commit · composing a clean store · reporting a
non-empty commit-path compose." (c) D51 *Rejected:* "… · folding another
session's stranded reports at `SessionStart` · relaying in place of the
subagent's own emission."

## Item 4 — docs/references/cc-platform.md

"…the parent transcript carries zero `hook_*` attachments while the subagent's
own JSONL carries all four hook attachment kinds — `hook_system_message`,
`hook_additional_context`, `hook_success` and `hook_non_blocking_error` —, and
the control run with no subagent surfaces both channels normally."

## Item 5 — docs/references/session.md

Step 6: "A refused fast-forward that classifies as divergence reports it and
routes to `/gitlore:resolve`; any other refusal reports git's own words instead,
since a lock, a corrupt object or an unwritable worktree refuse `--ff-only` too
and routing them to resolve would be a guess. Both arms end the pass there."
Verified against `scripts/cc-hooks/session-start.sh:197-213`. Step 10 left
unchanged.

## Item 6 — docs/references/merge-state-recovery.md

"**A landed tier merge is adopted, not only cleared.** Whether HEAD already
carries the merge or is put back onto it, the enclosing store's index still
names the commit the tier sat on before it, so `gitlore_adopt_recovered_merge`
composes… (D50, [git-hooks.md](git-hooks.md)). When the enclosing index already
records the tier's HEAD, the adoption is a no-op, so a re-run after a completed
bookkeeping commit does not project the carrier over root-index edits made
since. A failed up projection therefore stages nothing…" Verified both call
sites in `gitlore_recover_landed_merge` (scripts/lib/resolve.sh:234-271) call
`gitlore_adopt_recovered_merge`. The no-op short-circuit clause is written as
current truth per the dispatch note (parallel implementation).

## Item 7 — docs/design.md

"…the `PreToolUse`/`PostToolBatch` index pair keys on what changed rather than
on what the call declared (D31), per agent so a parent batch cannot consume a
subagent's baseline, a `PostToolBatch` relay drainer is the one…"

## Item 8 — CLAUDE.md

"…across turns in the main session; the completion notification carries the
verdict." — the `plans/index-edit-propagation/background-run-timeout-probe.md`
parenthetical is deleted. Nothing else in CLAUDE.md touched.

## Item 9 — plans/index-edit-propagation/runbook.md

(a) Appended to the end of Item 3.1 slice 4's bullet list, its own paragraph:
"**As executed, the last case above did not survive slice 5**, which retired it
for `an unkeyed run leaves a non-marker alone`; see that slice."

(b) Appended after Item 1.2's three-bullet remedy list (after the user-remedy
bullet, before "Two of Item 1.1's cases induce rc 1…"):
"**As executed, the agent remedy is**
`gitlore: composing would have overwritten what that tier holds, and committing would have adopted the move silently. Follow the remedy on each line above, then retry the commit — the approved summary is still in place.`
— generic rather than the fixed sentence above, because each
`gitlore_compose_check_pins` branch already prints the remedy its own cause
takes and one abort can carry several causes, so no single named remedy fits all
of them." Verified against scripts/lib/resolve.sh:1046-1052.

## check-docs-links.py

`cd /Users/david/code/gitlore && python3 scripts/check-docs-links.py` — exit 0,
all nine counters (broken-link, unstubbed-decision, stub-without-body,
duplicate-decision, duplicate-conclusion, undefined-decision, enumeration-drift,
delegation-drift, oversized-file) at zero.

## Deviations

None. All nine items applied as specified; no discrepancy found between the
task's description of the code and the code itself.
