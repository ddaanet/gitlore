# The memory index is over the loader cap, and curation cannot close it

Decision brief. Two sweeps have now looked for entries to retire; both came
back nearly empty, while the index grew faster than either freed. The question
left is structural, and it is my human partner's.

## What is measured

`memory/MEMORY.md` is 27,722 bytes. Claude Code's loader stops at ~24,985
bytes (24.4 KB), so the last 2,737 bytes never reach a session. The session
that wrote this one carries the harness's own warning to that effect.

Ten entries sit entirely past the cutoff and have been invisible in every
session for about two weeks:

- Agent hooks need exact trust key
- Named dispatch drops frontmatter hooks
- Guard safety visible in the pattern
- Guardrails must permit real commands
- Verify restart before structural diagnosis
- Parse, don't regex, structured formats
- jq index is bytes, slices are codepoints
- subagent skips @-import expansion
- git subtree ensure_clean unscoped
- skill eval must exercise the trigger

The eleventh casualty is the tail of *Shape rules are not duplication*, cut
mid-hook.

Two things about that list matter more than its length. It is the **newest**
facts — the ones least internalized, most likely to be re-learned the hard
way. And it ends with the one **project-local** entry, because composition
orders tier blocks first and gitlore's own lines last, so this repo's facts
are structurally the first to fall off.

## Why curation will not fix it

Index size across recent commits:

| date | bytes |
| --- | --- |
| 2026-08-13 | 24,274 |
| 2026-08-15 | 26,219 |
| 2026-08-20 | 26,602 |
| 2026-08-25 | 27,046 |
| 2026-08-27 | 27,722 |

That is +3,448 bytes in fourteen days, about 246 bytes — a little over one
entry — per day. The cap was crossed around 2026-08-13.

Against that, what curation has actually returned:

- **Sweep B** (`plans/sweep-b-ownership-audit.md`, 2026-08-25) classified all
  100 tier files and found **2 retirements and 2 relocations, 754 bytes**. All
  four have since been applied — none of those four slugs exists any more.
  Growth ate that 754 bytes back within 48 hours, four times over.
- **The budget survey** (`plans/2026-08-27-memory-index-budget-survey.md`)
  sampled ~20 entries and found **~245 bytes** in two merge candidates, and
  reported the acted-inline relocation well as dry.
- **The retirement sweep** (`plans/2026-08-27-memory-index-retirement-sweep.md`)
  returned **zero** further candidates. It reports itself honestly: its first
  pass re-classified 85 files from scratch before reading Sweep B, so that pass
  is redundant re-derivation rather than independent confirmation. What it adds
  over Sweep B is a delta — Sweep B's four actions are already executed and
  already inside the 27,722-byte baseline, three further facts were merged into
  `memory-writing.md` the day after, and the nine files created since
  2026-08-25 that no ownership audit had seen are all KEEP with a stated check.

One lever it does surface: the two upstream proposals Sweep B left open —
pushing the `GIT_INDEX_FILE` save/restore and the `160000` gitlink symptom into
the `shell-scripting:shell-gotchas` skill — have still not landed. Verified
here against the installed skill at v0.3.2: `grep -rl 'index.lock'` and
`grep -rl '160000'` over its files both return nothing. If they land,
`git-hook-env-leak` (301 B) and `submodule-escape-to-parent` become retirable,
which is roughly 500 bytes — under a fifth of the gap, and it depends on
another repo, so it is a proposal to make rather than a plan to count on.

The store is not carrying dead weight. It is carrying about 190 bytes per
fact, roughly 103 facts, and gaining one a day.

## The options

1. **Reorder composition so tier blocks come last.** Costs nothing and frees
   nothing, but it changes *which* entries are dropped: gitlore's own
   project-local facts and the newest entries stop being the sacrificial tail.
   A mitigation, not a fix, and gitlore already owns this code.
2. **Sub-scope the `ddaanet` tier.** The tier-wide-vs-sub-scoping fork that
   `plans/memory-hygiene-sweep.md` deliberately left open. One index carrying
   every fact for all 17 mounting repos is what makes the budget binding; a
   repo mounting only the tiers it needs is the structural answer. This is the
   real fix and the largest piece of work.
3. **Raise gitlore's own advisory budget and accept the overage**, treating
   the ~24.4 KB loader cap as the thing to push back on upstream. Honest about
   where the constraint lives, but leaves facts silently dropped meanwhile.

Recommendation: **1 now, 2 as the next real subproject.** Reordering removes
the worst property of the current failure — that the tail is exactly the set
of facts a session has least chance of already knowing — while the sub-scoping
decision is taken on its merits rather than under byte pressure.

What should not happen is another shortening pass. Both governing memories say
so, and the measurement behind them holds: rewriting fact bodies moved the
index ~2%, and the last trim damaged about a fifth of the lines it touched.
