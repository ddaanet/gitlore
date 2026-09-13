# Final review — the relay design record (38de36b, docs only)

Scope: the docs hunks of `git show 38de36b -- docs/` plus
`docs/changelog/2026-09-13-the-relay-is-one-file-per-report.md`. Every claim was
checked against `scripts/lib/index-sync.sh`, `scripts/cc-hooks/relay-drain.sh`,
`index-sync-post.sh`, `index-compose.sh`, `session-start.sh` and
`hooks/hooks.json`. Three defects found, all fixed in the docs; no code touched.

## Fixed

**1. `cc-platform.md` D51 heading contradicted its own body and the index.** The
heading still read "so the report is relayed through a marker" while the node's
header bullet, `decisions.md`'s D51 line and the paragraph directly below the
heading all describe a file keyed by session and agent. A reader landing on the
heading from the decisions index met the retired design. The heading now matches
the header bullet verbatim.

**2. "the only path" overstated the `SessionStart` drain, in two nodes.**
`index-authoring-sync.md` said the `SessionStart` pass "is the only path a
report reaches a session that compacted or resumed"; `session.md` step 10 said
the same. False against the code: a resumed session keeps its id and its next
main-thread batch fires `relay-drain.sh`, which enumerates `gitlore-relay-<S>-*`
and drains exactly that session. What is true is what the code's own comment
claims — `compact` and `resume` fire no batch, so the `SessionStart` pass
delivers *at* the resume rather than leaving the report to wait for the next
batch, and it is the whole delivery only for a session that runs no further
batch. Both nodes now state that bound, and neither contradicts the
delivery-timing residual stated two paragraphs later in the same node.

## Verified against the code, unchanged

- **Name shape.** `gitlore_relay_write` builds
  `gitlore-relay-$s-$a-$epoch-$pid-$tag` under `rev-parse --git-path`, matching
  the node, `configuration.md` and the changelog entry character for character.
- **Sanitizer and `nosession`.** `_gitlore_sanitize_id` collapses everything
  outside `[A-Za-z0-9-]` to `_`; an empty session maps to `nosession` on the
  write side and identically on the drain side, so the two meet. The node claims
  only "sanitized", which is true and not over-specified.
- **`${BASHPID:-$$}`.** Read as a bare assignment before the `rev-parse`
  substitution, so it is the calling process's pid. The docs say "the writing
  process's pid" — true on bash 3.2 via `$$` and on bash 4+ via `BASHPID`.
- **Tag closed set.** `case "$tag" in sync|compose)` refuses anything else; the
  node and the changelog name exactly those two.
- **`[ -e ]` refusal before `mv`.** Present, temp removed, `return 1`. The
  node's "since POSIX `mv` moves a source *into* an existing directory" is the
  code comment's reason for checking rather than relying on `mv`.
- **Drain glob, exclusion, removal.**
  `find -maxdepth 1 -type f -name "$prefix*" '!' -name '*.tmp' -print0`, sorted
  `LC_ALL=C`, `rm -f` per file read. Framing is
  `--- gitlore-relay agent $agent ---` on both channels. Filename order does
  group by agent then by epoch: every name for agent `a1` starts `a1-` and `-`
  (0x2D) sorts below every digit and letter, so no `a12-` name can fall between
  two `a1-` names.
- **Always-0 returns.** `gitlore_relay_drain` returns 0 on a missing gitdir, on
  an empty enumeration and at the end; `gitlore_relay_sweep` returns 0 on a
  missing gitdir and swallows `-delete` failure with `|| true`. Nothing in
  `session-start.sh`'s `set -e` can trip on either call.
- **Sweep.** `-name 'gitlore-relay-*' -mtime +7 -delete` — the name pattern
  matches `.tmp` too, so temps are included exactly as all three docs say, and
  the `.tmp` exclusion really is a drain rule only.
- **Keyed-run early exit.** `relay-drain.sh` does `[ -z "$agent_id" ] || exit 0`
  before any store access.
- **Baseline gating of the two reporting hooks.** `index-sync-post.sh` exits at
  `[ -f "$stashfile" ]`, `index-compose.sh` at `[ -f "$stamp" ]`. The node's
  argument that a drain in either would skip the batch whose `Agent` call
  returned holds.
- **Placement in `session-start.sh`.** The divergence branch and the ff-failure
  branch both `exit 0` well above the drain and sweep, which sit before the
  final emit. `session.md`'s sentence about the early exits is correct.
- **`session_id` parses.** Non-fatal in `index-sync-post.sh`, `index-compose.sh`
  and `session-start.sh` (`|| session=""`); deliberately fatal-to-the-drain in
  `relay-drain.sh` (`|| exit 0`), which is what the node's "the drainer parses
  its payload first, which establishes that `jq` works at all" describes.
- **Hook registration.** `relay-drain.sh` is a `PostToolBatch` entry in
  `hooks/hooks.json`, so `design.md`'s "a `PostToolBatch` relay drainer is the
  one consumer" is true of the shipped wiring.

## Residuals and rejected alternatives

All five residuals are stated as bounds, not as solved problems: the same-second
same-process collision (node, changelog, and the code comment it summarises);
the stranded temp that only the age sweep collects; the drain-then-emit window;
the background subagent whose report waits for the next batch, compact or
resume; and the dead session's report going by age rather than into a stranger's
session.

All four rejected alternatives are named in `decisions.md`'s D51 *Rejected* line
— shared per-agent marker, a drain inside each reporting hook, claim-by-rename,
folding another session's stranded reports at `SessionStart` — and each is
argued in `cc-platform.md` §Rejected alternatives with its own paragraph and a
`(D51)` citation.

## Writing rules

Present tense throughout; no "previously", "no longer", "revised" or "now"
framing in the new prose. The three surviving "no longer"/"now" hits in
`index-authoring-sync.md` and `cc-platform.md` are pre-existing lines outside
this commit's hunks. No `plans/` path, slice id, report name or line number
appears anywhere under `docs/`. Every node cites D51 by number; `design.md` and
the node header bullet summarise without arguing, and the argument lives in
`cc-platform.md` and the node body.

`docs/references/index-authoring-sync.md` is 374 lines, under the 400 cap, and
no unrelated prose was trimmed.

## Changelog numbers

The entry's probe figures match the deliverable review's Layer 2 result exactly:
86 lost reports and 2 torn markers out of 200 concurrent-write iterations (112
merged cleanly), and 144 doubled blocks, 51 empty blocks and 5 correct out of
200 concurrent-drain iterations. The entry is the one place the change is
described as a change, and the rest of `docs/` states current truth.

## Checks that passed

- `scripts/check-docs-links.py` — 51 decisions, 118 files: broken-link 0,
  unstubbed-decision 0, stub-without-body 0, duplicate-decision 0,
  duplicate-conclusion 0, undefined-decision 0, enumeration-drift 0,
  delegation-drift 0, oversized-file 0.
- `just format-docs` — "Fixed 2/91 issues in 2 files", the reflow of the two
  paragraphs edited above. It changed nothing else; no other file in the tree
  was touched.
