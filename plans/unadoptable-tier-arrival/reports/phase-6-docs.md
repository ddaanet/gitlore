# Phase 6 — design records

**Commit**: `ce3c23b`. The subject was given as `docs: Phase 6 — …`. The gitmoji
`commit-msg` hook rewrote the `docs:` prefix to `📝`, so it landed as
`📝 Phase 6 — D52 records the arrival repair and the merged-index gate, and D50 aborts on a changed index's problems`.
It contains 11 docs files, staged by explicit path. No handoff files, `plans/`
or other trees are in it.

## Structural deviation: D52 has its own node

The runbook puts D52 in `docs/references/tier-stores.md`. Once D52's body was
written, that file measured 402 lines before its seven rejected alternatives
were added, and about 440 after. `oversized-file` is a **blocking** check in
`scripts/check-docs-links.py` (MAX_LINES 400). The only ways to stay in
`tier-stores.md` were to cram lines or cut argument, and the rules forbid both.

So D52 and its seven rejected alternatives live in a new node,
**`docs/references/tier-arrival-repair.md`** (164 lines). `tier-stores.md` keeps
everything the runbook asked to change about D43 (fetch-first, walk-back,
unadopted merge, rest guard) and D44's sentence, and grows 277 → 311 lines. The
graph is wired as follows:

- `decisions.md`: the Tiered memory delegation reads
  `(D52) in [tier-arrival-repair.md]`. The node's opening summary bullet is the
  conclusion line. This is the format the group already uses for D42–D44; a
  `- **D52** —` bullet would have broken that group's convention.
- `tiered-memory.md`: "three sibling nodes" becomes four, and the enumeration
  becomes `D26–D40, D42–D44, D47 and D52`. The summary list gains a D52 bullet.
- `index-composition.md`: "one of the four nodes" becomes five.
- `tier-stores.md`: the summary points to the new node for D52.

If the lead wants D52 inside `tier-stores.md`, something there has to move out
to make room.

## Per file

- **`references/tier-arrival-repair.md`** (new). D52:
  - The problem, and why prevention alone falls short (a hand push, an older
    gitlore).
  - The repair as a plain `commit-tree` commit on the arrival, with its subject
    and the edit lines.
  - Interruption and the worktree argument, and the refused `live` update.
  - The three rules as a numbered list. The weld guard requires an existing file
    inside the tier, never a leading `/` or `..`. The pin-lacks pick. A new
    check rule gains a repair rule.
  - The wording/structure line that D50 records.
  - Attribution by exact `<file>: ` prefix. Resting on local problems. The
    unrepairable `live:MEMORY.md` report and its closing line, verbatim. The
    wedge residual. Several arrivals repaired in turn.
  - Publication, with both success lines verbatim by context. Both push arms and
    the `behind` re-push. Fetch-first, and two consumers meeting as a
    divergence. The `pre-push` residual.
  - The continuation gate: the refusal header verbatim, what is kept, and the
    `rejected:` loop. Tier carrier vs root duplicate/interleaved/welded. What
    still lands. A rootless store runs no check at all.
  - A short paragraph on per-arm push statuses and the rest guard, pointing to
    `tier-stores.md` for the remedy.
  - `## Rejected alternatives`: all seven K7 alternatives by name.
