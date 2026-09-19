# Deliverable review — AGENTIC-PROSE and HUMAN-DOCS, `tier-arrival-review-minors`

Scope: the prose half of the job (`agents/memory-merger.md`, `skills/resolve/SKILL.md`) and its docs (`docs/references/tier-arrival-repair.md`, `tier-stores.md`, `merge-and-resolve.md`, `git-hooks.md`, `commit-gate.md`, `index-authoring-sync.md`, `docs/changelog.md` and the new entry file). Baseline: `plans/tier-arrival-review-minors/runbook.md` Items 6.1 and 7.1–7.5, with `outline.md` where the runbook is silent. Job range `3502a86..00584a1`; every finding re-verified against HEAD (`da6f651`), and every quoted message checked with `grep -n` against `scripts/resolve.sh` and `scripts/lib/resolve.sh`.

Allow-list verification, Item 6.1's central contract: the two readers split the continuation's outcomes identically — exit 0 / merged-index line / message-file, build or refused-commit line / `gitlore: memory merge prepared` / any other non-zero — and nothing falls through to a landing claim in either. Every string they key on is a byte-exact prefix of what the harness prints (`scripts/resolve.sh:148`, `:322`, `:333`, `:339`; `scripts/lib/resolve.sh:648`). No finding against the split itself.

## Critical

None.

## Major

### 1. The rejected scratch-sweep alternative is recorded nowhere

