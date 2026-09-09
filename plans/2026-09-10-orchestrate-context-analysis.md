# Orchestrate session context analysis

Measured from the Claude Code transcripts under
`/Users/david/.claude/projects/-Users-david-code-gitlore/`. No transcript was
read into context; every figure below comes from aggregation scripts. Excerpts
quoted are under the 40-line budget.

## Method and how much to trust the numbers

Two independent measurements, cross-checked against each other.

**Ground truth (exact).** Every assistant message carries `message.usage`. The
context size at API call *k* is `input_tokens + cache_creation_input_tokens +
cache_read_input_tokens`. Summing that over all calls gives the session's total
billed input. These are the model's own token counts, not estimates.

**Attribution (modelled, ±15%).** For each consecutive pair of API calls I take
the *measured* context delta and split it across the transcript entries that
appeared between them, in proportion to their character counts. This is
calibrated per session rather than assuming a chars-per-token constant, and it
sums to the measured accumulation by construction. Its one assumption is that
all content between two calls tokenizes at a similar density — good for prose
and shell output, less good where a segment mixes a diff with a paragraph.

Two mechanism questions had to be settled before the attribution could be
trusted, and both were settled empirically rather than assumed:

- *Does content persist and get re-sent?* Yes. Context size rises monotonically
  and at every call equals base + everything accumulated so far. Nothing is
  dropped. A block added at call *k* is paid on all `N-k` calls after it.
