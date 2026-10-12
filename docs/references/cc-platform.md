# Claude Code platform workarounds — decisions D15, D18, D23, D51, D60

Five decisions whose subject is a Claude Code behaviour rather than gitlore's
own design: the in-process worktree switch that strands memory, the absence of
any hook field that can force a `Read`, the `Edit` weld defect, the confinement
of a hook's output to the subagent it fired in, and what a `PostToolBatch`
hook's exit status does to the turn. Each carries the empirical work that
established the platform behaviour, which is what makes them long and what makes
them worth keeping whole.

- Harness workarounds — **D15** an in-process-worktree memory-drift guard ·
  **D18** active recall is a skill the agent runs itself, with no hook and no
  state · **D23** the `Edit` weld defect is contained by a pair that computes
  the intended result, repairs, and reports its own obsolescence · **D51** a
  hook's output inside a subagent reaches that subagent alone, so its report is
  relayed through a file keyed by session and agent · **D60** a `PostToolBatch`
  hook that dies reports on both channels and exits 0, and never exits 2

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
`$TMPDIR` — therefore has no path into context. Closing that gap is FR16. At
2.1.258 the native path is additionally gated behind `tengu_moth_copse` or
`CLAUDE_MEMORY_STORES`, off by default, and delivers as a `relevant_memories`
attachment rather than a Read (`cc-memory-retrieval.md`); the gap is the same
either way.

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

**D51 — A hook firing inside a subagent reports only to that subagent, so the
report is relayed through a file keyed by session and agent**

Measured under CC 2.1.261, probe and control: the parent transcript carries zero
`hook_*` attachments while the subagent's own JSONL carries all four hook
attachment kinds — `hook_system_message`, `hook_additional_context`,
`hook_success` and `hook_non_blocking_error` — and the control run with no
subagent surfaces both channels normally. `systemMessage` and
`hookSpecificOutput.additionalContext` therefore both stop at the subagent. A
composition triggered by a subagent's edit to the root index reports to nobody
who can act on it, and the parent's only view is whatever the subagent chooses
to narrate — model-mediated, not a mechanism.

The same probe logs the subagent's `PostToolUse` stdin carrying the **parent's**
`session_id` alongside its own `agent_id`, so a hook inside a subagent can name
the conversation its report is owed to.

So a hook whose payload carries an `agent_id` writes its two bodies to a report
file keyed by session and agent, drained by a dedicated `PostToolBatch` hook.
The mechanism — the write-once name, the atomic install, the one `PostToolBatch`
drainer, the `SessionStart` drain and sweep, and why the subagent still emits
its own copy — is in [index-authoring-sync.md](index-authoring-sync.md). The
relay helpers cite this decision for the measurement, which itself lives outside
anything the plugin ships.

**D60 — A `PostToolBatch` hook that dies reports on both channels and exits 0;
when it cannot report, it exits non-zero but never 2**

Measured on CC 2.1.296 with a scratch `PostToolBatch` hook under `claude -p`
(`plans/batch-hook-deaths/probe/run.sh <code>` is how the table was measured):

| Hook exit               | Turn              | Agent sees                 | Transcript                  |
| ----------------------- | ----------------- | -------------------------- | --------------------------- |
| 0 + `additionalContext` | goes on           | the context                | `hook_additional_context`   |
| 1 or 3                  | goes on           | nothing                    | `hook_non_blocking_error`, stderr |
| 2                       | ends, empty reply | the stderr, next user turn | `hook_stopped_continuation` |

Exit 2 therefore blocks at `PostToolBatch` too, and it ends the turn. `awk`,
`cmp` and `grep` exit 2 on a file they cannot open, so under `set -e` a batch
hook dies with 2 on a vanished file: the silent turn. Every other death is an
exit 1-ish: the user gets a notice, the agent nothing, and inside a subagent
(D51) nobody does. Not measured: how many stderr lines the interactive TUI
renders.

`gitlore_batch_hook_guard` (`scripts/lib/hook-guard.sh`) is called once by each
of the six `PostToolBatch` hooks, after the memory path resolves and before the
first fallible step, with the hook name, the memory worktree and a consequence
sentence for the agent. It redirects the hook's stderr to a capture file in the
memory store's git dir and records the failing command and its line in an `ERR`
trap under `set -E`. The `EXIT` trap, on a non-zero status, emits one JSON
object and exits 0: `systemMessage` carries the hook name, the status, the
failing command with its line and the captured stderr; `additionalContext`
carries the same plus the consequence sentence, which says what did not happen
(an empty sentence for the upgrade notice, on which nothing depends). The
failing command's text is exact; its line is the command's on bash 4 and later,
and on bash 3.2 the first line of the enclosing function or compound command
(measured on 3.2.57, a GNU build on Linux). A clean exit leaves stdout alone,
replays the captured stderr and leaves no file. `GITLORE_HOOK_OWNED` is a
newline-joined list of files the trap removes on every exit, a death included; a
hook appends a baseline it has claimed by rename to it.

