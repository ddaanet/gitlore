# Memory index retirement sweep — delta on Sweep B

Read-only. No file outside this one was written, edited, or deleted, and
**no retirement is executed by this report** — per the repo's own decided
plan (`memory-hygiene-sweep.md`: "B proposes, never executes. Retiring a
shared-tier fact removes it from every ddaanet repo."). This supersedes my
own earlier pass in this file, which re-derived a fresh classification
without having read `sweep-b-ownership-audit.md` first — that audit already
did the exhaustive ownership classification (2026-08-25) this report builds
on instead of repeating.

`memory/MEMORY.md` is 27,722 B today against Claude Code's ~24,985 B
loader cap — need to shed ≥ 2,800 B.

## 1. What Sweep B already decided, and its current execution state

Sweep B (2026-08-25) classified all 100 then-existing ddaanet fact files and
reached **retire 2 + relocate 2 + keep 96**, totaling **754 B** if executed
(shell-gotchas-on-review 244 B, run-the-gate-not-a-suite-subset 197 B,
skill-vs-command 172 B, verify-session-root 141 B), against an index it
measured at 24,722 B at the time.

**All four have already been executed.** Confirmed directly:

- `memory/ddaanet/shell-gotchas-on-review.md`,
  `run-the-gate-not-a-suite-subset.md`, `skill-vs-command.md`,
  `verify-session-root.md` — none exist (`[ -f memory/ddaanet/<name>.md ]` fails
  for all four).
- None of the four slugs appear anywhere in the current `MEMORY.md`
  (`grep` returns no hits) — their index lines are gone.
- The two relocation targets' content is live in `shared-claude.md`, verbatim:
  `shared-claude.md:43` "**Run the repo's precommit gate before committing**,
  unprompted" and `shared-claude.md:45` "**After a compaction, verify the
  session root before acting.**" `skill-vs-command`'s rule is also present,
  at `shared-claude.md:129` ("**Self-triggering skill when the condition is
  mechanical and detectable**").

So **this 754 B is not available to claim today** — it is already baked
into the current 27,722 B baseline, not a pending action. Sweep B's own
retire+relocate list produces **zero further bytes**; it is done.

**Three more files vanished since Sweep B that its written verdicts never
named as retire or relocate targets**: `tier-links-cross-a-boundary.md`,
`tier-routing-plugin-shaped.md`, and `shared-trigger-means-merge.md` — all
three were in Sweep B's own "keep" lists, not its retire/relocate table.
They are gone from `memory/ddaanet/` today, and their content now lives
inline in `memory-writing.md`'s "Which tier the fact belongs in", "Links
when a fact routes up", and "A new file, or a section in one that exists"
sections respectively — `memory-writing.md`'s own frontmatter
`modified: 2026-08-26T19:24:25Z`, one day after Sweep B, confirms the
merge-in happened right after the audit, evidently already following its
"which tier"/"same-WHEN merge" logic on itself. This is a second batch of
already-executed consolidation Sweep B's table doesn't show, also already
reflected in the current 27,722 B baseline — not newly available.

**Net for ask (1): nothing Sweep B decided is retirable *today* that isn't
already retired.** Its analysis produced no undiscovered implication beyond
its own table — I checked the partial-overlap keeps and the three
skill-override keeps for a stronger reading than Sweep B gave them (below)
and found none.

## 2. Keep-because-unowned entries where an owner has since appeared

Sweep B named two open upstream proposals that would make two entries
retirable later: push the `GIT_INDEX_FILE` save/restore symptom and the
bogus `160000` gitlink symptom into `shell-scripting:shell-gotchas`. Checked
directly against the skill's current shipped content (source repo
`/Users/david/code/shell-gotchas`, tag `0.3.2` — same content as the
installed plugin cache):

- **`git-hook-env-leak`** — still not covered.
  `shell-gotchas/references/environments.md:27` covers a different, narrower
  case ("during a partial commit, `GIT_INDEX_FILE` points to a *temporary*
  index; a hook that unsets it and runs `git add` stages into the real index
  instead"). The distinctive half Sweep B flagged — saving and restoring
  `GIT_INDEX_FILE` around a staging `git add`, and the
  `Unable to create '.git/index.lock': File exists` symptom — is still absent:
  `grep -iF index.lock` over the skill's three reference files returns zero
  hits. **KEEP stands, unchanged.**
- **`submodule-escape-to-parent`** — still not covered. `grep -rn 160000`
  over the skill returns zero hits; the bogus-gitlink symptom Sweep B named
  as uncovered is still uncovered. **KEEP stands, unchanged.**

Also re-verified the three skill-override keeps, since "an installed skill
states the contrary rule" is exactly the kind of thing a skill update could
resolve:

- `skill-description-purpose-first` vs `writing-skills` — superpowers 6.3.0
  (currently cached, `superpowers@claude-plugins-official` enabled) still has
  at `SKILL.md:150`: "**CRITICAL: Description = When to Use, NOT What the
  Skill Does**". **Unchanged, still overridden, KEEP.**
- `plan-contracts-not-full-code` vs `writing-plans` — same 6.3.0
  `SKILL.md:136,138` still lists "Write tests for the above" (without actual
  test code)" as a defect and requires "code blocks required for code steps".
  **Unchanged, KEEP.**
- `imperative-form-scope` vs `skill-development` —
  `plugin-dev@claude-plugins-official` enabled, cached
  `skill-development/SKILL.md:160` still states "Write the entire skill using
  **imperative/infinitive form** … not second person". **Unchanged, KEEP.**

Also re-checked the two-live-skills argument that reversed the tmux cluster's
retirement: `grep -rl tmux` over the installed `handoff` plugin's skill tree
still hits `autoname`, `handoff`, `precompact`, and `restart` — all four
still ship in the currently-cached `handoff` versions, and `handoff@ddaanet`
is enabled. **`cc-tui-tmux-driving` and `tmux-test-isolation` stay KEEP,
unchanged.**

**Net for ask (2): no owner has appeared for anything Sweep B marked
keep-because-unowned or keep-because-overridden.** Zero bytes here.

## 3. Entries Sweep B never saw at all

Sweep B's audit covered exactly its 100-file snapshot. Diffing that snapshot
against the current 98-file directory (`comm` on sorted basename lists)
turns up **9 fact files created since 2026-08-25 that no ownership pass has
ever classified**:

| File | Index bytes | Candidate owner checked | Verdict |
| --- | --- | --- | --- |
| `bash-tool-set-e-inert` | 225 | `shell-scripting:shell-gotchas` (`references/robustness.md` "Exit status and `set -e`" section) | KEEP — partial overlap only. The skill covers `set -e` blind spots in *constructs* (command substitution, non-final pipeline stages, `grep` no-match); this fact's distinctive claim — that the whole Bash **tool command** runs inert because the harness's own wrapper evals it as a non-final element of an outer `&&` chain (`bash -c "... && eval '<command>' && pwd -P ..."`) — is a harness-internal mechanism the skill has no way to know about and doesn't mention. |
| `cc-async-task-notification-quirks` | 294 | none — CC-harness-internal | KEEP — no skill or hook states this. |
| `git-subtree-ensure-clean-unscoped` | 240 | `claude-plugin-dev` toolkit's own docs | KEEP — the toolkit is another repo's project-local docs, not a tier-wide owner under Sweep B's own rule. |
| `gitlore-memory-administration-no-parent-commit` | 316 | gitlore's own `docs/`/`CLAUDE.md` | KEEP — same class as Sweep B's existing "gitlore/ddaanet product facts; only coverage is project-local" bucket (`preflight-excludes-memory-submodule` et al.); project-local coverage is explicitly disqualified as an owner. |
| `gitlore-placeholder-remote-is-by-design` | 305 | gitlore's own `docs/` | KEEP — same bucket as above. |
| `jq-index-bytes-vs-slice-codepoints` | 295 | `shell-scripting:shell-gotchas` | KEEP — the skill's reference files mention `jq` nowhere near this claim; no jq-indexing content found. |
| `markdown-formatter-choice` | 317 | gitlore's own `justfile`/docs | KEEP — gitlore-specific tooling decision, project-local only, same bucket as the product-facts group. |
| `spec-enumerations-need-rederiving` | 251 | `shared-claude.md`, `superpowers` review skills | KEEP — no owner states this review-methodology rule. |
| `subagent-skips-at-import-expansion` | 215 | none — CC-harness-internal | KEEP — no skill or hook states this. |

None of the nine found an owner; total is **0 bytes newly retirable**, but
they are now on record as classified (previously they were simply outside
every audit's scope) — nine more entries that would need re-checking on any
future retirement pass.

## Cumulative total

| Source | Bytes freed |
| --- | --- |
| Prior budget survey's two merge candidates (unexecuted) | ~245 B |
| Sweep B's retire+relocate (already executed, baked into current 27,722 B) | 0 B (not newly available) |
| Sweep B's re-verified upstream-proposal keeps (§2) | 0 B (proposals not yet landed) |
| Nine previously-unclassified new entries (§3) | 0 B (all KEEP) |
| My own prior 85-file re-derivation in this file's previous version | 0 B (superseded by this delta; see note below) |
| **Total identified against the 2,800 B target** | **~245 B (~9%)** |

The ~2,555 B shortfall is unchanged by this delta pass. Sweep B already
found the two cheap retirements and both are spent. The remaining paths, per
Sweep B's own conclusion, are pushing the two named upstream proposals into
`shell-scripting:shell-gotchas` (still open, still would only free two
entries' worth once landed), reopening whether relocation to
`shared-claude.md` still has headroom despite the prior pass's "well is dry"
finding, or accepting the overage as a decision for the team lead.

## Note on my own prior pass

The version of this report before this message re-derived ownership/mechanism
verdicts for 85 files from scratch, in ignorance of Sweep B, and reached the
same "everything KEEP" conclusion by a different and much more expensive
route (three parallel forked agents doing fresh evidence-gathering). Its
per-file verdicts are not wrong — cross-checking a sample against Sweep B's
table shows agreement everywhere they overlap — but the exercise was
redundant with Sweep B's already-completed classification and produced no
finding Sweep B hadn't already made. This version replaces it.