- *Are thinking blocks retained across turns?* Essentially no. The transcript
  stores thinking bodies as empty strings, so I regressed context delta on
  (visible chars, previous call's `output_tokens`). Across the three largest
  sessions, visible content explains 81–86% of growth and output tokens
  0.01–0.06 tokens of context per output token — 1–6% of growth. The flagship
  session emitted 420,129 output tokens; if they had been retained the context
  would have been roughly double what it was. So reasoning is cheap to *hold*,
  even where it is expensive to *produce*.

There is also a per-API-call constant of 135–175 tokens (13–14% of growth) that
does not correspond to any transcript entry — per-turn scaffolding the
transcript does not record. It is small and not attributable further.

## The sessions

Identified by `Skill(orchestrate)` invocation and repeated `Agent` calls against
`edify:*` subagent types.

| session    | date        | API calls | dispatches | peak ctx | billed input |
| ---------- | ----------- | --------- | ---------- | -------- | ------------ |
| `95b12e49` | 09-08→09-09 | 366       | 24         | 419,100  | 84,268,347   |
| `70469e22` | 09-09→09-10 | 208       | 5          | 236,116  | 27,969,883   |
| `2a720752` | 09-08       | 175       | 12         | 221,332  | 23,865,707   |
| `4fe296f6` | 09-09       | 150       | 8          | 225,519  | 19,610,543   |
| `a9bf3102` | 09-07       | 145       | 5          | 176,570  | 15,338,294   |

`95b12e49` is the flagship: item 3.1 of `plans/index-edit-propagation/`, five
TDD slices, 24 dispatches, 419K peak context with no compaction. The figures
below are its unless stated; the other sessions are reported where they differ.

## Where the context goes

Two views. **Share of peak context** answers "what filled the window". **Share
of billed input** — token-turns, each block's size times the number of API calls
that followed it — answers "what it cost", and is the one that should drive
decisions, because a block added early is paid hundreds of times.

### Share of peak context (419,100 tok)

| category                                   | tokens  | % peak |
| ------------------------------------------ | ------- | ------ |
| Report reading (`cat`/`sed` of `reports/*`) | 91,937  | 21.9%  |
| Dispatch prompts (`Agent` tool input)       | 76,769  | 18.3%  |
| Fixed base prompt (call 0)                  | 39,884  | 9.5%   |
| Other file reads via Bash                   | 32,120  | 7.7%   |
| Bash *commands* the orchestrator writes     | 46,237  | 11.0%  |
| User-role messages                          | 24,117  | 5.8%   |
| `edited_text_file` re-injections            | 16,939  | 4.0%   |
| `output_style` reminder (×157)              | 15,756  | 3.8%   |
| Assistant prose                             | 13,710  | 3.3%   |
| Runbook reads/re-reads                      | 12,261  | 2.9%   |
| `relevant_memories` (×5)                    | 11,791  | 2.8%   |
| `total_tokens_reminder` (×155)              | 9,364   | 2.2%   |
| `just precommit` / bats output              | 5,296   | 1.3%   |
| Agent return messages (×24)                 | 3,478   | 0.8%   |
| git command output                          | 3,266   | 0.8%   |

### Share of billed input (84,268,347 tok)

| category                        | token-turns | % billed |
| ------------------------------- | ----------- | -------- |
| Fixed base prompt               | 14,597,544  | 17.3%    |
| Bash results other than reports | 13,829,191  | 16.4%    |
| Report reading                  | 13,474,673  | 16.0%    |
| Dispatch prompts                | 12,900,801  | 15.3%    |
| Bash commands written           | 7,637,031   | 9.1%     |
| `edited_text_file`              | 3,892,092   | 4.6%     |
| Runbook reads                   | 3,683,941   | 4.4%     |
| User-role messages              | 3,654,804   | 4.3%     |
| `output_style`                  | 3,163,445   | 3.8%     |
| `relevant_memories`             | 2,719,596   | 3.2%     |
| Assistant prose                 | 2,219,397   | 2.6%     |
| `total_tokens_reminder`         | 1,880,986   | 2.2%     |

The shape holds across sessions. In all five, Bash tool results are the top
category (30–38% of peak) and dispatch prompts second (12–21%). `4fe296f6`:
report reads 16.2%, dispatch prompts 12.6%. `2a720752`: report reads 10.0%,
dispatch prompts 17.1%.

### Why each big category is big

**Report reading — volume, not repetition.** 47 read calls over 25 distinct
files, 245,038 chars of results. The corrector reports are large by design:
across the job's 69 reports, code-review reports average 16,240 bytes and
test-review reports 15,073 bytes (max 24,713), against 6,452 for RED and 4,955
for GREEN. Corrector output is 516KB of the job's 747KB of reports. The
apparent "re-reads" are mostly paging — `sed -n '1,95p'` then `'95,215p'` then
`'215,300p'` through one report — not the same bytes twice. Genuine duplicate
reads are two commands issued twice, about 7,200 chars. So there is almost no
waste here to reclaim; the cost is that reports are long and the orchestrator
reads them end to end.

**Dispatch prompts — authored, not assembled.** 24 prompts, 167,303 chars,
median 6,836, mean 6,970, max 9,575, evenly split between `test-driver` and
`corrector` (83.6K chars each). Two measurements matter for the hypotheses
below. Line-level repetition across prompts is 15% of prompt chars, and the
repeated lines are short boilerplate (`Working directory: ...`, `Commit
nothing.`, the `Done criteria` heading). And an 8-gram provenance check against
every candidate source gives: 4.6% from `runbook.md`, 1.2% from any report, 0.1%
from `outline.md`, 0.0% from `docs/design.md` — **94.8% novel text**.

**Bash results other than reports (16.4% billed).** 52,267 chars over 32 calls
of source-file reading, the largest being `scripts/lib/index-sync.sh` (12,145
over 2 reads) and `scripts/cc-hooks/session-start.sh` (9,342 over 2) — files the
dispatched agents were themselves reading. Plus `justfile` paging (9,068 chars
over 3), nine reads of the background-task output files under `/tmp` (6,291),
and git output.

**Bash commands the orchestrator writes (9.1% billed).** 138 calls, median 110
chars, mean 577. Thirteen commands over 1,500 chars account for 65% of the
total: python heredocs (largest 11,907 chars, a one-off handoff generator),
multi-line `git commit -F -` heredocs, and long explicit `git add` file lists.

**Fixed base prompt (17.3% billed, the single largest line).** 39,884 tokens at
call 0, before any work. Regressing call-0 context on transcript-visible
pre-call content across the 60 most recent sessions in this project gives

```
base_tokens ≈ 22,062 + 0.298 × visible_chars     (⇒ 3.36 chars/token)
```

so ~22,062 tokens are invisible to the transcript — system prompt, tool schemas,
and the `CLAUDE.md` chain — and ~17,800 are visible attachments. The visible
part breaks down as: skill listing 23,364 chars (~7.0K tok), agent listing
12,128 (~3.6K), session-start hook output 22,162 (~6.6K), sandbox instructions
4,797. The `CLAUDE.md` chain on disk (`~/.claude/CLAUDE.md` 474 +
`gitlore/CLAUDE.md` 4,934 + `.claude/token-efficient.md` 416 +
`memory/ddaanet/shared-claude.md` 16,881 = 22,705 bytes) is ~6.8K tokens of the
invisible 22,062, leaving ~15K for system prompt and tool schemas. `MEMORY.md`
(26,321 bytes) is *not* in the always-loaded chain — only `shared-claude.md` is
imported — so it is not part of the floor. The split between system prompt and
tool schemas is not separable from transcripts; Claude Code's `/context` command
would settle it.

The base is not orchestrate's doing, but it is 17.3% of the bill and it scales
with call count, so it interacts with the recommendations below.

## Pure waste found

**1. `edited_text_file` re-injection of reports — 4.0% of peak here, 9.6% in
`4fe296f6`.** After the orchestrator reads a report, something else modifies
that file — a corrector appending, or `just format-docs` rewrapping it during
`precommit` — and the harness re-injects a snapshot of the changed file into the
orchestrator's context. Measured: seven injections in `95b12e49` (16,939 tok)
and eight in `4fe296f6` (21,636 tok), each capped near 8.8KB, every one of them
a `plans/index-edit-propagation/reports/*.md` file the orchestrator had already
read in full. This is the same bytes a second time, unrequested. It is the
cleanest waste in the data.

**2. The peer-message boilerplate on every dispatch return — 2.4% of peak.** 24
idle notifications, 29,865 chars, average 1,244. The payload is ~250 chars of
JSON naming the report path; the remaining ~1,000 chars are a fixed harness
paragraph about permission laundering, repeated 24 times (~10,000 tokens, 24,000
chars). Harness behaviour, not skill behaviour — flagged for completeness, not
actionable from the skill body.

**3. The handoff task file appears twice in the base.** At session start the
same ~9.7KB handoff text arrives once inside the `hook_success` stdout and again
as `hook_additional_context` (10,516 and 10,988 chars). Whether *both* reach the
API or the `hook_success` record is UI-only is not decidable from the
transcript — a cross-session regression on this was inconclusive. Worth one
`/context` check; if both are sent it is ~3K tokens on every call of the session.

**4. Two duplicated commands.** One `sed -n '80,135p' … item-3-1-s4-code-review`
and one `awk '/^### 5b/…' … item-3-1-s5-code-review`, each issued twice, ~7,200
chars. Trivial.

**5. `output_style` + `total_tokens_reminder`, 6.0% of peak / 6.0% of billed.**
157 and 155 injections of identical short strings, accumulating to 25,120
tokens. Harness behaviour; noted because it is not free and nothing in the
session controls it.

## The three hypotheses

### 1. "Dispatch-prompt authoring and report reading are the two big consumers" — CONFIRMED, but they are not the largest

Together they are 40.2% of peak context and 31.3% of billed input, and they are
the two largest *orchestrate-controlled* categories in every session measured.
So the hypothesis is right about which levers exist inside the loop.

It is wrong if read as "these dominate the bill". The fixed base prompt (17.3%)
is a bigger single line than either, and the two of them together are beaten by
the combination of base prompt + non-report Bash results (33.7%). More
importantly, both are dwarfed by the *structural* effect described in
recommendation A: the same content in a 366-call session costs three times what
it costs in a 122-call session, and no reduction inside a category can beat that.

### 2. "Dispatch prompts could be prepared in files, referenced by path" — FALSIFIED as stated

The saving is not merely small. In the form stated it is **negative**.

The mechanism, precisely. A prompt reaches the orchestrator's context exactly
once today, as the `input` of the `Agent` tool_use block, and persists there for
the rest of the session — that persistence is what the 12.9M token-turns
measures. Writing the prompt to a file first does not change how it is
*produced*: the orchestrator must still emit every one of those ~2,900 tokens as
output, and they land in context as the `Write` tool's `input` block, which
persists identically. You then additionally pay the `Write` tool_result and the
path-carrying `Agent` call. Net: same output tokens, same persistent block, plus
a round-trip. The premise in the brief — "a prompt written to a file by the
orchestrator still passes through the orchestrator's context once" — is correct,
and it is the whole story: there is no second copy today to eliminate.

The version that *would* pay is different: have a **different context** author
the file. Two shapes, and the data speaks to both.

- *Mechanical generation from the runbook.* Ruled out by measurement. Only 4.6%
  of prompt content is 8-gram-traceable to `runbook.md`. There is nothing
  substantial to template.
- *A composer subagent.* This is where the 94.8%-novel figure bites. That novel
  text is not invention for its own sake — inspection of the prompt structure
  shows sections like `## Constraints established by measurement — do not
  rediscover these` and `## The mutation round — this is the point of the
  review`, which encode what the orchestrator learned from the *previous*
  slice's reports, restated in its own words (hence only 1.2% overlap with the
  report text). A composer subagent would need that knowledge, which means
  either shipping it the reports (moving the cost, not removing it) or shipping
  it the orchestrator's understanding (which is the expensive part). The saving
  would be real but bounded by how much of the prompt is genuinely
  context-free — and the measurement says most of it is not.

