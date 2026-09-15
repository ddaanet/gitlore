# Deliverable review — prose (unadoptable tier arrival)

## Scope reviewed

Range `e60ff38..HEAD`. Claims checked against `scripts/lib/index-compose.sh`,
`scripts/lib/resolve.sh`, `scripts/resolve.sh`, `scripts/lib/util.sh`
(freshness) and `scripts/cc-hooks/memory-commit-batch.sh`.
`scripts/check-docs-links.py` run read-only: 0 broken links, 0 drift, 0
oversized files.

| File | `wc -l` |
| --- | --- |
| agents/memory-merger.md | 50 |
| skills/merge/SKILL.md | 74 |
| skills/push/SKILL.md | 82 |
| skills/resolve/SKILL.md | 90 |
| docs/references/tier-arrival-repair.md | 164 |
| docs/references/tier-stores.md | 311 |
| docs/references/git-hooks.md | 270 |
| docs/references/index-composition.md | 324 |
| docs/references/merge-and-resolve.md | 367 |
| docs/references/commit-gate.md | 272 |
| docs/references/tiered-memory.md | 195 |
| docs/decisions.md | 162 |
| docs/design.md | 292 |
| docs/changelog.md | 368 |
| docs/changelog/2026-09-15-an-arrival-the-root-index-cannot-adopt-is-repaired.md | 79 |

All files are under the 400-line cap, and each `SKILL.md` is under 200.

I grepped for literal strings. Every message the agent-facing prose quotes is in
the scripts, byte for byte:
- `gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:`
  is at `scripts/resolve.sh:136`.
- `gitlore: repaired %s's arrival: %s` is in `gitlore_adopt_repair_arrival`.
- `… the repair is committed in its local 'live', and this push publishes it.`
  and `…; /gitlore:push publishes it.` are in the same function.
- The
  `stays on the merge commit because its local 'live' does not hold it. Run:`
  block and its two commands are in `rest_unadopted_tier`.
- `Once the index is fixed where it was published, run /gitlore:merge again.` is
  the remedy passed to `gitlore_adopt_walk_back_tier`.

The following all match the code:
- **K5:** abort only for a rule 1/4/6 problem in a file with uncommitted
  changes; rules 2 and 3 print no `<file>: ` prefix (`gitlore_compose_check`,
  rules 2 and 3); restamp via `touch "$msgfile"`.
- **K3:** rule order, the weld guard (`gitlore_repair_tier_file`: no leading
  `/`, no `..` component, `-f`), and stray lines moved to after the last bullet.
- **K4:** gate scope is `gitlore_compose_problems_in "$merged_index"`, exit 1
  before `add`.
- **K6:** both push arms, and the `behind` arm's
  `merge-base --is-ancestor live origin/live` re-push.
- **Rest guard:** `merge-base --is-ancestor HEAD live`.
- **Fetch-first:** adoption is skipped when `origin/live` contains `live`.
- **`push_or_report`:** returns 2.

## Critical

None.

## Major

**M1 — skills/merge/SKILL.md:68-72 — actionability / accuracy — Major.** The
Report paragraph tells the agent to relay the repair lines "and say that the
repair is committed in the tier's local `live` and `/gitlore:push` publishes
it". Only then does it cover the case where the take rests on this repo's own
problems. Nothing limits the push claim to a take that landed, but in the
resting case `/gitlore:push` does not publish the repair.
- **Evidence:** the resting case prints the `gitlore: repaired …` lines and then
  goes through `gitlore_adopt_report_refusal_and_walk_back`. The
  `/gitlore:push publishes it` line comes only after a successful retry:
  `if [ "$retry_rc" -ne 0 ]; then gitlore_adopt_report_refusal_and_walk_back … return 1; fi`
  sits ahead of the
  `printf 'gitlore: %s — the repair is committed in its local '\''live'\''; /gitlore:push publishes it.\n'`
  line in `gitlore_adopt_repair_arrival`.
