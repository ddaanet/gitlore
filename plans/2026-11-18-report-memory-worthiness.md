# Report: how memory-worthiness gets settled in gitlore sessions

Written 2026-11-18 by a read-only research agent over the gitlore session
transcripts, for the TODO item my human partner raised on 2026-11-17 ("should it
be a memory? what is the learning? what is the forward value?"). Input for a
decision, not a decision. Scratch files under `/tmp/claude/gitlore-todo/`.

**Scope:** the main-thread text of all 223 gitlore transcripts, 2026-09-21 to
2026-11-18: user and assistant text, `Skill` calls, `gitlore-commit` heredocs,
and Write/Edit calls under `memory/`. Sidechain, meta and compact-summary
entries excluded. A full scan of the extracted 4.9 MB, not a sample. Sub-agent
transcripts and other repos' transcripts were not read.

## Findings

**1. The literal questions are rare, but challenges recur, and every one was
against a fact the agent originated.**

- "should it be a memory?" appears once (f50b0e00, 2026-11-17) and "What is the
  learning?" once (908a9b99, 2026-09-27). "forward value" never appears before
  the 2026-11-17 todo note.
- Counting other wordings with the same effect, there are 7 challenges, all
  against agent-originated facts. None of the 10 facts my human partner
  originated was challenged.

What predicts the outcome is who originated the fact:

- **Kept unquestioned:** facts that come from my human partner's own words:
  "remember that" (6b67d7a4), "Standing rule." (e148a4c0), "Here's the new loop.
  That goes to shared-claude.md" (d26d4a8d), "In the meantime that resides in
  memory, keyed on release review" (242f7b47), "don't review diffs, delegate"
  (48dcf726).
- **Challenged or discarded:** lessons the agent extracts from an incident at a
  session-end checkpoint ("Capturing the one durable lesson from this session
  before the checkpoint", 908a9b99; "recording the one durable lesson",
  69ec83c1) and facts written during a precompact (f50b0e00, d2b35b73).

How each challenge was settled:

- **908a9b99:** "I cannot make sense of this. I looked at the diff too. What is
  the learning?" The agent: "There isn't one worth a memory… a generalization I
  built to make the incident look transferable… I ran it past Q5 and Q2 but not
  Q3." Discarded.
- **f50b0e00:** "should it be a memory?" The agent: "No. It is a
  dispatch-mechanism fact, and the whole run is moving that class of fact out of
  the tier." Went to edify's inbox as a brief.
- **29b2bdc8:** "does that belong in shell-scripting plugin?" The agent conceded
  "ownership is by category, not by coverage"; folded into a brief.
- **d1a7ebac:** "that should be a prohibition: don't pipe precommit or test
  runners." Relocated to the always-on tier.
- **5e0e7f46:** the reply was a bare pointer at a prohibitions brief; the write
  was reverted.
- **36ee0b2e:** "What is it you're saying there?", then "Reread (from context)
  memory-writing". The prescription moved to its owners.
- **69ec83c1:** a bare `/gitlore:memory-writing`; relocated to CLAUDE.md as "an
  activity with no literal string".
- **71b27bc8** (bulk pass): "entry 13: should it go in ../craft/inbox…?" Folded
  into craft.

**2. The usual answer names an owner rather than saying "no fact".** Of the 7
challenges, 2 ended as "no fact" and 5 as "fold it elsewhere": a skill, a hook
or prohibition, CLAUDE.md, or the conventions file. The 2026-11-17 cut says the
same at scale ("most needed not be loaded in every session. Look for when-needed
seams that can translate into skills"): tier facts went from 70 to
26. An "ok" approval does not certify worth: at least 2 agent-originated facts
approved with "ok" were retired or moved in the 11-10 audit
(`preflight-excludes-memory-submodule`, owned by `ddaa:preflight`;
`main-thread-delegates-diff-review`, unroutable).

**3. §1 already asks these questions, and has since before every case.** "what
does the next session gain…" dates from 2026-09-02 (9526f05d); the Q1–Q8 ladder
and "Ask 'what is the new learning?'" from 2026-08-28 (13cadc87). Two failure
classes:

- **(a) The skill was never loaded.** In 4 of the 13 agent-originated lineages a
  fact was written with no prior memory-writing call (f50b0e00 19:28, 69ec83c1
  19:53, d2b35b73 10:42, 48dcf726 19:44). In f50b0e00, `gitlore:commit` was
  invoked and its review directive skipped. 2 of these 4 were then challenged.
  No wording in §1 reaches this class.
- **(b) The skill was loaded but the questions were run selectively and out of
  sight.** 908a9b99 skipped Q3; 29b2bdc8 answered Q2 by coverage instead of by
  remit; 5e0e7f46 showed a full walk but missed a brief pending in a sibling
  repo's inbox. Where a verdict was visible, one line from my human partner
  overturned it; where absent, the challenge had to be the bare question.

**4. The summary format hides the forward value.** Since 2026-10-27 (f8023010)
`gitlore:commit` tells each paragraph to "spend the rest on what the diff cannot
show: what prompted it… end on the cause" and forbids stating what the fact now
says. Summaries are all incident and carry no learning or trigger moment. My
human partner's three questions ask for exactly what the format excludes.

**5. Agents rarely reach a verdict on their own.** 3 unprompted "nothing durable
surfaced" verdicts at handoff (cda304dd, dd1c20b0, 0c1e89f8); 1 owner-based
discard inside a proposal (29b2bdc8); a few relocations on the skill's own
authority (39f45ae2, 6b67d7a4, 908a9b99 before its challenge).

**6. A separate protocol defect.** In f50b0e00 the summary was shown at
19:31:22.877 and a queued `/autodrive-handoff:precompact` arrived 1.4 s later;
`gitlore-commit` ran at 19:31:41 with no approving reply, breaking step 2 of
`gitlore:commit`. That fact was discarded ten minutes later.

## Counts

23 cases, one per fact lineage, redrafts collapsed; hygiene renames (8aacbbf3)
and the bulk passes of 09-26, 10-16, 11-10 and 11-17 excluded. "Loaded" means
memory-writing was called before the proposal; "Shown" means the agent displayed
its verdict. "User" origin means my human partner.

| # | Session, date | Fact | Origin | Loaded | Shown | Answer | Outcome |
|---|---|---|---|---|---|---|---|
| 1 | 36ee0b2e 09-24 | cc-bash-background augment | agent | yes | no | "What is it you're saying there?" | fold part, kept |
| 2 | 29b2bdc8 09-25 | macos-tmpdir-path-shapes | agent | yes | partial | "does that belong in shell-scripting plugin?" | fold (skill) |
| 3 | d1a7ebac 09-25 | uv-direnv-venv augment | agent | yes | yes | "ok" | yes |
| 4 | d1a7ebac 09-25 | bg-notification-exit-status | agent | yes | yes | "that should be a prohibition" | fold (conventions) |
| 5 | 5e0e7f46 09-26 | cc-bash-background update | agent | yes | full | pointer at prohibitions brief | fold (hook) |
| 6 | 908a9b99 09-27 | cite-placement | agent, session end | yes | partial | "What is the learning?" | no fact |
| 7 | e148a4c0 10-12 | agent-reuse rule | user | – | – | "ok" | yes |
| 8 | f4910738 10-16 | review-level default | user | yes | – | "ok" | yes |
| 9 | c7552bfd 10-26 | owned-projects | user | – | – | "memory commit ok" | yes |
| 10 | 65fd3861 10-27 | --no-verify wording | user | – | – | approved | yes |
| 11 | 48dcf726 10-29 | main-thread-delegates-diff-review | user | no | no | "ok" | yes (moved 11-10) |
| 12 | d26d4a8d 10-29 | review loop | user | yes | yes | "1, approved" | yes |
| 13 | 97c3a880 10-30 | dogfood-bin-on-path | user | yes | – | "approved" | yes |
| 14 | 06322571 10-30 | preflight-excludes update | agent | yes | no | "approve" | yes (retired 11-10) |
| 15 | 39f45ae2 11-02 | design-question rule | user | yes | yes | "ok" | yes |
| 16 | 1e416cdb 11-06 | Fable fixes to fresh agent | agent | yes | – | "yes, add it" | yes |
| 17 | 418c4f51 11-09 | probe-state-normal-path | agent | after the Write | no | "ok" | yes |
| 18 | 6b67d7a4 11-12 | full suite is the gate's | user | yes | yes | "move it to shared claude" | yes |
| 19 | 69ec83c1 11-13 | no-parent-commit → commit skill | agent | – | yes | "approved" | yes (relocation) |
| 20 | 69ec83c1 11-13 | dispatch-brief-no-real-repo-entry-points | agent, session end | no | no | `/gitlore:memory-writing` | fold (CLAUDE.md) |
| 21 | f50b0e00 11-17 | cc-subagent-bash-cwd (2 versions) | agent | no | no | "should it be a memory?" | no fact (brief) |
| 22 | d2b35b73 11-18 | review-of-uncommitted-memory… | agent, precompact | no | no | "ok" | yes |
| 23 | 242f7b47 11-18 | release-review-slicing | user | yes | – | "ok" | yes |

| Origin | Cases | Yes | Fold | No fact | Challenged |
|---|---|---|---|---|---|
| My human partner | 10 | 10 | 0 | 0 | 0 |
| Agent | 13 | 6 | 5 | 2 | 7 |

Two of the 6 agent "yes" cases were later retired or moved by an audit.

## Recommendation

Yes, scoped. 5 of the 7 challenges (cases 1, 2, 4, 6, 20/21) are ones where a
shown answer to every question would have pre-empted or replaced the challenge.
Case 5 needed inbox knowledge the agent did not have.

**A. `skills/memory-writing/SKILL.md` §1.** After the opening paragraph (the one
ending "…still 'not much', discard."), insert:

> Answer three questions for each fact before proposing it, or before a summary
> over facts already written, and show the answers in the reply, above any
> summary block:
>
> - **Learning:** the rule, in one sentence a reader who was not in this session
>   can act on. If it needs the incident to make sense, or is unarguable once
>   stated, the instance was the whole content (Q3).
> - **Forward value:** the moment it fires — the string a tool result shows, or
>   the task being started — and what a session does differently there than it
>   would unaided. "A session would know X" names no moment.
> - **Verdict:** discard, relocate to a named owner, merge into a named file, or
>   save — with the question below that settled it. Q2 is decided by the owner's
>   remit, not by whether it already states the fact, and counts briefs pending
>   in an owner's `inbox/`.
>
> A discard or relocate verdict is carried out, not offered: the reply reports
> it. What stays in memory is what no owner can carry: a correction from the
> user, a failure mode observed in this repo, a constraint from outside the
> artifact's world. If nothing survives, write nothing — an empty flush is the
> normal case.

Then delete the closing paragraph starting "Ask 'what is the new learning?'";
its content moves into the new text. Size: SKILL.md is 9184 B against the 10000
B hub cap; the change adds about 850 B and removes about 370 B, ending near 9660
B. If too tight, the Q2 owner bullets (about 2 KB) are the when-needed seam to
split out.

**B. `skills/commit/SKILL.md`, Review directive.** Add: "Show each pending
fact's Learning, Forward value and Verdict lines (memory-writing §1) above the
summary block, outside it; draft the summary only over facts whose verdict is
save." The lines must not go inside an `== <store> ==` section: that text goes
verbatim to `gitlore-commit`'s stdin and becomes the commit message.

**C. Class (a) is a fork for my human partner.** All 4 skips happened at
session-end or precompact checkpoints, or right after a correction. Options:
make `gitlore:commit` refuse to draft until the verdict lines are shown (text
only), or have the handoff/precompact checkpoint text name memory-writing
(autodrive-handoff, another repo: a brief).

**D. `gitlore:commit` step 2:** a slash command or queued message that arrives
after the summary is not approval. Evidence: f50b0e00 at 19:31.

## Not established

- Sibling repos' transcripts were not read; the facts are in the shared tier, so
  "I often answer" may also draw on edify, craft and sandbox-lies sessions.
- Sub-agent transcripts were not read, so facts written there were not traced.
- Memory writes made through a Bash heredoc are missing from the event list, so
  the "not loaded" count may be low.
- Origin and "challenged" were judged from timestamps at minute resolution; case
  1 counts as both fold and kept, and case 21 merges two summaries.
- The effect of showing a verdict cannot be measured yet: only 3 cases showed a
  full walk, and 2 of those were still overturned.
