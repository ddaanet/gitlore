# Outline: the unadoptable tier arrival

Deliverable-review Major 1 of `plans/index-edit-propagation`, with minor-pass-2
code m4 folded in. My human partner chose repair (C) plus upstream prevention; a
message fix alone (A) and a push that tolerates the defect (B) are rejected.

## Problem

`gitlore_compose_up` runs `gitlore_compose_check` over root and every carrier. A
carrier that arrives with a duplicate pointer, an interleaved non-bullet line or
a welded line is refused, the take walks the tier back to its pin, and the
arrival stays in the tier's `live`. From there every take refuses again,
`gitlore_push_stores` retakes whenever `live` is ahead, and every push fails.
The message names a worktree file that is clean, and no local remedy exists: a
take refuses a dirty tier, the pin guard refuses a tier checked out at `live`,
and a hand commit on `live` bypasses the approval gate. Upstream publishes the
defect because the commit path treats a compose refusal as advisory (rc 1).

## Approach

1. **Prevention (upstream).** The commit path aborts when a compose refusal
   names an index file the commit carries changes to. A commit that changes an
   index file is the one that would publish its defect.
2. **Repair (downstream).** When a take's refusal names the arriving carrier,
   the take repairs the carrier mechanically — restructuring, never rewording —
   commits the repair on top of the arrival, and adopts it. The push that ran
   the take, or the next push after `/gitlore:merge`, publishes it to every
   consumer. Writers outside gitlore (a hand push, an older gitlore) are why
   prevention alone is not enough. A tier merge whose merged index fails the
   check does not land.
3. **Continuation exits (m4).** `push_or_report` returns a status instead of
   exiting, and a rest moves a tier only when `live` contains HEAD (S4).

## Key decisions

**K1 — The repair is a plain commit on top of the arrival, made inside the
take.** The take has already advanced the tier's `live` and HEAD to the arrival.
On a refusal naming the arriving carrier (K2), `gitlore_adopt_tier_into_root`
repairs a scratch copy of the carrier (K3), rechecks it, builds R with the
arrival as its only parent, advances `live` to R with
`push . <R>:refs/heads/live`, checks the tier out at `live`, and retries
`gitlore_compose_up`. Nothing yields and no state file is written.
- **History:** linear; D6 is untouched. R is unprompted under D49 because it
  adds no text; its subject names the repair and its body lists each edit.
- **The worktree never holds the repair uncommitted.** R is built from a
  temporary index inside the tier's gitdir with `commit-tree`, and the tier
  moves only by checking out `live` once it holds R. A carrier written into the
  worktree before its commit would strand a killed take: `submodule update`
  cannot check the pin out over a modified `MEMORY.md` (probed), the pin guard
  then refuses every commit, and the take refuses the dirty tier. `commit-tree`
  runs no hook, so no `GITLORE_MEMORY_COMMIT` sentinel is needed.
- **Interruption:** a take killed before the up projection writes root leaves
  the tier clean, off its pin or on it, with no state. SessionStart's
  unconditional `submodule update` returns it to the pin, `live` keeps the
  arrival or R, and the next take repairs again or adopts R. The repair is
  deterministic, so a lost R costs nothing. A kill after root is written is the
  window every take already has, unchanged here.
- **A refused `live` update** leaves R unreachable: the tier, still on the
  arrival, walks back to its pin, `live` stays on the arrival, and the take
  exits 1 with git's message.
- **No merge machinery:** the entry-wise index pass never runs, so every line
  the rules do not name keeps its bytes.
- **Rejected:** a `--no-ff` merge of the arrival onto the pin — merge used for
  convenience with no two histories to join, which inverted D6's parent order
  and needed four patches (pin guard, recovery target, entry-wise pass, marker
  completion). An agent-driven repair through the memory-merger — every edit K3
  allows is computable, and the agent shape needed a repair state, its detection
  and recovery arms, a landed-repair scan and a merger contract exception.

**K2 — A refusal in which any problem names the arriving carrier repairs.**
Problem lines are attributed by the `"<file>:"` prefix
`gitlore_compose_check_index` prints — `"$mempath/$tier/MEMORY.md:"` for a
carrier, `"$mempath/MEMORY.md:"` for root — matched exactly against the
`$mempath` spelling the check was given. Rules 2 and 3 print no file prefix.
- **The repair covers** the carrier's lines.
- **The rest** — root, the manifest, another tier's carrier — are fixes this
  repo makes itself. The take's report names them as what adoption waits on, and
  the tier rests on its pin with R in `live`; the next take or push adopts R
  with no second repair.
- **No problem names the arriving carrier:** nothing is repaired, and the tier
  rests on its pin with the arrival in `live` until the local problems are
  fixed.
