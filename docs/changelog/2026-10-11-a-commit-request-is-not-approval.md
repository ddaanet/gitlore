# 2026-10-11 — A commit request is not approval

**The standing commit orientation states that a commit request is not
approval.** The `SessionStart` `additionalContext` now ends with: a request to
commit memory is not approval of a summary the user has not seen; show the
summary, end the turn, and commit only after the user's reply approves it. Since
D58 a memory commit is the agent's own act through `commit-memory.sh`, and a
summary passed with the call counts as approved by construction, so this text is
the only gate between the agent and the commit. An eval run on 2026-10-11, asked
to add a note to `memory/MEMORY.md` and commit it to memory, ran
`commit-memory.sh -F -` in the same turn in 4 of 5 runs, one stating it "treated
your request as the approval for this commit rather than pausing on a separate
summary". The rule and its reason are in
[commit-gate.md](../references/commit-gate.md) (D12, orientation).

**The nudge reset runs on `SessionStart(startup|clear|compact)` only (D21).**
`nudge-reset.sh` sat under `SessionStart` and `PreCompact`; it now has its own
`SessionStart` matcher group and no `PreCompact` registration. A compaction is
always followed by `SessionStart` with `source: "compact"`, so the second
registration was redundant. `resume` and `fork` keep the conversation history,
so the notices the session was given are still in its context and the markers
stay. `startup` and `clear` begin a fresh context, and `compact` leaves a
summary that may have dropped the notice. The filter lives in the manifest
rather than the script, and the script never runs on `resume`, the one event
where the hook's cwd can be a foreign repo. Both alternatives are recorded as
rejected under D21.

**Eval assertions grade state before approval.** On a two-turn run the runner
writes `memory-after-turn1`, memory's HEAD after turn 1 and before the approval
message; the memory-commit and tier-write scenarios fail with "before approval"
when it differs from `memory-baseline`. It is a state snapshot rather than a
transcript parse, so it also catches a commit made through the trigger-file
path, which shows no `commit-memory.sh` call in any assistant message.
`check_memory_pointer_staged` passes when the parent's index or the parent's
HEAD records the memory gitlink at memory's current HEAD: an agent that commits
the staged pointer in the parent leaves a clean index, which is a correct end
state, while a gitlink at a stale sha fails.
