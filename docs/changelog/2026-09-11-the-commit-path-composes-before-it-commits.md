# 2026-09-11 — The commit path composes before it commits (D50, D51)

`gitlore_compose` had three callers — `session-start.sh`, the `PostToolBatch`
hook and `add-tier-batch.sh` — and the commit path was not among them. A carrier
left stale by a missed in-session compose self-heals at the next `SessionStart`,
but it **ships** if a memory commit lands first, because the carrier is what a
tier's remote serves. The tier's consumers then read text the root index no
longer holds, and nothing on the publishing side ever notices.

`gitlore_sync_memory_to_live` in `scripts/lib/resolve.sh` now composes, and that
one function is the shared body behind both commit entry points — the
`pre-commit` hook and `commit-memory.sh` — so the sequence is
`dirty/freshness gate → pin guard → compose → add -A → …` wherever a memory
commit starts. The placement ahead of `gitlore_sync_tiers_to_live` is
load-bearing: composition writes carrier files *inside* the tiers, so it has to
land before the tier commits move their gitlinks, or the gitlink pins the
pre-compose content — the one-behind lag the existing tier-first ordering
already exists to prevent.

Dirty stores only. Composing a clean store can *create* a dirty state the user
never approved a summary for, and the FR11 gate would then refuse the commit for
a change the agent did not make. What keeps that boundary intact in the dirty
case is that a carrier is a projection of root index lines the approved summary
already covered, never new content. A store whose committed carrier already
diverges from its committed root index is left to `SessionStart`, whose compose
rides the next commit that does have a summary.

The two refusals are not interchangeable. A compose refusal (rc 1) writes
nothing — projecting root's older text over an unadopted carrier is exactly what
D31 and D36 exist to stop — so the commit proceeds with the indexes as they
stand and the refusal is only reported. A **pin** refusal aborts, and is checked
by `gitlore_compose_check_pins` ahead of the compose rather than reached through
its rc-1 arm: leaving it to compose would let the commit's own `add -A` stage
the moved gitlink anyway, adopting the move silently in the very commit that
reported it as a problem, and the next compose would then overwrite the approved
upstream fact with root's older text. The abort names no remedy of its own,
because every branch of the check already printed the one its cause takes. A
write failure (rc 2) aborts too — a half-written carrier must not be committed —
and restamps the commit-msg file, since what the pass did write is now newer
than the approval and would read as stale on the retry. The pin abort writes
nothing, so it restamps nothing.

The baselines the `PostToolBatch` hooks keep are now keyed per agent as well as
per batch. `gitlore_index_preimage_file`, `gitlore_compose_stamp_file` and the
new `gitlore_relay_marker_file` each take an agent id and append
`_gitlore_agent_suffix`'s sanitized `-<agent_id>`; an absent or empty id yields
the unsuffixed name, so the main thread's files are unchanged and nothing
migrates. The race that keying closes: `index-sync-pre.sh` skips re-baselining
when a file is already present and every consumer `rm -f`s unconditionally, so a
parent batch ending between a subagent's pre-hook and its post-hook consumed the
subagent's baseline and stranded that edit silently. Every hook reads `agent_id`
specifically and never `agent_type`, which also appears on the main thread of an
`--agent` session. One residual is bounded rather than swept: a pair stranded by
an interrupted batch is consumed and deleted by the next batch of that same
agent id, and one left behind by a subagent that died is consumed by nothing —
an agent id is not reused, so the leftovers are one pair per dead subagent
rather than unbounded growth.

Keying is what made the subagent relay possible. A hook firing inside a subagent
has both `systemMessage` and `additionalContext` confined to that subagent's own
transcript (D51, measured under CC 2.1.261), so a subagent's edit to the root
index triggered a composition whose report reached neither the parent's context
nor the user — the parent's only view was whatever the subagent chose to
narrate. A keyed run now stages its report in `gitlore-relay-<agent_id>`, a
sixth untracked `gitlore-…` file in the memory gitdir, and the next unkeyed
parent-side run folds every marker in — each block framed with the agent id its
filename carries — and removes them. `session-start.sh` drains the same way, so
a marker that outlives its session is not lost. The write merges into an
existing marker rather than truncating it, because both `PostToolBatch` hooks
can stage to one key within a single batch. The relay is
**in addition to, not instead of**, the subagent's own emission: the subagent is
the actor, and a blind agent goes looking rather than waiting.
