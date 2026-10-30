# 2026-10-30 — Memory commits take the summary in the call

D70 removes everything that let an approval outlive the call that used it, and
five decisions leave the index with it. Each argued a mechanism that no longer
exists; their reasoning at the time is recorded here.

**D4 — the file handshake — inverts.** The approved commit message travelled in
`.claude/gitlore-memory-message` in the parent working tree, where the agent
could write it, and the file's presence was the approval signal. The summary now
travels on `gitlore-commit`'s stdin and no file carries it, so nothing the agent
writes means approval. Its rejected alternatives — a `Stop` hook to generate the
message, `PostToolUse` on every memory `Write`/`Edit`, and `claude --print` —
were arguments against a hook-driven commit and stay true under D70, the first
two among the entry-points group's rejected alternatives.

**D12 — the submodule-side gate — retires.** A `pre-commit` hook inside the
store, emitted by `emit-memory-gate.sh`, admitted a commit only under the
`GITLORE_MEMORY_COMMIT=1` sentinel, with a mirrored `gitlore.hooksDir` in each
store's config. It distinguished a sentinel, not an approval, so it admitted the
unapproved commit the 2026-10-11 eval measured and refused only a direct
`git commit` the orientation already forbids. The orientation half of D12 moved
into D70. `SessionStart` removes a wrapper byte-identical to the retired
emitter's output and unsets the mirrored key in the memory store and each tier.

**D53 — report-only guard arms do not restamp — falls with the restamp.**
Rejected there: a per-arm return code from `gitlore_guard_stale_merge_state`.

**D54 — a failure-time restamp blessing a concurrent write — falls with the
restamp.** The residual it accepted on the success path, freshness read before
the `add -A`, disappears with freshness; a write another session lands mid-run
is committed under the summary, which is the case D54's last sentence already
placed outside what an approval speaks for. Rejected there: a `touch -r`
snapshot of the approval's mtime.

**D56 — the batch retry judged by freshness — falls with the batch.** There is
no batch and no bare retry: a retry is the caller passing the summary again,
re-approved in conversation when the store has moved. Rejected there: an
exit-code or status-line protocol from `commit-memory.sh`, parsing the refusal
text for "needs approval again", deleting the message file on a fix-needed
refusal, an `-ef` guard inside `-F` skipping the rewrite when the operand is the
message file, and freshness checked in the hook before the run with the script
unchanged.

**What went with them.** `memory-commit-batch.sh` and its `hooks.json` entry,
the `memory-pre-commit` hook and `emit-memory-gate.sh`, the trigger file, the
freshness and restamp code in `resolve-sync-memory.sh`, bare `commit-memory.sh`,
and the `-m` and `-F` forms. The three entry points are reached by the plugin
`bin/` names `gitlore-commit`, `gitlore-push` and `gitlore-merge`, and the
`gitlore.commitCommand`, `pushCommand`, `mergeCommand` and
`memoryApprovalClauseFile` keys are neither seeded nor re-pinned. The approval
wording lives in the `gitlore:commit` skill (D19), and `commit-gate.md` is
retitled "Approval wording and repo gates", holding D19, D22 and D67.
