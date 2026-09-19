# Prose/docs review fixes — Major 1, Minors 6–12

## Per fix

**Major 1 — rejected scratch alternatives recorded.**
- `docs/decisions.md:164-167` — the D17/tiered-memory *Rejected* line now ends `… · a scratch directory in the tier's gitdir · a sweep of stale `gitlore-repair.*` directories on the next repair (tier-arrival-repair.md).`
- `docs/references/tier-arrival-repair.md:190-194` — **A scratch directory in the tier's gitdir.** keeps the scratch copy inside a repository (which a killed take then strands) and needs a library-level `trap` that clobbers the caller's; `${TMPDIR:-/tmp}` strands nothing in a repo.
- `docs/references/tier-arrival-repair.md:196-201` — **A sweep of stale `gitlore-repair.*` directories on the next repair.** races a concurrent take: the directories carry no owner, so a sweep cannot tell a leftover from the copy another take is repairing in, and removing it loses that work mid-repair; the leftover is kilobytes under the system temp dir, reclaimed on its own schedule.

**Minor 6 — post-landing push failure gets its own recognised arm in both readers.**
- `agents/memory-merger.md:42` — new turn-2 branch beside the prepared-merge one: **Non-zero with `gitlore: pushing '` … `failed, and not because of divergence`** → the merge landed and the post-commit `live` advance/publish failed for a reason no merge fixes; quote the line with git's text under it and every other `gitlore:` line, including any `gitlore: tier '<t>' stays on the merge commit … Run:` remedy and its command lines; say the merge landed and the push failed; stop. "Any other non-zero" kept as the fallthrough, its explanation untouched and still true (an errexit abort after the commit carries no recognised line).
- `skills/resolve/SKILL.md:83` — matching route: the merge landed but `live` was not advanced or not published; no `rejected:`, no **Loop** (a rerun meets the same non-divergence refusal); **Summarize**, skipping **Resume commit**.
- `skills/resolve/SKILL.md:103-105` — Summarize outcome: report the merge as landed and the push as failed with git's reason; any remedy printed below it is still to run.
- `skills/resolve/SKILL.md:121-124` — closing paragraph reworked: a printed rest remedy is outstanding *whenever it was printed* — on an outcome that never reaches **Loop** as much as on one where the **Loop**'s `resolve.sh` then reports the state healthy.
- `docs/references/merge-and-resolve.md:102-108` — the enumeration of how the readers classify the continuation's exits now names the post-landing `gitlore: pushing '…' failed, and not because of divergence` arm, and says the fresh directive goes back through the loop while the push failure ends in the summary with any rest remedy still to run.
- Grounding confirmed: `scripts/resolve.sh:274-291` (`push_or_report`, rc 2 after the line), call sites `:369` and `:389`, both after the merge commit at `:337`; each rc-2 arm runs `rest_unadopted_tier` (`:227`, remedy at `:238-241`) then `exit 1`. The only other `push_or_report` calls are in `check_store_gates` (`:458`, `:479`), outside `continue-after-merge`. Nothing before the merge commit prints that line.
- Enumeration sweep: `grep -rn "unrecognised\|fate" docs/references agents skills docs/changelog docs/design.md` → only `merge-and-resolve.md:104`, `memory-merger.md:42`, `SKILL.md:84,107` and the 2026-09-18 changelog entry (a write-time record of what shipped then; left alone per the present-tense/changelog split).

**Minor 7 — both post-commit yield sites named.**
- `agents/memory-merger.md:41`, `skills/resolve/SKILL.md:82` — "a `live` push after it" → "the local `live` advance after it, or the push of `live` to `origin`". Same phrasing used in the new arm.
- `docs/references/merge-and-resolve.md` no longer carried that phrasing at HEAD (its clause is "pushes when the flavor calls for it; a push refused for any reason but divergence exits 1 once an unadopted tier is rested"), which already covers both sites. No edit needed there for this item.

**Minor 8 — node count.** `docs/references/tier-arrival-repair.md:4-5` now reads "One of the five nodes of the tiered-memory subsystem (FR15), whose entry point is [tiered-memory.md](tiered-memory.md)." Count verified: `tiered-memory.md:23` says "across this node and four siblings" and lists `index-composition.md`, `index-authoring-sync.md`, `tier-stores.md`, `tier-arrival-repair.md` at `:25-47` — so `tier-arrival-repair.md` is one of the listed siblings and five is correct.

**Minor 9 — `/tmp` fallback.** `docs/references/tier-arrival-repair.md:35-37` "in a `mktemp -d` directory under `$TMPDIR` or, where that is unset, `/tmp`"; `docs/changelog/2026-09-18-…:18-19` "under `$TMPDIR` — or `/tmp` where that is unset".

**Minor 10 — the fourth remedy.** `docs/references/tier-arrival-repair.md:90-96` — the retry-refusal description now closes "with the walk-back's default remedy, `Fix the store, then run /gitlore:merge again.` — the store is what needs fixing here, unlike the transient arms above." Byte-exact against `scripts/lib/resolve.sh:2152` (`local remedy="${5:-Fix the store, then run /gitlore:merge again.}"`), reached because `:2082` passes an empty remedy.

**Minor 11 — one statement of the refused `live` advance.** The duplicate sentence at the old `:56-57` is gone; the walk-back paragraph (`tier-arrival-repair.md:57-66`) now carries the whole arm: it prints its failure line and the full refusal, walks back to the pin, the take exits 1, and "a refused advance leaves the repair commit unreachable, the tier on its pin and `live` on the arrival".

**Minor 12 — weld-tail case.** `docs/changelog/2026-09-18-…:29-32` — "leaves its output unterminated only when what is last is the input's own unterminated last line, or that line's tail after a weld split", matching the comment at `scripts/lib/index-compose.sh:355-358`.

## Also fixed (verified stale claim in a file I own)

`docs/references/merge-and-resolve.md:82-83` said the sub-agent "runs `git add -A`". The merger has staged by explicit path since `c1730f2` and `agents/memory-merger.md:29` forbids `git add -A`. Now: "stages by explicit path in the store the state file names".

## Test assertions affected

None. `grep -rn "memory-merger.md\|resolve/SKILL.md" tests/` hits only `tests/plugin_distribution.bats:35` and `:117`, which assert on frontmatter alone (`name:`, `tools:` vs `allowed-tools:`, no `SendMessage`, and the `gitlore: memory merge prepared` marker inside the skill's `description:`). No frontmatter was touched, and the `description:` line is unchanged.

## Verification run

- `just format-docs` → rc 0 (rumdl pin matched; it rewrapped the edited `docs/` files; the "Found 39 issues in 11/196 files" line is pre-existing MD013 residue in `plans/`, unrelated).
- `python3 scripts/check-docs-links.py` → rc 0; all nine counters zero, including `enumeration-drift` and `oversized-file`.
- `wc -l`: `tier-arrival-repair.md` 201, `merge-and-resolve.md` 378, `decisions.md` 175, `SKILL.md` 124, `memory-merger.md` 57, changelog entry 46. None crossed 400.
- `git status --short -- docs agents skills` → exactly the six intended files modified, nothing else.

## Not done

Nothing outstanding. No commit, no staging, no branch change, no suite run, per the dispatch.