What *does* pay, cheaply: the 15% of prompt chars that are repeated boilerplate
(~24,342 chars ≈ 10,000 tokens ≈ 1.9% of billed). Those lines — working
directory, the CLAUDE.md paths to read, "Commit nothing", the recall-artifact
path — are identical across dispatches and belong in the agent definitions or a
fragment the agent reads, not re-emitted 24 times. `dispatch-composition.md`
already says "Context by path, never by content" for design and recall; the same
rule applied to the standing preamble removes it from the prompt entirely.

### 3. "Report processing can be delegated to a subagent" — QUALIFIED; delegate the long tail, not the loop

Report reading is 16.0% of billed input, so the ceiling on this is real. But
what the orchestrator extracts from a report is not summarisable in the general
case, because the extraction *is* the next dispatch prompt.

What it genuinely needs is narrow and mechanical:

- a verdict (fixes applied / UNFIXABLE / blocked),
- whether anything was left uncommitted for it to commit,
- the slice commit hash from a GREEN report,
- a list revision for the remaining slices in `runbook.md`,
- an escalation signal — a finding the corrector *reported rather than applied*.

The last two are exactly where a summariser fails. The excerpt from
`item-3-1-s4-code-review.md` is instructive: its "Headline" paragraph already
compresses the verdict into ~800 chars and explicitly names two findings
reported-not-applied with section pointers. A reader agent asked for "the
verdict" would plausibly return "correct, no changes needed" and drop §6 —
`gitlore_relay_drain` can still abort its caller — which is precisely the line
that changes what happens next. The failure is silent: the orchestrator cannot
tell a report with nothing in it from a summary that lost the one thing in it.

