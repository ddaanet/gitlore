# Reverse D78's premise — a tier ahead of its pin outside a take is a fault

One slice, on `dev`. My human partner's call: no normal operation leaves a
tier's `HEAD` ahead of the gitlink the memory index records. The take records
the tier it moves (bookkeeping commit, or staged under D43 on a dirty root), the
memory merge's continuation and the recovery stage what they compose, and the
commit path records every tier with `add -A` after a pending check that saw them
on their pins. What produces the state is a killed take or hand git inside the
tier, and the right answer is the take: `/gitlore:merge` composes the tier's
lines up three-way and records the gitlink. So the compose pass and the commit's
pending check refuse the state naming that remedy, and the seven commits
`4726e3d..971a937`, which instead made the pass stage what it merged and taught
every root move to reset the staged gitlink, come out — except the one dirty
gate in `gitlore_yield_merge`, which stops unapproved files riding a merge
commit on the push and resolve paths and stays.

Probed on 2026-11-09 with the take's real entry point
(`scripts/merge-memory.sh`) from a hand-moved tier: an active tier with `HEAD`
ahead and no local `live`, the same with `live` following `HEAD`, and a dormant
tier, are all recorded in `HEAD:<tier>` (the dormant one staged under D43, since
the manifest edit left the store dirty). The remedy the refusal names is real.

## Outside the frame's literal text

**D50 flips with it.** `docs/decisions.md` D50 and `git-hooks.md` say a tier
ahead of its pin is committed through and list "a refusal for a tier ahead of
its pin" as rejected. After this slice the pending check refuses it, so those
lines would prescribe the opposite of the code: the rejected alternative becomes
the decision, and "committed through" the rejected one, with the reason:
recording it silently hides the killed take or hand git that produced it, and
the take is the one path that composes before it records.

**Every mounted tier, dormant included.** The pin guard and the take's
`gitlore_tiers_ahead_of_pin` both walk `gitlore_tier_paths`, and the commit's
`add -A` records a dormant tier's `HEAD` too, so the refusal covers a dormant
tier ahead of its pin as well; `tests/index_compose_pins_edge.bats` "a dormant
tier moved ahead of its pin does not refuse" flips.

## Refusal line

One problem line from `gitlore_compose_check_pins`, in the arm that today
`continue`s when the pin is an ancestor of `HEAD`, verbatim so the tests and the
scripts can be edited in parallel:

```
tier '<tier>' is checked out at <head:0:12>, ahead of the commit the memory store records at <pinned:0:12>: it was moved outside a completed take, so the root index has not taken its lines. Run /gitlore:merge, which composes them into the root index and records the tier.
```

