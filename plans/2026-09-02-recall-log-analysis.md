# Recall log analysis, rerun with native recall accounted for

Analysis input for the index-budget decision and the ddaanet curation pass.
Produced by `plans/2026-09-02-recall-log-analysis.py` over every transcript
under `~/.claude/projects/-Users-david-code-*/` (main sessions, `subagents/`,
`archived/`) on 2026-09-02. Rerun with
`python3 plans/2026-09-02-recall-log-analysis.py`.

## Corpus

| transcripts | user turns | turns with a recall skill call | span |
| ----------- | ---------- | ------------------------------ | ---- |
| 2710 | 12186 | 26 | 2026-W30 to 2026-W36, CC 2.1.215 to 2.1.258 |

## Classes

A delivery is one memory fact body entering one context.

- **harness**: a `relevant_memories` attachment, the CC 2.1.258 native recall
  shape described in `docs/references/cc-memory-retrieval.md`. Zero in the
  corpus, which is the expected reading: the gate (`tengu_moth_copse` or
  `CLAUDE_MEMORY_STORES`) was off on this machine for the whole span. It was
  opened on 2026-09-02, after this run, by setting `CLAUDE_MEMORY_STORES=1`
  in the settings `env` block, and the first attachment landed the same day.
  A rerun will count the class.
- **spontaneous**: a Read or Bash read after a `Skill(gitlore:recall)` call, or
  a `/gitlore:recall` command, earlier in the same user turn.
- **manual**: the user's prompt for that turn names recall or the file.
- **active**: any other model-issued Read or Bash read.
- **reattach**: a `file` attachment of a memory path. No user prompt in the
  corpus @-mentions a memory file, so all of these are post-compaction
  re-attachment of a file read before the compaction, not recall.

Bash reads are a command containing `cat`, `sed`, `head`, `tail`, `bat`,
`less` or `awk` together with a memory path, and are folded into the per-file
counts. Bash commands that only name a fact (grep, ls, git) are counted
separately and are not reads.

## Class totals

| class | Read | Bash read | total | of which in subagents |
| ----- | ---: | --------: | ----: | --------------------: |
| harness | 0 | | 0 | 0 |
| spontaneous | 18 | 18 | 36 | 0 |
| manual | 190 | 76 | 266 | 107 |
| active | 456 | 335 | 791 | 70 |
| reattach | 33 | | 33 | 0 |
| bash-other (not a read) | | 157 | | |

Active reads are 70% of all deliveries. Spontaneous recall, the gitlore skill
firing on its own, is 3%. Twenty-six turns in seven weeks invoked the skill.

## Class totals by ISO week

| week | spontaneous | manual | active | reattach | total |
| ---- | ----------: | -----: | -----: | -------: | ----: |
| 2026-W30 | 0 | 3 | 17 | 7 | 27 |
| 2026-W31 | 0 | 4 | 15 | 0 | 19 |
| 2026-W32 | 0 | 20 | 64 | 6 | 90 |
| 2026-W33 | 7 | 102 | 390 | 18 | 517 |
| 2026-W34 | 0 | 3 | 10 | 0 | 13 |
| 2026-W35 | 29 | 91 | 194 | 0 | 314 |
| 2026-W36 | 0 | 43 | 101 | 2 | 146 |

The harness column is zero in every week and omitted. W33 and W35 are the two
ddaanet review passes, which read facts in bulk by design.

## Most-read facts

| fact | spontaneous | manual | active | reattach | total |
| ---- | ----------: | -----: | -----: | -------: | ----: |
| ddaanet/memory-writing.md | 16 | 52 | 17 | 2 | 87 |
| ddaanet/shared-claude.md | 0 | 18 | 42 | 0 | 60 |
| ddaanet/design-doc-writing.md | 2 | 11 | 32 | 1 | 46 |
| ddaanet/claude-plugin-dev.md | 1 | 7 | 27 | 2 | 37 |
| ddaanet/index-compaction-triggers.md | 0 | 8 | 29 | 0 | 37 |
| ddaanet/green-is-not-evidence.md | 1 | 7 | 27 | 0 | 35 |
| ddaanet/sandbox-effects.md | 0 | 5 | 27 | 0 | 32 |

`memory-writing.md` and `index-compaction-triggers.md` no longer exist as
facts; their reads predate the move of authoring guidance into the plugin.
`shared-claude.md` is already in every context through the CLAUDE.md import,
so its 60 reads are redundant deliveries.

## Least-read facts, among current facts read at all

| fact | manual | active | total |
| ---- | -----: | -----: | ----: |
| ddaanet/bash-tool-set-e-inert.md | 0 | 1 | 1 |
| ddaanet/commit-bundling.md | 0 | 1 | 1 |
| ddaanet/git-checkout-clears-merge-state.md | 1 | 0 | 1 |
| ddaanet/git-protocol-file-allow.md | 0 | 1 | 1 |
| ddaanet/git-replay-hooks.md | 0 | 1 | 1 |
| ddaanet/git-subtree-ensure-clean-unscoped.md | 0 | 1 | 1 |
| ddaanet/ground-formulas-in-data.md | 0 | 1 | 1 |

## Never read

20 of the 101 facts in this repo's store (100 ddaanet tier facts and one
local, which was read) were never read by any session in the corpus:

bang-shell-shared-cwd, bash-prolog-common-foundations, cc-command-namespacing,
cc-project-dir-encoding, cc-worktree-bash-guard, detect-liveness-not-presence,
dont-bake-in-guarantees, edify-python-standards, git-ext-transport,
guard-safety-visible-in-the-pattern, large-docs-review, loose-generation,
marginal-weakness-is-not-misweighting, optional-means-source-can-omit,
provisional-values-not-provisional-code, session-title-customtitle,
slice-history-forward-not-by-cherry-pick, slice-uncommitted-tree-via-index,
tmux-test-isolation, todo-tool-flag-gated.

Never read is not never used: a fact whose index line carries the whole
routing clause can act from the index alone, and a fact written in the last
fortnight has had little chance to be needed.

## Caveats

- The 2.1.209 recall-Read shape (a memory Read as the turn's first tool use,
  with no thinking text) matches 41 of the active reads, spread from 2.1.215
  to 2.1.252. Under the gate that shape is a model-issued Read on a trivial
  prompt, not native recall, so it is left in active rather than counted as
  harness. It is the upper bound on misclassified harness reads.
- "manual" keys on the word "recall" or the fact's name appearing anywhere in
  the prompt, so a prompt about recall itself (this rerun, for one) marks its
  whole turn manual.
- The task frame cites the native recall fact as
  `ddaanet/cc-native-memory-recall.md`; no such memory file exists. The
  mechanism lives in `docs/references/cc-memory-retrieval.md`.