So the qualified form: **delegating the whole report is unsafe; delegating by
report class is sound.** RED and GREEN reports (mean 6,452 and 4,955 bytes) are
mostly per-test output the orchestrator does not act on — it needs a pass/fail
roll-up and a commit hash, both mechanically extractable and both verifiable
against `git log` and a test re-run if wrong. Corrector reports are where
judgement lives and should keep being read by the orchestrator. A cheaper and
strictly safer variant for those: have the corrector's report format put a
machine-shaped verdict block at the top — verdict, files changed, findings
reported-not-applied, list-revision suggestions — so the orchestrator reads a
short head first and pages into a section only when the head points at one. That
keeps the orchestrator as the reader and cuts the bytes, with no summariser in
the path.

## Recommendations, ranked by measured saving

### A. Split the run across sessions at phase boundaries — saves 35–55%

The dominant cost is not any category; it is that cost grows with the square of
session length. Replaying the flagship session's measured context series with
splits, charging a generous 20K-token re-prime to each new session:

| split          | billed input | saving |
| -------------- | ------------ | ------ |
| actual (1)     | 84,268,347   | —      |
| 2 sessions     | 54,692,436   | 35%    |
| 3 sessions     | 43,563,291   | 48%    |
| 4 sessions     | 37,545,703   | 55%    |
| 6 sessions     | 32,017,577   | 62%    |

No other change on this list comes close, and it needs no new mechanism. The
skill body's §5 already specifies "Resuming after a context ceiling or kill" —
find the last checkpoint commit, run its verification, rebuild the inventory,
resume. That is a *recovery* path today; the change is to make it a *scheduled*
one.

**File:** `skills/orchestrate/SKILL.md` §4 (Phase Boundary) and §5. Add to the
phase boundary, after the checkpoint corrector commits: hand off and clear, then
resume via the existing §5 procedure. The three smaller sessions above
(`2a720752`, `4fe296f6`, `a9bf3102`) show what a phase-sized run costs — 15–24M
billed input, peaking at 176–226K — versus 84M for the one that ran three phases
end to end.

**Risk:** the cost is re-establishing state, which is exactly what §5 already
describes and what the handoff skill exists to carry. Note the flagship session
*was* resumed from a handoff (its base carries a 9.7KB task file), so the
mechanism is already exercised in this workflow. The residual risk is a
mid-phase split losing an in-flight slice; splitting only at phase boundaries,
after a checkpoint commit, avoids it.

### B. Stop re-reading reports the harness will re-inject — saves ~4–10% of peak

Cause: the orchestrator reads a report, then `just format-docs` rewraps it or a
corrector appends to it, and the harness pushes a full snapshot back. Measured
16,939 tok (`95b12e49`) and 21,636 tok (`4fe296f6`).

**File:** `skills/orchestrate/SKILL.md` §3 and §4. Mechanism: read a report
*after* the precommit that rewraps it, not before — or exclude `plans/*/reports/`
from `just format-docs`' wrap set so a report is never rewritten after it is
written. The second is cheaper and removes the cause rather than sequencing
around it, but it touches the `justfile`, which is this repo's, not the plugin's.