- **Why the push fails:** a later push reaches
  `if gitlore_live_ahead_of_head "$tierpath"; then GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores "$mempath" || return 1`
  in `gitlore_push_stores`. That take refuses again on the same root problem, so
  the push fails. `tier-arrival-repair.md:99` agrees: "A repair resting on local
  problems publishes nothing until they are fixed."
- **Effect:** the agent tells the user a push will publish the repair while the
  push is blocked on a local fix.
- **Fix:** say `/gitlore:push` publishes it only when the run printed that line,
  and in the resting case say it publishes once the listed problems are fixed.

## Minor

**m1 — agents/memory-merger.md:28 — constraint precision — Minor.** "Keeps one
pointer per bullet, one bullet per line, and no non-bullet line inside the
pointer block" describes rules 6 and 4. It never says what rule 1 checks: no two
bullets may name the same path. `gitlore_compose_check_index` flags that as
`duplicate pointer path`. The first two clauses both describe a weld, so the
merger is never told about duplicates. The gate still catches one, at the cost
of a rejection cycle. Suggested wording: "one bullet per file path, one pointer
per bullet, one bullet per line …".

**m2 — agents/memory-merger.md:39; skills/resolve/SKILL.md:85-86 — accuracy —
Minor.** Both texts say that for any exit other than the merged-index message,
the remaining `gitlore:` lines "come after the merge commit" or "came after the
merge commit landed". That is not always true. `scripts/resolve.sh` also exits 1
before landing when the message cannot be built or the commit itself is refused:
`gitlore_merge_commit_message … || { rm -f "$merge_msgfile"; exit 1; }` and
`GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$merge_msgfile" || { rm -f "$merge_msgfile"; exit 1; }`.
In both cases `MERGE_HEAD` is kept and nothing landed. These failures are rare,
but the "otherwise" branch reports them as a landed merge.

**m3 — docs/references/git-hooks.md:155-157 — accuracy / clarity — Minor.** "A
duplicate, interleaved or welded line in root's `MEMORY.md` or in a tier carrier
with uncommitted changes aborts" can be read as root aborting whether or not it
is dirty. The code requires `git -C "$mempath" status --porcelain -- MEMORY.md`
to be non-empty for root too. The next sentence fixes the reading, but the
changelog's phrasing, "when that file has uncommitted changes", is the
unambiguous one.

**m4 — docs/references/tier-arrival-repair.md:20-26 — living-doc style /
accuracy — Minor.** The opening paragraph is in the present tense: "the take
walks back with the arrival in `live`. Every later take refuses the same way,
and every push retakes and fails … the worktree carrier the refusal names is
clean". That describes behaviour the repair has replaced for every repairable
arrival. A reader skimming the node takes it as current behaviour. Frame it as
the unrepaired case ("Left unrepaired, …").

**m5 — docs/references/tier-stores.md:190-195 — clarity — Minor.** The sentence
now reads "…and exits 1 after resting the tier when a push is refused … The
remedy is printed instead — fix the store and run `/gitlore:merge`". "Instead"
was written when the sentence before it ended "exits 0", and it no longer has a
referent. Drop it or say what the remedy stands in for.

**m6 — docs/references/index-authoring-sync.md:5 — consistency — Minor.** It
still says "One of the four nodes of the tiered-memory subsystem". This job
added a fifth node, and `index-composition.md:5` and `tiered-memory.md:5,23`
were updated to five.

**m7 — docs/changelog.md:15-16 — clarity — Minor.** "a push refused for any
other reason rests the tier only when its `live` holds the merge": "other" has
no antecedent in the index line. The entry body says "for any reason but
divergence".

**m8 — docs/references/commit-gate.md:57-61 — accuracy — Minor.** "Lands only
once the edit is made" lists an off-pin tier as an edit. Its remedy is a
checkout or a take, not an edit to the named lines. (The approval re-stamp and
retry interaction is tracked.)

