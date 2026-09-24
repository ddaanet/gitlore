# Batch-retry approval freshness

2026-09-24. Closes the gap named in the todo: on the `PostToolBatch` path a
retry reuses the preserved summary, so the edit that fixes an aborting index
commits under the old approval, while the abort text says the summary needs
approval again.

## The defect, from the scripts

`scripts/commit-memory.sh` is arg-driven (D16): with `-m` or `-F` it writes the
summary it received into `.claude/gitlore-memory-message` and then calls
`gitlore_sync_memory_to_live`. That write is what makes the approval fresh "by
construction" — the file is newer than every file in the store, so
`gitlore_commit_msg_freshness` answers `yes`. It is right for the callers the
mode was built for: a summary arriving with the call was approved just before
it.

`scripts/cc-hooks/memory-commit-batch.sh` invokes it as
`commit-memory.sh -F "$msgfile"` — the message file itself. So every retry
rewrites the approval file from its own contents and mints a fresh approval,
whatever happened to the store since the user approved it. On the parent
`pre-commit` path the file is read as it stands, an agent's later edit to
`MEMORY.md` is newer than it, and the sync refuses until the summary is
rewritten. On the batch path the same edit commits.

Concretely: a welded line in a changed index aborts with "Fix them by editing
the lines above … then retry; the summary needs approval again" and the approval
is restamped (D50). The hook wraps that as "deferred … with the approved summary
preserved … when the reason below names a fix, make it and the retry picks it
up". The agent edits the index. The next batch rewrites the message file,
freshness reads `yes`, and the edit is committed under a summary that never saw
it. The two messages contradict each other and neither is enforced.

## Design

**The enforcement is the mtime gate the pre-commit path already runs, not a
status the script reports.** Three changes.

1. **`commit-memory.sh` with no summary operand commits on the approval already
   on disk, judged by its freshness.** Today a bare invocation on dirty memory
   refuses ("needs an approved summary"). It keeps refusing when no message file
   exists, and otherwise leaves the file untouched and lets
   `gitlore_sync_memory_to_live` decide: fresh commits, stale refuses. `-m` and
   `-F` keep writing the file — a summary that arrives with the call is approved
   by intent, and the handoff plugin's `-F -` path is unchanged.

2. **`memory-commit-batch.sh` invokes it bare.**
   `commit-memory.sh -F "$msgfile"` becomes `commit-memory.sh`: the hook's
   `[ ! -s "$msgfile" ]` branch still handles the absent summary ahead of the
   run, so the bare call only ever meets a file that exists, and the script's
   freshness verdict on it is the gate. This is the line that closes the defect;
   the rest is messaging.

3. **The batch hook reads the store's freshness after a failed run, and that
   picks which message it emits.** `gitlore_commit_msg_freshness` is the status:
   `yes` means the approval still covers the store — a transient, or a fix the
   agent has not made yet — and today's deferred message stands with the
   script's reason under it. `no` means something newer than the approval is in
   the store — the agent's index edit, a checkout, a take, a resolved merge —
   and the hook emits its own message. Acts only, no mechanism: the summary at
   the message file no longer covers the memory store; present it again as a
   blockquote, amended for what changed, get approval, write it to the message
   file — the commit then completes on its own. The clause goes last, as on the
   no-summary branch; the trigger is not named. The user line is curt:
   `gitlore: memory commit deferred — the approved summary no longer covers the store, approval needed again`.
   Both IPC files stay; the stale file is the text the agent re-presents. The
   script's reason is dropped on this branch — it is the sync's "no approved
   commit summary", which reads wrong next to a file that exists.

The restamp arms in `resolve-sync-memory.sh` now do on the batch path exactly
what they do on the pre-commit path: a failure that wrote only projections of
approved lines keeps the approval; a merge preparation does not (D53); the
agent's own write to the store always invalidates it. No new state, no new
return code, no classification for the script to keep true across future arms —
D53's argument against a per-arm code holds here in full, and freshness is read
from the store rather than reported by the run.

**Residual.** Freshness is mtime order, so an agent that writes a memory file
after the message file inside one batch gets one visible re-approval request,
not a lost commit — the same edge the pre-commit path has always had. The
handoff flow writes memory first and the summary only after the user's approval
turn, so it does not hit it.

## Rejected

- **An exit-code or status-line protocol from `commit-memory.sh`.** The hook
  would act on the run's classification of its own failure, which D53 refused
  for the stale-merge guard on the cost asymmetry: a misclassified arm keeps an
  approval over content no summary covers. Freshness is the store's own answer.
- **Parsing the refusal text for "needs approval again".** Prose as protocol;
  the existing contradiction is what parsing would have to keep in sync.
- **Deleting the message file on a fix-needed refusal.** Needs the
  classification above, and destroys the text the agent would re-present.
- **An `-ef` guard in `-F`, skipping the rewrite when the operand is the message
  file.** Makes the entry point behave differently on one path value, invisible
  from its usage line.
- **Freshness checked in the hook before the run, script unchanged.** Leaves the
  entry point minting approval for any caller that passes the file, so the gate
  would live in the caller rather than the script that commits (D7).

## Work

RED before GREEN, test-driver on sonnet, one red dispatch then one green.

- `tests/commit_memory.bats`: bare invocation with a fresh message file commits
  and consumes it — red today, since bare refuses everything. Bare with a stale
  one refuses, leaves both file and memory, and says so with the sync's own
  refusal rather than "needs an approved summary" — that wording is what makes
  it red, because a bare refusal on unchanged code passes the rest. Bare with
  none refuses (exists — stays).
- `tests/cc_hook_memory_commit_batch.bats`: the defect — welded-index abort,
  agent edits the index, next batch does not commit (`HEAD` unchanged — red
  today, the retry commits), keeps both files, asks for re-approval with the
  clause and without the deferred wording; the agent rewrites the message file,
  next batch commits. The locked-repo transient test must stay green with no
  re-approval, and it is the positive pairing the negative above needs: same
  failure branch, freshness `yes`, the deferred message.
- `scripts/commit-memory.sh` (bare mode),
  `scripts/cc-hooks/memory-commit-batch.sh` (the bare invocation, the comment
  block above it, the post-run freshness branch).
- Docs: `docs/references/commit-gate.md` mechanism paragraph on the IPC files;
  `docs/references/memory-entry-points.md` D16 for the bare mode;
  `docs/decisions.md` one line under the commit gate with the rejected list; a
  `docs/changelog/` entry. Handoff plugin: nothing changes on its side.
