# Task — 2026-09-10 00:01:09 

## Current task

Orchestrating `plans/index-edit-propagation/runbook.md` with the edify
orchestrate skill. Phases 1-3, Item 1.2 and Item 4.0 are behind. Item 1.3 was
added at the Phase 4 checkpoint; its slice 1 landed as `e04cb19`.

Phase 4 remainder: Item 1.3 slice 2, then Items 4.1 + 4.2 in **one commit** (a
decision argued in a node with no conclusion in the decisions index is what
`scripts/check-docs-links.py` blocks on as `unstubbed-decision`, so the gate
must not run between them), then 4.3. Next free decision id is D50; re-derive
rather than trust that, with `grep -oh 'D[0-9]\+' docs/decisions.md
docs/references/*.md | sort -u -t D -k2 -n | tail -1`.

**Item 1.3 slice 2**, specified in the runbook: `gitlore_compose_check_pins`
(`scripts/lib/index-compose.sh:310`) gains a third branch, between the
mid-merge test and the existing one, on `merge-base --is-ancestor "$pinned"
"$head"`. A tier ahead of its pin is still refused, but worded as
ahead-of-the-pin and without the `checkout --detach <pinned>` remedy, which
discards the commits it carries. Slice 1 narrowed its scope: the cause is now
fixed, so slice 2 covers only tiers advanced outside gitlore. Branch order is
load-bearing — mid-merge first, so a tier that is both keeps `/gitlore:resolve`.

**What D50 gained from slice 1 and must carry:** the up-before-stage invariant.
Staging a moved gitlink without projecting the carrier up first *inverts* the
pin guard — the index then agrees with HEAD, composition proceeds, and the down
projection writes root's older text over the merged-in facts. Measured against
the staging-only implementation: exit 0, carrier overwritten, and the only
message printed was the recovery's own "none of that merge is lost". Also for
D50: the guard now writes and stages from push/merge/session gates too, not
just the commit path, and leaves the pair staged rather than committing its own
bookkeeping (D43's degraded case) — both deliberate, neither yet in the record.

**The dispatch shape that works, and should continue:** RED (sonnet
test-driver) → test review (opus corrector) → GREEN (sonnet test-driver) → code
review (opus corrector). The orchestrator alone runs the gate and makes every
commit, and every subagent prompt says so and gives the reason — a subagent does
not reliably receive the background-task completion notification. A born-green
slice collapses to RED plus test review. The reviews earn their cost by mutating
the SUT and measuring which wrong implementations still ship green; that round,
never the pass/fail count, found every real defect in Phase 3, Item 1.2 and
Item 1.3.

**Three of my own spec errors were caught this session, each by measurement
rather than argument**, and all three by subagents pushing back:
`--show-superproject-working-tree` does not distinguish the memory root (it is
itself a real submodule of the parent repo); `gitlore_tier_paths` does not
exclude a host project (it prints every submodule a repo registers); and staging
without the up projection destroys the merge it was staged to preserve. Write a
spec a subagent can falsify, and treat its empirical objection as probably
right.

**Gate state.** `just precommit` was OOM-killed twice this session, and so was
the 2-suite chunked fallback. What completed was
`/tmp/claude-1000/gate-chunks1.sh` — one suite at a time, resumable, appending
to `/tmp/claude-1000/gate-results.txt`: 65 suites, 905 tests, 0 failed, plus
lint, memory hygiene, docs-links and version. The `test-unit` and
`test-integration` sentinels were **not** recorded, so they are stale on disk
and must not be read as passes.
