# Recall log analysis, rerun with native recall counted

Rerun of `plans/2026-09-02-recall-log-analysis.py` on 2026-09-21, nineteen days
after `CLAUDE_MEMORY_STORES=1` opened native recall on this machine. Classes and
caveats are those of `plans/2026-09-02-recall-log-analysis.md`; this file holds
only what the rerun adds. Rerun with
`python3 plans/2026-09-02-recall-log-analysis.py`.

## Corpus

| transcripts | user turns | turns with a recall skill call | span |
| ----------- | ---------- | ------------------------------ | ---- |
| 4780 | 18450 | 19 | 2026-W26 to 2026-W39, CC 2.1.187 to 2.1.272 |

The corpus is not a superset of the 2026-09-02 one. Weeks W31, W32 and W34 are
absent, W33 holds 110 deliveries where it held 517, and W26 to W29 are new. The
cause was not investigated; week-to-week comparison with the earlier run is
unsafe for anything before W35. W35 matches exactly (314).

Attachments seen: 831 `relevant_memories`, 308 `file`, 436 `nested_memory`.

## Class totals

| class | Read | Bash read | total | of which in subagents |
| ----- | ---: | --------: | ----: | --------------------: |
| harness | 1994 | | 1994 | 0 |
| spontaneous | 14 | 19 | 33 | 0 |
| manual | 269 | 335 | 604 | 452 |
| active | 432 | 776 | 1208 | 62 |
| reattach | 69 | | 69 | 0 |
| bash-other (not a read) | | 414 | | |

831 attachments deliver 1994 fact bodies, 2.4 per attachment.

## Class totals by ISO week, since the gate opened

| week | harness | spontaneous | manual | active | reattach | total |
| ---- | ------: | ----------: | -----: | -----: | -------: | ----: |
| 2026-W36 | 376 | 0 | 121 | 299 | 3 | 799 |
| 2026-W37 | 598 | 1 | 162 | 121 | 0 | 882 |
| 2026-W38 | 976 | 0 | 112 | 202 | 1 | 1291 |
| 2026-W39 | 44 | 0 | 4 | 12 | 0 | 60 |

W39 is one day. Over W36 to W39 the harness is 1994 of 3032 deliveries, 66%;
active reads are 634, 21%; manual 399, 13%.

## Findings

- **Native recall is the main delivery path.** Two thirds of fact bodies
  reaching a context since the gate opened arrive as `relevant_memories`
  attachments, none of them in a subagent.
- **The `gitlore:recall` skill firing on its own has stopped**: one spontaneous
  delivery in the four weeks since the gate opened, against 29 in W35 alone.
  Whether the harness satisfies the moments the skill used to catch, or the
  skill's trigger is simply losing to it, the counts do not say.
- **Active reads continue at the earlier rate** — 634 over W36 to W39, about 200
  a week, against 194 in W35 — so native recall adds deliveries rather than
  replacing the model's own trips to the store.
- **Subagents get memory only by being told**: 452 of 604 manual deliveries are
  in subagents, and the harness delivers none there.
- **Coverage is now near-total.** One of the 68 current facts was never read
  (`ddaanet/token-counting.md`), against 20 of 101 on 2026-09-02. The harness
  accounts for it: the twelve least-read facts are almost all harness-only
  deliveries of one to three.

## Most-read facts

| fact | harness | spontaneous | manual | active | reattach | total |
| ---- | ------: | ----------: | -----: | -----: | -------: | ----: |
| ddaanet/gitlore-tier-merge-direction.md | 93 | 1 | 10 | 20 | 0 | 124 |
| ddaanet/no-stderr-suppression.md | 102 | 0 | 4 | 10 | 0 | 116 |
| micro:ghmem-project.md | 5 | 0 | 25 | 80 | 0 | 110 |
| ddaanet/hook-output-channels.md | 30 | 2 | 24 | 35 | 0 | 91 |
| ddaanet/commit-bundling.md | 78 | 0 | 4 | 8 | 0 | 90 |
| ddaanet/green-is-not-evidence.md | 12 | 1 | 41 | 32 | 0 | 86 |
| ddaanet/shared-claude.md | 6 | 0 | 17 | 56 | 0 | 79 |
| ddaanet/git-hook-env-leak.md | 59 | 0 | 10 | 8 | 0 | 77 |
| ddaanet/sandbox-effects.md | 25 | 0 | 8 | 40 | 0 | 73 |
| ddaanet/claude-plugin-dev.md | 31 | 0 | 13 | 27 | 1 | 72 |
| ddaanet/bash-tool-set-e-inert.md | 66 | 0 | 2 | 1 | 0 | 69 |
| ddaanet/design-doc-writing.md | 23 | 1 | 20 | 25 | 0 | 69 |

The harness has favourites of its own: `no-stderr-suppression`,
`gitlore-tier-merge-direction`, `commit-bundling`, `bash-tool-set-e-inert` and
`git-hook-env-leak` are delivered 59 to 102 times each and model-read ten times
or fewer. `commit-bundling` and `bash-tool-set-e-inert` were among the
least-read facts on 2026-09-02. Whether those deliveries are relevant or the
retriever matching on common vocabulary is not measured here; it is the question
a precision sample of `relevant_memories` attachments would answer.
`shared-claude.md` is in every context through the CLAUDE.md import, so its 79
deliveries, six by the harness, are redundant.

## Least-read current facts

| fact | harness | manual | active | reattach | total |
| ---- | ------: | -----: | -----: | -------: | ----: |
| ddaanet/codex-review-of-design-docs.md | 1 | 0 | 0 | 0 | 1 |
| ddaanet/perf-fix-check-parallelism-assumption.md | 1 | 0 | 0 | 0 | 1 |
| ddaanet/session-title-customtitle.md | 1 | 0 | 0 | 0 | 1 |
| ddaanet/todo-tool-flag-gated.md | 1 | 0 | 0 | 0 | 1 |
| ddaanet/cc-project-dir-encoding.md | 1 | 1 | 0 | 0 | 2 |
| ddaanet/cc-worktree-bash-guard.md | 2 | 0 | 0 | 0 | 2 |
| ddaanet/claude-project-dir.md | 0 | 0 | 2 | 0 | 2 |
| ddaanet/jq-index-bytes-vs-slice-codepoints.md | 2 | 0 | 0 | 0 | 2 |
| ddaanet/bash-prolog-common-foundations.md | 2 | 1 | 0 | 0 | 3 |
| ddaanet/detect-liveness-not-presence.md | 3 | 0 | 0 | 0 | 3 |
| ddaanet/git-config-multivalued-read.md | 2 | 0 | 0 | 1 | 3 |
| ddaanet/guard-reveals-singleton.md | 2 | 0 | 0 | 1 | 3 |

## Caveat added by this run

The 2.1.209 recall-Read shape matches 54 active reads, from 2.1.187 to 2.1.272,
six of them on 2.1.258 or later, the versions that carry native recall. It stays
the upper bound on harness reads misfiled as active.
