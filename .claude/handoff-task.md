## Current task

The memory merge and in-session index trigger rework is finished and green
(`just precommit`, 505 cases). One thread stays open: the `Bash` arm of the
`PreToolUse` trigger is proven only by the bats suite. `hooks.json` event
registration freezes at session start, so the widened `Write|Edit|Bash` matcher
cannot take effect until a restart — dogfood a `sed -i` on the real
`memory/MEMORY.md` in a fresh session and confirm both propagation and
composition run. The stamp protocol itself already dogfooded here: retiring
`reference_gitlore_bash_edit_desync.md` went through the new `index-compose.sh`
and mirrored the deletion down into the tier correctly.

## Open decisions

- Ordering inside a merged bullet block is ours-order-then-theirs-only-appended,
  matching `gitlore_compose_tier_bullets`. No insertion-point arithmetic. Fine
  for the root (composition reorders tier blocks straight after) and for a
  carrier (incoming facts land at the end) — but it is a choice, not a law.
- `add-tier-batch.sh` drops the compose stamp assuming `PostToolBatch` hooks run
  in the order `hooks.json` lists them. Noise-suppression only; if the
  assumption is wrong the cost is one redundant idempotent compose.
- The pre-hook now runs on **every** Bash call (cd to project root, two git
  queries, a `cp` of the index, a `cksum`). Cheap, but new per-call cost on the
  hottest tool, and nothing measures it.
- Whether the `agents`/`commands`/`skills` exclusion from `precommit_inputs`
  should stand. This change edited `agents/` and `skills/`, so precommit went
  green without re-running the distribution guard.