- **A carrier problem the repair cannot fix** (K3's weld guard): the take walks
  back as today, and its report attributes those problems to the arrival held in
  the tier's `live`, never to the worktree carrier, which is clean.
- **Several defective arrivals:** tiers are taken one at a time and the first
  failure stops the pass, so each is repaired in turn.

**K3 — The repair restructures and never rewords.**
`gitlore_repair_index <file> <pin-carrier> <tier-dir>` rewrites `<file>` (a
scratch copy of the arrival's carrier, outside the worktree) and applies, in
order:
1. **Welds:** a welded line is split before the second link's `- [` — exactly
   the shape `gitlore_welded_path` reports — repeated until none remain, and
   only when the welded path names a file in the tier. A bare `[x](y.md)` in a
   hook is not a weld and is left unchanged. Welds go first because a weld can
   hide a duplicate.
2. **Interleaved non-bullet lines** (non-blank, as rule 4 flags them) move
   verbatim to the start of the trailer, keeping their order.
3. **Duplicate pointers:** an identical duplicate is dropped. Of differing lines
   sharing a path, the first one the pin's carrier lacks survives, at its own
   position; when the pin's carrier lacks none or all of them, the first
   survives.

Every other line keeps its bytes and relative order. It prints one line per
edit, naming each dropped line verbatim. A wrong pick is an ordinary edit, which
goes upstream. The D50 node records the line this draws:
`gitlore-tier-merge-direction` governs wording, and a structural defect the up
projection cannot adopt is repaired by the take.

**K4 — A merge continuation refuses to commit while the merged index fails the
check.** Before the merge commit, problems the S1 helper attributes to the
merged index file — the tier's carrier for a tier merge, root `MEMORY.md` under
rules 1, 4 and 6 for a memory-root merge — exit 1 with those problems, keep the
merge state and `MERGE_HEAD`, and commit nothing. The parent rejects with the
problem list and a new synthesis follows. Problems outside the merged index let
the merge land: a tier merge rests the tier, and a memory-root merge commits
uncomposed, as now. The mechanical repair is for arrivals, never for a
synthesis: what this repo authors (a commit, a synthesis) is refused and
re-authored; what arrives is repaired. This replaces `index-composition.md`'s "a
refusal in the continuation never blocks" for the merged index.

**K5 — Prevention aborts on a problem in an index file the commit carries
changes to.** In the rc 1 arm of `gitlore_sync_memory_to_live`:
- **Aborts:** a carrier with uncommitted changes
  (`git -C <tier> status --porcelain -- MEMORY.md` non-empty) that has problems,
  or a dirty root `MEMORY.md` with a rule 1, 4 or 6 problem. The abort restamps
  the approval (`touch "$msgfile"`, as rc 2 does), names the problems, and says
  the fix is an edit to the named lines and the summary needs approval again.
  Compose rc 1 writes nothing, so dirtiness does not change across it.
  `pre-commit` and `commit-memory.sh` share the body.
- **Stays advisory:** root rules 2 and 3, and problems in clean files — a dirty
  tier whose carrier is unchanged included.

**K6 — The repair publishes the way its take does.** A take inside a push
publishes R in that push, before memory's push records R's gitlink. Both push
arms reach the take: `live` ahead of HEAD, and a tier push refused as `behind`.
The `behind` arm today `continue`s past the tier's push after its take, so it
retries the tier push when the take left `live` ahead of `origin/live`.
`/gitlore:merge` leaves R in the tier's `live`, and its report names
`/gitlore:push`. A repair resting on local problems publishes nothing until they
are fixed.

**K7 — Decision records.** A new **D52** in `tier-stores.md`: the mechanical
arrival repair, its rules, attribution and publication, the rest guard, and the
continuation gate. D50's conclusion is amended: a compose refusal in an index
file the commit carries changes to aborts, root rules 2 and 3 excepted.
`decisions.md` names the rejected alternatives: A, a message fix alone; B, a
push that tolerates the defect; a `--no-ff` repair merge onto the pin; an
agent-driven repair through the memory-merger; a mechanical repair of a merge
synthesis; repairing only when every problem names the carrier; a continuation
that commits a defective merged index uncomposed.

## Sub-problems

**S1 — Prevention** (tdd). Files: `scripts/lib/resolve.sh` (the rc 1 arm of
`gitlore_sync_memory_to_live`), `scripts/lib/index-compose.sh` (the attribution
helper, beside the check whose output it parses), `tests/index_compose.bats`,
`tests/commit_memory.bats`, `tests/git_hook_pre_commit.bats`.
- **Helper:** given the check's output and `$mempath`, prints the problems
  attributed to one index file (root or a tier's carrier) by exact `"<file>:"`
  prefix. S2 and S3 reuse it.
- **Postconditions:**
  - A dirty carrier with a duplicate pointer aborts the commit through
    `commit-memory.sh` and through `pre-commit`: the output names the problem,
    the tier and memory stay uncommitted, the tier's `live` is unmoved, and the
    approval is restamped.
  - A dirty root `MEMORY.md` with a welded line aborts the same way.
  - The same carrier defect in a clean tier commits and reports, and so does a
    tier dirty only outside its carrier.
  - A rule 3 leftover prefix in root commits and reports, even when root is
    dirty.
  - The helper attributes correctly under a `$mempath` containing a space, and
    for tier names where one is a prefix of another.
  - The arm's comment states which problems abort and which report.

**S2 — Mechanical repair in the take** (tdd). Files:
`scripts/lib/index-compose.sh` (new `gitlore_repair_index`, and a comment at
`gitlore_compose_check_index` that a new rule gains a repair rule in the same
change), `scripts/lib/resolve.sh` (`gitlore_adopt_tier_into_root`,
`gitlore_merge_one_store`, the `behind` arm of `gitlore_push_stores`),
`tests/index_compose.bats`, `tests/merge_memory.bats` (the take),
`tests/push_behind_vs_diverged.bats` (the take inside a push).
- **Unit postconditions** (`gitlore_repair_index`, rules per K3):
  - Each rule alone; a three-bullet weld; a bare `[x](y.md)` in a hook, with
    `y.md` in the tier, is left unchanged.
  - A hook quoting a link whose path names no file in the tier is left
    unchanged.
  - A differing duplicate keeps the line the pin lacks, even when it comes
    second; one where neither line existed at the pin keeps the first; a pin
    with no `MEMORY.md`.
  - The result passes `gitlore_compose_check_index`, every unnamed line keeps
    its bytes and order, and a clean index is byte-identical.
- **Take postconditions:**
  - **Carrier problems only:** the take exits 0; R's only parent is the arrival;
    HEAD and `live` are R; root adopts R and the pair is committed; the report
    lists each edit. Under `/gitlore:merge`, origin is unchanged and the report
    names `/gitlore:push`; through a push — both the `live`-ahead and the
    `behind` arm — the tier's origin holds R before memory's origin holds the
    gitlink recording it.
  - **Carrier plus a root problem:** R lands in `live`, the tier rests on its
    pin, and the take exits 1 listing only the root problem. After the root is
    fixed, the next take adopts R with no second repair commit.
  - **No problem names the carrier:** the take walks back as today, `live` on
    the arrival.
  - **The check still refuses after the repair** (a guarded weld): nothing is
    committed, the tier walks back with a clean worktree, and the report lists
    the remaining problems as the arrival's in `live`.
  - **A refused `live` update after R is built** (a held `live` lock): the tier
    is on its pin with a clean worktree, `live` on the arrival, no ref reaches
    R, and the take exits 1 with git's message. The next take repairs again.
  - **Walk-back** asserts that `live` contains HEAD.
  - **Fetch first:** `gitlore_merge_one_store` fetches before
    `gitlore_adopt_advanced_live`. When local `live` is an ancestor of
    `origin/live`, the local adoption is skipped and the remote fast-forward
    takes origin's commits, so a consumer resting with the arrival takes another
    consumer's published repair with no repair commit of its own. A failed fetch
    still adopts local `live`, then reports the fetch failure and exits 1 as
    today.
  - **Reach:** both through `gitlore_adopt_advanced_live` and through a remote
    fast-forward.
- **Fixture:** the upstream clone commits a defective carrier by hand and
  pushes, bypassing S1; one arrival per defect kind.

**S3 — Continuation gate** (tdd). Files: `scripts/resolve.sh`
(`compose_merged_indexes`), `tests/resolve_compose.bats`.
- **Gate:** before the merge commit, problems the S1 helper attributes to the
  merged index file (K4) print and exit 1.
- **Postconditions:**
  - A `head-vs-remote` tier merge whose staged carrier holds a duplicate pointer
    exits 1 before the commit: output lists the carrier problems, the state file
    and `MERGE_HEAD` are kept, no tier commit, root untouched. Same for
    `head-vs-live`.
  - A later gate meeting the kept merge re-emits the continue-after-merge
    directive.
  - After the carrier is fixed, the continuation lands the merge.
  - A merged carrier that passes, beside a root problem, lands and rests the
    tier.
  - A memory-root merge whose merged root index holds a welded line exits 1
    before the commit. The existing case "a compose refusal is reported but
    never strands the merge" (a duplicate in the merged root index) inverts to
    the same refusal.

**S4 — m4 per-arm exits and the rest guard** (tdd). Files: `scripts/resolve.sh`
(`push_or_report`, its callers including `check_store_gates`,
`rest_unadopted_tier`), `tests/resolve_compose.bats`.
- **Contract:** `push_or_report` returns 0 on success, 1 on divergence, and 2
  after emitting for any other refusal. Every call is written `|| rc=$?`, never
  `if !`. On status 2 the continuation rests an unadopted tier and exits 1.
- **Rest guard:** `rest_unadopted_tier` checks the tier out at its pin only when
  `live` contains HEAD. Otherwise it leaves the tier on its commit and prints a
  verbatim-runnable remedy: `git -C "<abs tier>" push . HEAD:live`, then
  `git -C "<abs tier>" checkout --detach <pin>`, then fix the problems listed
  above, then `/gitlore:merge`.
- **Postconditions:**
  - An origin push declined by `pre-receive`, with an unadopted tier, leaves the
    tier on its pin with `live` on the merge, and exits 1.
  - A local `HEAD:live` refusal (a held `live.lock`), with an unadopted tier,
    leaves the tier on the merge, prints the remedy and exits 1.
  - Following that remedy — the root problem fixed — then `/gitlore:merge`,
    adopts the merge into root.
  - Default-mode `check_store_gates` exits 1 on status 2, as now.

**S5 — Agent-facing prose** (inline, opus).
- **`agents/memory-merger.md`:** a synthesized `MEMORY.md` keeps one pointer per
  bullet, one bullet per line, and no non-bullet line inside the pointer block.
  In turn 2, a continuation exiting 1 with problems in the merged index means
  the merge did not land: quote those lines and stop.
- **`skills/resolve/SKILL.md`:** that exit is answered with `rejected:` and the
  problem lines, and the loop continues. Summarize separates index problems that
  blocked the landing from those reported after it.
- **`skills/merge/SKILL.md` Report:** a take that repaired an arrival relays
  each edit and dropped line, and says `/gitlore:push` publishes the repair.

**S6 — Design records** (inline, opus).
- **`docs/references/tier-stores.md`:** D52 (the mechanical arrival repair, its
  rules, attribution and publication, the continuation gate); the walk-back and
  unadopted-merge paragraphs rewritten to present truth; the adoption
  paragraph's "at the head of every take" for fetch-first; the rest guard as the
  third resting exception.
- **`docs/references/git-hooks.md`:** D50's amended conclusion (abort on
  problems in an index file this commit changes, root rules 2 and 3 advisory)
  and the wording/structure line linked to D52.
- **`docs/references/index-composition.md`:** the continuation paragraph (lines
  116-120) states that problems in the merged index block the landing, and what
  still commits uncomposed.
- **`docs/decisions.md`:** D52, the amended D50 line, K7's rejected
  alternatives.
- **`docs/design.md`:** the D50 sentence at line 232.
- **Changelog:** an entry plus its index line.

**S7 — Memory fact** (inline, opus). Files:
`memory/ddaanet/gitlore-tier-merge-direction.md` and its root index line.
- **New paragraph after the propagation rule:** a structural defect upstream
  sent — a duplicate pointer, a welded line, a non-bullet line inside the
  pointer block — is repaired by the take itself, as a plain commit on the
  arrival that restructures and never rewords, listed in the take's report and
  published by the push that ran the take or the next one. Don't hand-edit the
  arriving carrier. A merge synthesis carrying such a defect is refused before
  it commits, and the answer is a new synthesis.
- **Hook:** the description and index line gain "a structural defect upstream
  sent is the take's to repair". The file stays under 4KB.

## Dependencies

- **S1 before S2 and S3:** both reuse its attribution helper.
- **S2, S3, S4:** no ordering edge; S3 and S4 edit different functions of
  `scripts/resolve.sh`, and one sequential executor owns the scripts and
  `tests/resolve_compose.bats`.
- **S5 after S2 and S3:** it describes the take's repair report and the
  continuation gate.
- **S6 after S1–S4; S7 after S6.**
- **Order:** S1 → S2 → S3 → S4 → S5 → S6 → S7.

## Scope

**IN:** S1–S7.

**OUT:**
- Surfacing index problems earlier, in the `PostToolBatch` compose report.
- minor-pass-2 code m3 and test m9.
- The entry-wise index pass dropping interleaved and blank pointer-region lines
  in ordinary merges, tracked as its own defect.
- A tier whose local `live` failed to advance after its commit on the commit
  path, tracked separately.

## Risks

- **Two consumers repair the same arrival:** usually identical trees; the later
  push merges them with `No conflict.`. Fetch-first (S2) avoids it for a
  consumer resting with the arrival.
- **Pre-push publishes without the check:** accepted residual, covered
  downstream by the repair.
- **A check rule with no repair rule:** the take walks back for that rule; the
  check's comment couples the two.
- **The mechanical pick drops the wrong duplicate:** the report names it; an
  ordinary edit fixes it upstream.
- **A weld the guard leaves** (a hook quoting a link to a path the tier lacks):
  not repaired. The tier is wedged as before this job — every take walks back
  and every push fails — until upstream edits the line; the report names the
  arrival as the source.