**Risk:** near zero for the sequencing change. Confirm first that the
re-injections are in fact rewrap-driven — `git log -p --stat` on one report file
against the session's precommit times settles it in one command.

### C. Move the dispatch preamble out of the prompt — saves ~1.9% of billed

The 15% of prompt characters that repeat across dispatches, ~24,342 chars ≈
10,000 tokens ≈ 1.9% of the flagship bill. Small but genuinely free: no new
failure mode, no new agent, and it removes text the agent already has other
routes to.

**File:** `skills/orchestrate/references/dispatch-composition.md`, §Prompt
contents. Extend the existing "Context by path, never by content" rule to the
standing preamble — working directory, `CLAUDE.md` paths, "Commit nothing",
recall-artifact path — and put those in `plugin/fragments/delegation.md`, which
§Agent behaviour contract already makes every dispatched agent read.

**Risk:** low, but not nil. "Commit nothing" is a *behavioural override* of the
agent's own definition and currently appears in the prompt precisely because it
contradicts what the agent otherwise does; moving it into a fragment the agent
reads is fine, moving it somewhere the agent may not read is not. Keep the
override lines in the prompt if there is any doubt — they are the small part of
the 15%.

### D. Put a verdict head on corrector reports — saves up to ~10% of billed, no summariser

Corrector reports are 69% of the job's report bytes and drive most of the 16.0%
report-reading line. The reports already open with a "Headline" paragraph; the
change is to make it a specified, complete, machine-shaped head — verdict, files
changed, findings reported-not-applied with section pointers, list-revision
suggestions — so the orchestrator can read ~1KB and page into one section
instead of reading 16KB.

**File:** `agents/corrector.md`, its "Review structure" section (line 380) and
"Write review" step (line 599).

**Risk:** moderate and worth stating plainly. This shifts the completeness
burden onto the corrector: if the head omits a finding, the orchestrator never
sees it, which is the same silent failure as a summariser — just moved earlier
and into an agent that has already read everything and has no incentive to
compress. Mitigate by requiring the head to *point* at sections rather than
replace them, and by keeping the orchestrator's read of any section the head
flags.

### E. Do not delegate corrector-report reading; do delegate RED/GREEN roll-up — saves ~2–3%

Following from hypothesis 3. RED and GREEN reports are 189KB of the job's 747KB
and carry per-test output the orchestrator does not act on. A reader that
returns pass/fail counts plus the commit hash is verifiable against `git log`
and a re-run, so the summariser failure mode is detectable rather than silent.

**File:** `skills/orchestrate/SKILL.md` §2.3(a)/(c).

**Risk:** low *because verifiable*. Do not extend this to correctors — see the
§6 example above.

### F. Things not worth doing

- **Shrinking `just precommit` output.** It is 1.3% of peak / measured 5,296
  tokens over 16 calls. The background-task-plus-gate-file protocol in
  `CLAUDE.md` is already doing its job; there is nothing to reclaim.
- **Compressing agent return messages.** 3,478 tokens over 24 returns, 0.8%.
  The return contract is already one line.
- **Fixing the two duplicated Bash commands.** ~7,200 chars. Noted for honesty;
  not a change worth making.
- **Trimming the base prompt from inside orchestrate.** The 17.3% is real, but
  its two largest movable pieces are the skill listing (23,364 chars) and agent
  listing (12,128 chars), which are functions of how many plugins are enabled,
  not of anything orchestrate does. Worth a separate look; not this skill's.

## Uncertain, and what would settle it

- **Base-prompt composition.** The 22,062-token invisible floor is measured; its
  internal split between system prompt, tool schemas and the `CLAUDE.md` chain is
  inferred from file sizes. Claude Code's `/context` command reports the split
  directly.
- **Handoff double-injection.** Whether `hook_success` stdout and
  `hook_additional_context` both reach the API, or only one does. `/context` at
  the start of a session resumed from a handoff answers it.
- **Thinking retention.** Measured as 1–6% of growth in these sessions, which is
  consistent with thinking being stripped from prior turns and retained only
  within a turn. That is an inference from the regression, not from a documented
  contract; it could differ under a different effort setting. It matters only if
  it changes — at 1–6% it is not a lever today.
- **Cache economics.** 98% of the flagship session's billed input was
  `cache_read_input_tokens`. Cache reads bill at a fraction of base input, so the
  *monetary* ranking of these recommendations differs from the token ranking, and
  recommendation A benefits most (it removes reads rather than writes). I have
  not applied a price multiplier here; current per-model cache-read pricing
  should be checked before converting any of these figures to money.