- **Files:** `docs/decisions.md:151-166` (the D17 *Rejected* line), `docs/references/tier-arrival-repair.md:154-187` (the node's `## Rejected alternatives`).
- **Axis:** conformance / completeness (human docs).
- **Description:** the design rejected an alternative for the scratch-directory move — `outline.md` Phase 6, item 7: "*Rejected:* sweeping stale `gitlore-repair.*` directories on the next repair. It races a concurrent take." It appears in neither the decisions index nor the node. `docs/decisions.md:161-167` lists seven rejected alternatives for `tier-arrival-repair.md` and this is not among them; the node's section carries the same seven. The project's own rule is that `docs/decisions.md` holds "every rejected alternative by name" and the node holds the argument, so a future session weighing a stale-scratch sweep finds nothing saying it was considered and why it loses. The runbook's Phase 7 items do not assign this, so the gap is inherited from the runbook rather than introduced against it — but the outline states the rejection and the deliverable is where it belongs.
- **Grounding:** `scripts/lib/resolve.sh:2018` `if ! scratch=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"); then` — the decision the rejection attaches to, shipped with no recorded counterfactual.

### 2. The rest remedy is reachable only through the landed-merge branch, but it arrives on an exit 1

- **Files:** `skills/resolve/SKILL.md:84`, `:107-108`, `:113-119`.
- **Axis:** functional completeness / consistency (agentic prose).
- **Description:** a continuation whose post-landing push is refused for a reason other than divergence rests the unadopted tier and exits 1 after printing `gitlore: tier '<t>' stays on the merge commit … Run:` and the command lines under it. Item 6.1 deliberately puts that exit in the unrecognised bucket (the runbook names the `not because of divergence` exit as one that "claims nothing by itself"), and `:84` routes it to **Summarize**, where `:107-108` says to relay it "as a state to inspect, not a landing to report". But the paragraph that tells the agent those printed command lines are *still to run* — `:117-119` — was rescoped by this job to `:113` "**On a landed merge**, any other `gitlore:` line …", so on the one exit that actually prints that remedy the instruction no longer applies. The agent relays the text verbatim and never states the remedy is outstanding, while `docs/references/tier-stores.md:211-214` and `tier-arrival-repair.md:144-152` document it as a fully specified outcome whose remedy must be run. The two halves of the same skill now describe the same exit differently.
- **Grounding:** `scripts/resolve.sh:346-349` — `rc` 2 from `push_or_report` runs `rest_unadopted_tier` then `exit 1`; `scripts/lib/resolve.sh:243-253` prints the `stays on the merge commit … Run:` remedy on that path.
- **Suggested fix:** either detach the `A printed remedy …` paragraph from the landed-merge sentence, or give the rest remedy its own recognised-line arm in both readers (`gitlore: tier '` + `' stays on the merge commit` is a stable prefix).

## Minor

### 3. "a `live` push after it" names only one of the two yield sites

- **Files:** `agents/memory-merger.md:41`, `skills/resolve/SKILL.md:82`, `docs/references/merge-and-resolve.md:103`.
- **Axis:** constraint precision.
- **Description:** all three explain `gitlore: memory merge prepared` as the product of "a `live` push after it". The continuation has two post-commit yield sites: the local `HEAD:live` advance and, for `head-vs-remote`, the `origin live` push. The second is a push *of* `live` rather than a push *to* `live`, so the phrasing is at best ambiguous about the flavor it names. Routing is unaffected (both yields print the same directive and both go to **Loop**), which is why this is Minor.
- **Grounding:** `scripts/resolve.sh:345` `rc=0; push_or_report "$mempath" . HEAD:live || rc=$?` → `:347 gitlore_yield_merge "$mempath" live head-vs-live HEAD`; `scripts/resolve.sh:370` `rc=0; push_or_report "$mempath" origin live || rc=$?` → `:373 gitlore_yield_merge "$mempath" origin/live head-vs-remote live`.

### 4. The D52 node is the only subsystem node that does not state the node count

- **File:** `docs/references/tier-arrival-repair.md:4-5` — "One of the nodes of the tiered-memory subsystem".
- **Axis:** consistency (M19).
- **Description:** M19 made `index-authoring-sync.md:5` read "One of the five nodes", matching `index-composition.md:4-5`. `tier-arrival-repair.md` — the node this job spent most of its docs budget on — still says "One of the nodes", and the runbook's own sweep (`rg -n 'of the (four|five) nodes|four sibling'`) cannot see it because it carries no numeral. `tier-stores.md:3-6` legitimately opts out with a standalone-reading note; this node does not.
- **Grounding:** `docs/references/tiered-memory.md:23` "across this node and four siblings", with the four listed at `:25-45`.

### 5. The scratch location claim omits the `/tmp` fallback

- **File:** `docs/references/tier-arrival-repair.md:35-36` — "in a `mktemp -d` directory under `$TMPDIR`".
- **Axis:** accuracy.
- **Description:** the location is `${TMPDIR:-/tmp}`, so on an environment with no `TMPDIR` the scratch copy is under `/tmp`. The node's own point — outside the repository, so a killed take leaves nothing in a repo — holds either way, but a reader looking for a stale directory is told the wrong place half the time. `docs/changelog/2026-09-18-…:18-19` carries the same abbreviation.
- **Grounding:** `scripts/lib/resolve.sh:2018` `mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"`.

### 6. The retry-refusal arm's remedy wording is no longer stated anywhere in `docs/`

- **File:** `docs/references/tier-arrival-repair.md:91-94`.
- **Axis:** completeness (Item 7.4's sweep).
- **Description:** the node now quotes three remedies verbatim — `Run /gitlore:merge again.` (`:66`), `Once the index is fixed where it was published, run /gitlore:merge again.` (`:99`) and the both-fixes line (`:102`) — but the fourth, the default that a retry refused on root, the manifest or another tier still emits, appears in no node. `grep -rn "Fix the store, then run" docs/ skills/` returns only `docs/changelog/2026-09-18-…:7`, and there it reads as wording that was *removed*. A reader meeting `Fix the store, then run /gitlore:merge again.` in real output finds the phrase only in a changelog sentence saying it was wrong.
- **Grounding:** `scripts/lib/resolve.sh:2087` passes an empty remedy, and `:2146` defaults it: `local remedy="${5:-Fix the store, then run /gitlore:merge again.}"`.

### 7. Two adjacent paragraphs describe the refused `live` advance at different completeness

- **File:** `docs/references/tier-arrival-repair.md:55-57` against `:59-67`.
- **Axis:** consistency.
- **Description:** `:56-57` still says a refused `live` update leaves "the tier on its pin and `live` on the arrival, and the take exits 1 with git's message", while the paragraph immediately below now says that arm also prints the full refusal under the root-index header and closes with `Run /gitlore:merge again.`. Both are true; read in order, the first reads as the whole behaviour and the second as a correction of it. Folding the arm's mention at `:56-57` into a pointer at `:59` would leave one statement of it.
- **Grounding:** `scripts/lib/resolve.sh:2068-2075` — the push arm prints its own line, then `gitlore_adopt_report_refusal_and_walk_back … "Run /gitlore:merge again."`.

### 8. The changelog's terminator rule drops the weld-tail case

- **File:** `docs/changelog/2026-09-18-repair-and-continuation-failures-say-what-they-left.md:28-29` — "leaves its output unterminated only when the input's own unterminated last line is still last".
- **Axis:** accuracy.
- **Description:** the implemented rule also keeps the output unterminated when what is last is that line's *tail* after a weld split, which the code comment states explicitly. A summary entry may compress, but this sentence reads as the full rule and the omitted case is the one a reader would not guess.
- **Grounding:** `scripts/lib/index-compose.sh:355-358` — "tagged follows the input's last line, or that line's tail after a weld split — the one element termination can hinge on".

## Fixed since

None. Every finding above is present at HEAD. The later work in `00584a1..HEAD` touched all four prose/doc surfaces (the `index_problems` briefing, explicit-path staging, the denied-call branch in both readers, the killed-take residual in `tier-stores.md`) but corrected nothing this job left; the denied-call branch was added on both sides at once, so the allow-list parity Item 6.1 established still holds at HEAD.

## Requirement coverage

| Req | Verdict | Where at HEAD | Note |
|---|---|---|---|
| M14 — merger states rule 1 | covered | `agents/memory-merger.md:28` | "no two bullets naming the same path", in step 6's rule list, matching `gitlore_compose_check_index`'s duplicate rule (`scripts/lib/index-compose.sh:289-291`) |
| M15 (prose half) — allow-list on continuation exits | covered | `agents/memory-merger.md:37-45`; `skills/resolve/SKILL.md:80-84`, `:98-108` | five-way split identical on both sides; every keyed string byte-exact against `scripts/resolve.sh:148,322,333,339` and `scripts/lib/resolve.sh:648`; nothing falls through to a landing claim. See Major 2 for the rest-remedy consequence and Minor 3 for the `live`-push phrasing |
| M16 — git-hooks dirtiness clause | covered | `docs/references/git-hooks.md:161-163` | exact wording the runbook specifies; matches the commit path's changed-file scoping |
| M17 — tier-arrival-repair opening tense | covered | `docs/references/tier-arrival-repair.md:20-30` | "Left unrepaired, it wedges the tier"; present tense, no correction framing |
| M18 — tier-stores dangling "instead" | covered | `docs/references/tier-stores.md:211-212` | "It prints the remedy — fix the store and run `/gitlore:merge` —" |
| M19 — node count | partial | `docs/references/index-authoring-sync.md:5` (covered); `docs/references/tier-arrival-repair.md:5` (uncounted) | five is the right count: `tiered-memory.md` plus the four siblings it lists at `:25-45`. `tiered-memory.md:5,23` correctly keep "four siblings". See Minor 4 |
| M20 — changelog dangling "other" | covered | `docs/changelog.md:38` | "refused for any reason but divergence"; agrees with the 2026-09-15 entry `:55` and with `tier-stores.md:211`, `merge-and-resolve.md:94`, `tier-arrival-repair.md:146` |
| M21 — commit-gate off-pin tier remedy | covered | `docs/references/commit-gate.md:57-61` | "a checkout or take, for an off-pin tier" matches the refusal's own remedy at `scripts/lib/index-compose.sh:586,599` (`checkout --detach <pin>`, then `/gitlore:merge`) |
| 7.2 — D52 mechanism (scratch, publication pass, remedies, walk-back) | covered | `docs/references/tier-arrival-repair.md:35-36`, `:59-67`, `:91-105`, `:107-116` | scratch outside the repo (`lib/resolve.sh:2018`); all seven transient arms print the header and `Run /gitlore:merge again.` (`:2020,2066,2072,2077`); both-fixes remedy byte-exact against `:2052`; walk-back `what arrived` / `the repair` against `:2147` and the two `the repair` call sites `:2077,2087`; post-loop pass against `lib/resolve.sh:1509-1524`. Minor 5, 6, 7 are precision gaps inside this item |
| 7.3 — tier-stores alignment | covered | `docs/references/tier-stores.md:175-182`, `:211-214` | the walk-back enumeration now names the `live`-advance and checkout-follow arms and what `live` keeps in each; no stale scratch-location or behind-arm-publication claim remains in the node |
| 7.4 — quote and mechanism sweep | covered | — | `grep -rn` over `docs/` and `skills/` for `keeps what arrived` (0 hits), `Fix the store, then run` (changelog only — Minor 6), `not because of divergence` (changelog only; the shipped wording is at `lib/resolve.sh` via `gitlore_report_tier_push_failure`), `the merge was not committed` (6 hits, all byte-exact), `both push arms` (0 hits), `gitdir` near `repair` (changelog only). `docs/design.md:45-54,199-200` and `docs/decisions.md:138-167` carry no claim contradicting the changed nodes on the scratch location, the post-loop pass, the `Run /gitlore:merge again.` remedy or the walk-back — but they also carry no record of the sweep's rejected alternative (Major 1) |