It reaches the pass (`gitlore_compose`, `PostToolBatch`), the pending check
(`gitlore_compose_pending`: the commit path and `SessionStart`'s diagnostics)
and the commit's pin guard in `gitlore_sync_memory_to_live`, whose header "a
tier was moved off the commit the memory store records for it" already fits.

## Scripts (one agent)

- `scripts/lib/index-compose-check.sh` — `gitlore_compose_check_pins`: the
  ancestor arm becomes the refusal above; the header comment (lines ~196–213)
  states the new rule: a tier ahead of its pin is refused outside a take, the
  take composes and records it.
- `scripts/lib/index-compose-pending.sh` — `gitlore_compose_pass`: the whole up
  block (the `gitlore_tiers_off_pin` read, `gitlore_compose_merge_tiers`, the
  staging, the return 3 path) goes; `ahead`, `dir`, `mrc` go with it; the header
  comment and the rule-7 comment say the pass composes no tier up, since the pin
  guard refuses one ahead. Return code 3 no longer arises from the pass; check
  `gitlore_compose`'s comment in `index-compose.sh` and the `gitlore-compose`
  entry point's documented codes.
- `scripts/lib/index-compose-project.sh` — `gitlore_stage_merged_tiers` comment
  back to chunk-only (the message with the runnable `git add` stays);
  `gitlore_tiers_off_pin` keeps its `$2`, with the continuation as its one
  caller; `gitlore_compose_up`'s comment: its callers are the take, the recovery
  and the continuation.
- `scripts/lib/resolve-adopt-report.sh` — `gitlore_tiers_ahead_of_pin` and
  `gitlore_bookkeeping_message` back to the index read (`:$tier`), since a
  staged gitlink is recorded again; comment at the `msgfile` line and the
  function header.
- `scripts/lib/resolve-merge-prepare.sh` — delete
  `gitlore_unstage_tier_gitlinks_for_move` and its call in
  `gitlore_prepare_merge`; the yield gate's comment loses the sentence naming it
  and keeps the gate.
- `scripts/lib/resolve-merge-stores.sh` — the two call sites (the catch-up onto
  local `live`, the root take before the fast-forward).
- Comments only: `scripts/commit-memory.sh` ("a tier ahead of its pin is checked
  as the pass would compose it"), `scripts/lib/resolve-sync-memory.sh` ("A tier
  ahead of its pin passes, and its HEAD is recorded"),
  `scripts/lib/session-tiers.sh` header ("A tier ahead of its pin is no fault"),
  `scripts/lib/session-diagnostics.sh` orphan comment ("a line a tier off its
  pin added reads as an orphan").
- `grep -rn "ahead of its pin\|off its pin\|unstage_tier_gitlinks\|stage_merged_tiers" scripts bin hooks`
  must come back with only the take, the continuation and the recovery.

## Tests (one agent, in parallel)

- `tests/index_compose_pins.bats` — header comment; "a tier ahead of its pin
  composes up and is left where it stands" becomes a refusal: rc 1, the line
  above on stdout with both shas, `/gitlore:merge` named, root and carrier
  byte-identical to before, tier `HEAD` unmoved, gitlink unstaged; "the check
  leaves the gitlink … unstaged" becomes the pending check's refusal (rc 1, same
  line, gitlink unstaged).
- `tests/index_compose_pins_edge.bats` — "composes up under a project path
  holding a space" becomes the refusal under that path; "keeps its arrival while
  root's new line mirrors down" is driven through the take's path
  (`gitlore_compose_up` + `git add MEMORY.md <tier>` + commit, what
  `gitlore_compose_moved_tiers` does) before the root line is added; "the
  compose-up adopts a tier ahead of its pin" stays; "a dormant tier moved ahead
  of its pin does not refuse" flips to refuses.
- `tests/index_compose_adoption.bats` — the two tests "a root deletion of a line
  the pass adopted …" and "a root reword of a line the pass adopted …" drive the
  take's path instead of the pass (as above); they keep pinning that the
  deletion stands and the reword projects down without a chunk.
- `tests/merge_memory_tiers.bats` — delete the four tests whose fixture is "the
  pass staged": "a tier gitlink the compose pass staged does not block …", "the
  take records a tier the pass staged and that moved further …", "a take with
  nothing upstream keeps the gitlink the pass staged …", "a diverged root
  prepares its merge over a gitlink the pass staged …".
- `tests/killed_take_repro.bats` — "SessionStart reports no dangling pointer and
  no pending compose" flips: the hook's report names the tier ahead and
  `/gitlore:merge` ("cannot be composed until these are fixed"), still no
  dangling pointer, tier unmoved; "gitlore-compose between SessionStart and the
  take changes nothing" flips: rc 1 naming `/gitlore:merge`, root and carrier
  unchanged, then the take records the tier. The first test's SessionStart
  assertions follow.
- Keep `tests/push_behind_vs_diverged.bats` and
  `tests/resolve_merge_remote.bats` dirty-gate tests. After the edits,
  `move_tier_off_pin_into_live` in `tests/helpers/tier-fixtures.bash` either
  keeps a caller or goes.

## Docs (one agent, after the scripts land, since it reads them)

- `docs/references/take-and-compose.md` — D78 retitled "Tier lines compose up
  three-way against the index's gitlink, and a tier ahead of its pin outside a
  take is refused naming the take"; body: the base rule stays; the staging
  paragraph becomes: the take, the recovery and the continuation leave the
  gitlink staged or committed before the next pass reads it, the pass composes
  no tier up and refuses one ahead of its pin, since nothing normal produces it;
  the paragraphs on `HEAD`-read moves and the per-move reset go; the yield gate
  keeps one sentence. Rejected alternatives: drop "Resetting a staged gitlink
  only where the move changes it", "Staging inside gitlore_compose_up"; rewrite
  "Skipping the reset on a dirty root, or a dirty gate per caller" to the gate
  half; replace "Staging the merged tiers only on a chunk" with "The pass
  composing a tier ahead of its pin up and staging the gitlinks it merged" (what
  it cost: every root move met a staged gitlink and grew a reset, and the pass
  recorded what no commit approved); keep "A base read from HEAD" and the
  others. D77's "A marker recording a killed take" says the next take, not "the
  next pass or take". The header's one-line D78 summary follows.
- `docs/decisions.md` — D50 and D78 lines and rejected lists.
- `docs/references/git-hooks.md` — D50 title, body paragraph "A tier ahead of
  its pin is committed through …" becomes the refusal, rejected "A refusal for a
  tier ahead of its pin" becomes "Committing through a tier ahead of its pin".
- One-sentence fixes: `index-composition.md` (~106–109), `session.md` (~249,
  ~296: the hook leaves the tier because the take needs it where it stands),
  `merge-state-recovery.md` (~104: for the take), `tier-arrival-repair.md` (~96:
  the next take), `tier-stores.md` (~67–69), `tiered-memory.md` (~28, ~63),
  `publishing-divergence.md` (~50 table row), `memory-entry-points.md` (~76).
- `just format-docs` and `check-docs-links.py` pass;
  `grep -rn "no fault\|ahead of its pin\|off its pin" docs` reads consistently.

## Residual, declined

A take killed between its `add` and its `commit` with a tier move that changed
no root line leaves a staged gitlink alone; the yield gate's
`--ignore-submodules=all` hides it and a later root move that changes that entry
gets git's refusal on the move's error channel. Rare state, hand-fixable from
the message, no guard.

## Gate

`just precommit` in the background, one commit, `/code-review medium` on it,
high and medium findings fixed in a reviewed fix commit.
