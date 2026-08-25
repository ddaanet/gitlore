# Claude Code platform workarounds — decisions D15, D18, D23

Three decisions whose subject is a Claude Code behaviour rather than gitlore's
own design: the in-process worktree switch that strands memory, the absence of
any hook field that can force a `Read`, and the `Edit` weld defect. Each carries
the empirical work that established the platform behaviour, which is what makes
them long and what makes them worth keeping whole.

- Harness workarounds — **D15** an in-process-worktree memory-drift guard ·
  **D18** active recall is a skill the agent runs itself, with no hook and no
  state · **D23** the `Edit` weld defect is contained by a pair that computes
  the intended result, repairs, and reports its own obsolescence

---

**D15 — In-process-worktree memory-drift guard**

Claude Code's in-process `EnterWorktree` moves the session cwd into a linked
worktree but **freezes the launch environment** — `PATH`, `autoMemoryDirectory`,
and `CLAUDE_PROJECT_DIR` all stay pinned to the repo the session launched in
(verified by transcript capture, 2026-06-09). The memory-redirect shim (D10)
injects `autoMemoryDirectory` once at launch, so after an in-process
`EnterWorktree` the agent edits files in the worktree while CC's auto-memory
keeps writing to the **launch** repo's submodule. Memory silently strands in the
wrong working copy — the cwd-vs-launch divergence is the drift signal.