**m9 — scripts/lib/resolve.sh:2018 vs docs/references/tier-stores.md:180-181 —
consistency — Minor.** In the resting-repair case, the walk-back message that
the merge skill relays verbatim says "its local 'live' keeps what arrived".
`tier-stores.md` says `live` "keeps the repair rather than the arrival", and it
does. The shared `gitlore_adopt_walk_back_tier` wording is wrong for this
caller. This is script text, but it contradicts the doc and is relayed to the
user.

(tracked) `tier-arrival-repair.md:118-119` and `index-composition.md:128`: a
store with no root `MEMORY.md` runs no check.

(tracked) `merge-and-resolve.md:98-100`, "memory's pointer never goes out ahead
of a tier": `resolve.sh`'s "remote has no live branch. Pushing." runs before the
tier gates.

(tracked) `skills/resolve/SKILL.md:68`: the "same problem line again" stop is
the agent's only bound on refuse/re-synthesize cycles.

(tracked) `commit-gate.md` / `memory-commit-batch.sh`: a deferred retry after
the requested fix versus "the summary needs approval again".

## Conformance map

| Outline item | Covered by |
| --- | --- |
| S5 merger: synthesized `MEMORY.md` structure | agents/memory-merger.md:28 (duplicates implicit, m1) |
| S5 merger: turn 2, exit 1 → quote and stop | agents/memory-merger.md:38 |
| S5 resolve: answer with `rejected:` + lines, loop continues | skills/resolve/SKILL.md:68 |
| S5 resolve: Summarize separates blocked vs reported | skills/resolve/SKILL.md:82-90 |
| S5 merge Report: relay edits and dropped lines, `/gitlore:push` publishes | skills/merge/SKILL.md:65-74 (resting case, M1) |
| (accepted extra) push skill relays repair lines | skills/push/SKILL.md:17-20, 34-35 |
| S6 D52: rules, attribution, publication, gate (node accepted) | docs/references/tier-arrival-repair.md:17-129 |
| S6 tier-stores: walk-back paragraph | docs/references/tier-stores.md:171-180 |
| S6 tier-stores: unadopted-merge paragraph | docs/references/tier-stores.md:182-195 |
| S6 tier-stores: adoption, fetch-first | docs/references/tier-stores.md:118-131 |
| S6 tier-stores: rest guard as third exception | docs/references/tier-stores.md:197-214 |
| S6 git-hooks: D50 amended conclusion | docs/references/git-hooks.md:15-17, 135-136, 152-161 |
| S6 git-hooks: wording/structure line linked to D52 | docs/references/git-hooks.md:163-167 |
| S6 index-composition: continuation paragraph | docs/references/index-composition.md:117-131 |
| S6 decisions: D52 | docs/decisions.md:134-137 (group intro, per the tiered-memory convention) |
| S6 decisions: amended D50 line | docs/decisions.md:53-55 |
| S6 design.md: D50 sentence | docs/design.md:234-236 (+ FR11 exemption :52-54, merge skill :199-200) |
| S6 changelog entry + index line | docs/changelog/2026-09-15-…md; docs/changelog.md:9-17 |
| K7 rejected: message fix alone (A) | decisions.md:150; tier-arrival-repair.md:133 |
| K7 rejected: push tolerating the defect (B) | decisions.md:150-151; tier-arrival-repair.md:137 |
| K7 rejected: `--no-ff` repair merge | decisions.md:151; tier-arrival-repair.md:141 |
| K7 rejected: agent-driven repair | decisions.md:151-152; tier-arrival-repair.md:146 |
| K7 rejected: mechanical repair of a synthesis | decisions.md:152; tier-arrival-repair.md:151 |
| K7 rejected: repair only when every problem names the carrier | decisions.md:152-153; tier-arrival-repair.md:156 |
| K7 rejected: continuation committing a defective merged index | decisions.md:153-154; tier-arrival-repair.md:161 |
| S7 memory fact | dropped deliberately (not assessed) |