When the git dir cannot be resolved or the capture file cannot be created, the
guard takes no capture, and when `jq` cannot encode the report it replays the
capture; in both cases a death is a plain non-zero exit with 2 turned into 1.
Deaths before the call (sourcing, the `cd`) stay plain non-zero exits and none
is an exit-2 path. A hook killed by a signal runs no trap and strands its
capture file and any claimed baseline, one file per kill and never reused, since
every reader tests the unclaimed name. A `jq` dying mid-emit is the stated
residual: all six hooks write their stdout as their last act, so one object is
emitted either way.

The consequence differs by hook. A dying `relay-drain.sh` loses the reports it
read this batch, because it can die at its final emit after the drain removed
the markers it read; unread ones stay staged. `add-tier-batch.sh` leaves the
mount outcome unknown, and `memory-commit-batch.sh` the commit outcome unknown,
with the trigger and summary files possibly still in place. The baseline hooks
(`index-sync-post.sh`, `index-compose.sh`) claim by rename, so a copy that loses
the race exits 0 quietly rather than dying on a missing file; the mechanism is
in [index-authoring-sync.md](index-authoring-sync.md). `plugin-upgrade-batch.sh`
falls back to an empty session when the payload does not parse and sends the
notice when its marker cannot be written, where a repeated notice costs a line
and a withheld one the only telling there is.

Outside the decision: `PreToolUse` hooks (`index-sync-pre.sh`,
`edit-weld-pre.sh`), where exit 2 blocks the tool call and the guard's exit-0
report would be the wrong default, are unaudited.

A step of the report builder in `gitlore_compose_and_report` (the `grep -c`
counts, `gitlore_compose_orphans`, `gitlore_compose_dangling`,
`gitlore_active_tier_scopes`) can die after the composition pass has run; a
failing `gitlore_compose` is not such a death, since it is caught into
`compose_rc` and reported with return 0. After a successful mount
`add-tier-batch.sh` dies with it, and the guard reports the death with
add-tier's consequence, so the mount report is not emitted. That is left as it
is, because no state reached from a fixture produces it and the guard's report
already tells the agent to check `.gitmodules`. Calling the function under
`if !` alone does not help: errexit is suspended for its whole body, which ends
in assignments, so it runs on and returns 0.

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

**Leaving a subagent's hook report to the subagent's own narration.** Both
channels stop at the subagent, so what reaches the parent is prose the model
chose to write rather than the report itself, and a report that never arrives
leaves nothing behind to notice (D51).

**One shared marker per agent, each reporting hook merging into it.** Every hook
matching one event runs in parallel, so two hooks staging in one batch race on a
read-merge-write and the loser's report is overwritten. A file per report has no
shared state to serialize (D51).

**A drain inside each reporting hook** rather than a hook of its own. Parallel
again: on a batch that fires both, each copy frames and emits the same reports,
so the parent sees everything twice. Both hooks also act only when their own
baseline fired, and the batch whose `Agent` call returned changed no index — so
either placement skips exactly the batch the report was staged for, leaving it
to an unrelated index edit or a `SessionStart` (D51).

**Claim-by-rename before reading**, to close the window in which a drained
report exists only in the draining hook's variables. Unique names already keep a
drain from removing a file it did not read, so the rename buys only that window
— and pays for it with a claimed file that a killed claimer strands under a name
no later drain enumerates, converting a rare lost report into a permanently
stranded one (D51).

**Folding another session's stranded reports at `SessionStart`.** It lands a
report in a conversation that never dispatched the agent and cannot act on it,
while the store state the report described is already re-covered by that
session's own structural pass. Age is the backstop instead (D51).

**Relaying in place of the subagent's own emission.** The parent would get the
report either way, but the subagent is the actor: it made the edit the report
describes, and without its own copy it goes through the rest of its run blind to
what its hook found. A relay write that fails is also reported on that emission,
where the subagent is asked to carry the report into its reply, so without it
the failure reaches nobody. The relay is staged in addition to the emission
(D51).

**Exit 1 passthrough alone.** The user gets a notice and the agent nothing, and
inside a subagent no one does (D60).

**A fixed message with no capture.** It discards the failing tool's own error,
which is the one thing that locates the death (D60).

**Per-site `|| exit 0`.** Already rejected as a dishonest error path: it ends
the hook with the failure unreported (D60).

**A wrapper script in `hooks.json`.** Six extra process spawns per batch in
every repo, for a mechanism a sourced function does in the hook's own process
(D60).

**Rewriting every non-zero status to 1.** It loses the status for nothing; only
2 is remapped, because only 2 ends the turn (D60).

**A mount report with a line saying composition did not run**, by calling
`gitlore_compose_and_report` under `if !` in `add-tier-batch.sh`. The function
cannot return non-zero there: errexit is suspended for its whole body, which
ends in assignments, so the condition never fires. Making it return non-zero
from its report-builder steps would be new behaviour for a death no state
reached from a fixture produces, and the guard's report already directs the
agent to `.gitmodules` (D60).