A `PostToolUse` hook on the targeted matcher `EnterWorktree|ExitWorktree`
(`scripts/cc-hooks/worktree-drift.sh`) catches the transition and emits one
user-visible `systemMessage` (D14's substrate) when the session has drifted. The
targeted matcher rests on an empirical confirmation (2026-06-10, this repo) that
`EnterWorktree` **does** fire `PostToolUse` and that a name-based matcher
matches `tool_name`. It beats a `"*"` matcher with a fast bail: it fires exactly
once per transition, so zero per-tool cost and no de-dup state, because it
cannot fire on the intervening `Bash` calls.

Drift predicate (all read-only git, bail silently on any error): the current
worktree's `--show-toplevel` differs from the launch root's, **and** both
resolve to one shared `--git-common-dir` (a linked worktree of the *same* repo,
not an unrelated directory). `ExitWorktree` restores cwd to the launch root, so
the predicate is false and the hook is silent — the Enter-warns/Exit-silent
asymmetry is intentional. The guard also requires the launch repo to be a
gitlore-enabled repo with a registered memory submodule; otherwise there is no
redirected memory to strand. No shim change is needed — the guard reads the
frozen `CLAUDE_PROJECT_DIR` (already relied on by the `version-guard` hook) and
compares it to the moved cwd.

**D18 — Active recall: a skill the agent runs itself, with no hook and no
state**

CC's native recall runs a per-query classifier against the **user prompt**,
returns at most five files it is certain about, and is instructed not to
re-select within a conversation. A fact whose trigger only appears *mid-task* —
a git rejection string, a `2>/dev/null` in a file just opened, an empty
`$TMPDIR` — therefore has no path into context. Closing that gap is FR16.

**The whole mechanism is `skills/recall/SKILL.md`.** Three steps: decide from
the index already in context with **no tool calls**, select at most five
entries, then `Read` those bodies in a single batch. Nothing else — no request
file, no hook, no ledger, no reset. The skill is invoked by the user, by the
agent when it notices a trigger, or — the load-bearing case — by another skill
at a checkpoint it prescribes.

**Why the agent reads, rather than a hook reading for it.** No hook output field
can inject a `tool_use` or force a `Read` — verified against the shipped binary
(2.1.217), where `injectToolCall`/`requestTool`/`forceRead`/`forceToolUse` have
zero occurrences while `additionalContext` has 180. The choice is
hook-emits-*bytes* against hook-emits-a-*directive*, and bytes lose on two
measured counts. **Truncation:** a large `additionalContext` is not delivered
whole — at 15.6KB the harness wrote it to a
`tool-results/…-additionalContext.txt` file and inlined a ~2KB preview, while 57
of this store's 122 bodies exceed 2KB on their own (mean 3.2KB, largest 19KB),
so a five-entry fetch delivers a fraction of itself and leaves the agent chasing
a pointer. **Editability:** injected text does not register in the file-read
ledger, which is keyed off actual `Read` calls, so an `Edit` on a recalled
memory fails until the agent Reads it anyway — paying for the same body twice on
exactly the path that matters most, since a memory worth recalling mid-task is
often one about to be corrected. A `Read` costs a second round trip and has
neither problem.

**What that gives up: unconditional delivery.** Injected bytes arrived whether
the agent cooperated or not; a directive can be deferred, and mid-task — when
the agent is busy — is both when deferral is likely and the condition recall
exists for. **On non-compliance nothing arrives and nothing reports it.**
Accepted rather than mitigated: the machinery that bought unconditional delivery
(an IPC file, a validating resolver, a content-addressed ledger, two reset
events) was buying delivery of a truncated payload that still had to be re-read
before it could be edited. Detecting a skipped recall is a separate problem from
serving one, and gating the agent into the checkpoint is rejected below on its
own merits.

**Selection discipline is instruction, not enforcement.** The cap of five,
"unsure means no", "an empty selection is a real answer", and matching on what
the task is *about* rather than on keyword overlap are prose in the skill body,
adapted from the prompt CC gives its own memory-selection classifier — the same
judgement, over the same evidence, made by a subagent there and inline here. A
resolver could enforce the count and reject a bad path; it could never make the
selection good, which is the part that matters. No ledger either: the agent sees
its own context, and a body it already Read is visible in the transcript.

**Index as routing table.** The premise the skill rests on: an index line
carries the *trigger keywords* so read-or-skip can be decided from it, not the
fact itself. Always-on directives were moved out of `MEMORY.md` to `CLAUDE.md`
and path-scoped `.claude/rules/`, whose `paths:` frontmatter fires on reading a
matching file — native harness support for the same mid-task-trigger problem,
along the file-path dimension.

**D23 — The `Edit` weld defect is contained by a pair that computes the intended
result, repairs, and reports its own obsolescence**

Claude Code's `Edit` is line-oriented on deletion: emptying a line removes the
line rather than leaving it blank, which costs the line's *trailing* newline.
When `old_string` has already consumed the *leading* one, a single deleted line
costs two separators and its neighbours weld onto one physical line. `Edit`
reports success identically either way. That is the origin of the welded index
bullets the compose check and the sync refuse — refusal being containment
downstream of the damage, in one file class, on the next pass.
`scripts/cc-hooks/edit-weld-pre.sh` and `edit-weld-post.sh` contain it at the
edit site instead.

**Computing the intended result is what makes the guard more than a marker.** A
hook that only recorded "something risky happened" would leave the corruption in
place and leave the agent to infer, from a downstream check finding nothing,
that the defect had gone. `PreToolUse` writes `{orig, exp, weld}` — the file as
it stands, the result the edit asked for, and the result the defect produces —
to a state file keyed by `session_id` plus `file_path`, since `PreToolUse` stdin
carries no `tool_use_id`. `PostToolUse` compares the target against all three
and consumes the state file whatever it finds. **repair**: write `exp` over the
file, undoing the join before composition, the sync or any pattern check sees
it. **clean**: `Edit` no longer welds on a shape that can — the retirement
signal, an observation rather than the absence of one, which is the whole reason
for computing an expectation. **unchanged**: the edit did not land, so writing
`exp` would apply a deletion the tool declined to make. **unknown**: the model
of `Edit` is out of date; report, write nothing. Every branch is decided by a
whole-file byte comparison, so a wrong plan can only fall through to `unknown` —
never provoke a write.

**Weldable is narrower than risky, and the difference is measured.** The arming
test is not just "empty `new_string` and a leading newline in `old_string`": the
match must also be *followed* by a newline, or there is no second separator to
lose and `Edit` is correct. Over this machine's transcript corpus — 3,248
transcripts, 12,407 `Edit` results — 14 calls carried the risky argument shape
and only 3 were weldable; all 3 reconstruct to the welded output, and the other
11 are correct deletions a shape-only test would have armed on. The guard
therefore writes a state file on roughly one `Edit` in 4,100, and that rarity is
what lets every observation speak on its own: no counters, no once-per-session
suppression, no tally. `replace_all` never co-occurred with the shape, so the
guard disarms on it rather than guessing at multi-match deletion semantics — a
stated bound, not an evasion.

**Scope is every `Edit`, in any repo.** The shape test is cheap, the defect is
not index-specific, and narrowing to `MEMORY.md` would leave other files
silently welded while starving the retirement signal of samples. The pair
depends on no gitlore store and keeps its state under `TMPDIR`, swept on the
armed path for expectations left by sessions that ended between the two hooks. A
cksum collision in the state key is harmless by the same construction as
everything else here: a mismatched record never matches.

**Only `systemMessage` and `additionalContext` carry the report;
`updatedToolOutput` does not.** `Edit`'s model-visible result is a fixed success
string — "The file … has been updated successfully" — with no diff in it
(verified across the corpus, current at 2.1.232). The agent's model of the file
comes from the edit it asked for, which after a repair is what the file holds,
so there is no corrupted diff for a rewritten tool output to displace. The
`clean` branch is user-only on the same reasoning: the agent has nothing to do
with a retirement signal, and the decision to retire is not its call.

**Rejected: rewriting the arguments via `PreToolUse` `updatedInput`.** Moving
the leading newline from `old_string` into `new_string` sidesteps the defect
entirely and costs no state file — and no divergence is ever observable again,
so the workaround could never be retired. The pair pays one file write per
weldable edit to keep the observation.

The compose check and the sync refusal stay alongside it. The pair sees only
glue arriving through `Edit`; a merge, a hand-edited carrier or a `Write`
reaches an index without passing it.

## Rejected alternatives

**Hook-side injection of the bodies**, from a request file the agent writes:
`.claude/gitlore-recall` listing up to five store-relative paths, a
`PostToolBatch` hook validating and resolving it, and a content-addressed ledger
so a body already in context was never sent twice. It delivers unconditionally,
which a directive cannot — but `additionalContext` spills past ~2KB into a
pointer file, and injected bytes never satisfy the `Read`-before-`Edit` ledger,
so the common case (recall a fact, then correct it) paid for the body twice and
the large case delivered a preview. The validation, the ledger and its two reset
events existed only to serve that channel; the selection judgement they
surrounded was always the agent's (D18).

**A `PreToolUse` deny on the first durable write of an episode,** forcing a
recall decision before the agent may write. Making a denial the *normal* control
flow spends a turn on every editing episode forever and trains the agent to read
denials as routine, corroding the channel that should mean stop. Arming it at
`UserPromptSubmit` is worse still: it duplicates the native classifier that
already fires there. The obligation lives in the calling skill's flow instead
(D18).