- **`references/tier-stores.md`**:
  - The adoption paragraph's "at the head of every take" is now fetch-first,
    including the skip condition and the no-remote / failed-fetch / no-`live`
    cases.
  - The walk-back paragraph now says a carrier-naming refusal is repaired first
    and lists when the tier still walks back, with `live` keeping the repair
    after a retry refusal.
  - The unadopted-merge paragraph: a failing merged carrier never reaches it;
    exit 0 vs exit 1 after a status-2 push. A new paragraph gives the three
    cases that leave the tier off its pin, the rest guard third ("rests on its
    pin only when its local `live` holds the merge"), and quotes both remedy
    commands verbatim, including the `merge-base --is-ancestor … &&` second
    line.
  - D44: "on any of gitlore's own paths … an arrival from a writer outside
    gitlore that carries one is repaired by the take (D52)".
- **`references/git-hooks.md`**:
  - The D50 summary bullet and D50's title are amended.
  - Mechanism step 3: rc 1 aborts on a problem in an index file with uncommitted
    changes and otherwise reports. The freshness gate meets a tier's
    prepared-merge directive before it asks for a summary (Phase 3's commit-path
    fix).
  - D50's "two refusals" argument is rewritten. It covers what aborts
    (duplicate/interleaved/welded in dirty root or carrier), the restamp and
    listed files, why compose rc 1 cannot change dirtiness, and what reports
    (clean files, a tier dirty outside its carrier, the manifest and
    leftover-prefix rules). It also gives the wording/structure line, linked to
    D52.
- **`references/commit-gate.md`**:
  - The IPC retry paragraph now says a refusal that needs an edit (an
    index-problem abort, or an off-pin tier) retries but lands only after the
    edit, and the hook's agent message defers to the fix.
  - D12 notes that the repair commit needs no sentinel (`commit-tree`, FR11
    exemption).
- **`references/index-composition.md`**:
  - The continuation paragraph now says a merged-index problem blocks the
    landing (tier carrier; root duplicate/interleaved/welded), and why. Any
    other refusal still lands: memory-root uncomposed, tier rested. A rootless
    store runs no check.
  - The node count is updated.
- **`decisions.md`**:
  - The D50 line is amended.
  - The D52 delegation is added.
  - The seven rejected alternatives are on the Tiered memory *Rejected* line,
    tagged `(tier-arrival-repair.md)`.
- **`design.md`**:
  - The D50 sentence gains the abort on a compose problem in a changed index
    file.
  - FR11's exemption names the repair (D52).
  - The `merge` skill bullet notes that it repairs an arrival (D52).
- **`references/merge-and-resolve.md`**:
  - D49's exemption sentence names the arrival repair commit, linked to D52.
  - Resolve step 4 gains the merged-index refusal and the status-2 exit after
    resting.
  - Step 5 gains the tier-before-memory gate order, and the rest remedy relayed
    as still to run.
- **`references/tiered-memory.md`**: the enumerations and sibling count above.
- **`changelog/2026-09-15-an-arrival-the-root-index-cannot-adopt-is-repaired.md`**
  and its newest-first line in `changelog.md`. The entry covers:
  - the defect;
  - the D50 abort and the batch hook's message;
  - the repair, with the edit and success lines verbatim per context, the
    `behind` re-push, resting, the unrepairable closing line and fetch-first;
  - the merged-index refusal verbatim, with merger and resolve behaviour and the
    unapproved-commit directive;
  - per-arm push statuses and the rest guard, with the four-line remedy
    verbatim;
  - the refused merge commit leaving no message file;
  - the standalone resolver gating tiers before memory;
  - the rejected alternatives in brief.

## Extra stale statements found and fixed

| Where | Stale statement | Now |
|---|---|---|
| `git-hooks.md` D50 body ("Staging a moved gitlink…") | "keeping what arrived in its local `live`"; "a landed merge continuation that stages nothing and exits 0 onto a pin the merge contains; a yield and a pin off to the side leave the tier where it is" | the take's repair may be what `live` keeps; the continuation rests only once `live` holds the merge; a `live` short of the merge is the third case left in place |
| `git-hooks.md` step 3 | freshness gate listed before each tier's stale-merge guard, with no mention that an unapproved dirty store meets a tier's prepared-merge directive first | stated |
| `commit-gate.md` D12 | "Every gitlore-internal commit path exports the sentinel … all three blessed paths" (the repair commit uses none) | the repair needs none, being `commit-tree`, and is FR11-exempt |
| `tiered-memory.md` | "three sibling nodes", "the tier-store trio D42–D44", "D26–D40, D42–D44 and D47 … three siblings" | four siblings, D52 included |
| `index-composition.md` header | "One of the four nodes" | five |
| `merge-and-resolve.md` resolve steps 4–5 | no merged-index refusal; continuation implied to succeed after pushing; no store order | the refusal, the status-2 exit after rest, tiers gated before memory, the rest remedy relayed as still to run |
| `design.md` `merge` skill bullet | "takes what every remote holds and publishes nothing" (it can now write a repair commit) | notes the repair |

The runbook's own targets were fixed as specified: `index-composition.md` "never
blocks … commits uncomposed", `tier-stores.md` "no dedup pass is needed" and "at
the head of every take", `git-hooks.md` "rc 1 reports and continues", "the
refusal is only reported" and the summary bullet, `decisions.md` "a compose
refusal only reports", and `commit-gate.md` "no agent action".

Searched and not stale in `docs/`: "Exit status stays the caller's" and "EXITS
1" for `push_or_report`. Both appear only in `scripts/resolve.sh` comments,
which are out of scope here.
- The `rest_unadopted_tier` header still says "Exit status stays the caller's
  either way", which remains true, since the function returns 0 and the caller
  decides.
- The `compose_merged_indexes` "EXITS 1" is correct.

Not changed, judged still true:
- `workflows.md` take/publish steps.
- `memory-entry-points.md` shared-body summaries.
- `merge-state-recovery.md`.
- D35's "hand-editing a carrier is a documented requirement when a pointer
  arrives from upstream in a merge". It is about merges, which are
  re-synthesized rather than repaired.

## Outline vs shipped code (code followed throughout)

- **Rest-guard remedy, second line**: the outline has a bare
  `checkout --detach <pin>`. Shipped:
  `git -C "<abs>" merge-base --is-ancestor HEAD live && git -C "<abs>" checkout --detach <pin>`.
  The docs quote the shipped line.
- **Repair success line**: the outline has one line naming `/gitlore:push`.
  Shipped has two. Under `/gitlore:merge` it is `…; /gitlore:push publishes it.`
  Inside a push (`GITLORE_TAKE_IN_PUSH`) it is `…, and this push publishes it.`
  The docs give both.
- **Unrepairable walk-back closing**: shipped
  `Once the index is fixed where it was published, run /gitlore:merge again.`
  and not the default "Fix the store…". Problem lines are indented
  `gitlore:   live:MEMORY.md: …`.
- **Weld guard**: shipped adds containment (`gitlore_repair_tier_file` rejects a
  leading `/` and `..` components). The docs state it.
- **Duplicates rule**: the outline says "when the pin's carrier lacks none or
  all of them, the first survives". The code picks the first line the pin lacks,
  falling back to the first. "Lacks all" then yields the first line anyway, so
  the two agree; the docs state the code's single rule.
- **Standalone resolver order and refused-merge-commit cleanup**: both come from
  the Phase 4 corrector and are not in the outline. Both are documented in the
  changelog and merge-and-resolve step 5.
- **The outline's "two consumers usually build identical trees"**: not
  guaranteed by the code, since consumers can hold different pins and so pick
  differently. The docs say only that they meet as an ordinary divergence at the
  later push.
- **D52 location**: see the structural deviation above.

## Lint recap

- `just format-docs`: ran after every edit round. The final run rewrapped 2
  files.
- `just lint`: `lint-shell: 138 files clean`. The last invocation reported
  cached, because `docs/` is not among its inputs.
- `just lint` does **not** run the docs graph check; `precommit` runs it
  separately. I ran `scripts/check-docs-links.py` directly and it exited 0, with
  52 decisions across 120 files. Every check was 0: broken-link,
  unstubbed-decision, stub-without-body, duplicate-decision,
  duplicate-conclusion, undefined-decision, enumeration-drift, delegation-drift
  and oversized-file.
- I also checked that no rewrap put a line starting with `N. ` into edited prose
  (one such line appeared in the new node and was reworded).
