# 2026-09-24 — The batch retry is judged by the approval's freshness (D56)

`memory-commit-batch.sh` invoked `commit-memory.sh -F <msgfile>` with the
commit-message file as its own operand, so every retry rewrote the approval from
its own contents and minted a fresh mtime. The freshness gate inside
`gitlore_sync_memory_to_live` then always passed on the batch path, while the
parent `pre-commit` path read the same file as it stood. A welded line in a
changed index aborts with "the summary needs approval again" and keeps both IPC
files (D50); the agent edits the index; the next batch committed that edit under
a summary that never saw it. The abort text and the hook's "with the approved
summary preserved" said opposite things, and neither was enforced.

The hook now runs `commit-memory.sh` bare. With no summary operand the script
leaves the message file alone and lets the shared body's freshness gate judge
the approval already on disk — the same gate, on both paths. `-m` and `-F` still
write the file, because a summary arriving with the call was approved
immediately before it (D16), and the handoff plugin's `-F -` path is unchanged.
Which failure message the hook emits is read off the store and off the IPC file
the run left behind, never off a status the run reports about itself: that is
D53's argument against a per-arm classification, applied one layer out.

Two review passes closed refusal loops. A zero-byte approval, and then an
all-whitespace one, are both fresh by mtime; `git commit -F` rejects them as an
empty message on an arm that restamps the file, so the hook re-emitted the
identical deferred pair on every batch, under "otherwise no action is needed
from you". One predicate, carried in both scripts, now screens absent and blank
alike — in `commit-memory.sh` after its own write, so `-m ""` and `-F -` over
empty stdin meet the entry point's own directive instead of git's abort.

The checkpoint review found the third failure state mis-routed. A commit that
lands and then fails to fast-forward `HEAD:live` has already consumed the
message file; taking that to the stale-summary arm asked for a re-approval
nothing was waiting on, and dropped the prepared-merge directive the divergence
arm carries in the script's reason. It is now its own arm, tested first — the
summary was present and non-blank before the run, so its absence after it is the
fact — which leaves the freshness call downstream of it able to answer only
`yes` or `no`.

Two pre-existing defects were found and left in place. After the
landed-then-failed merge arm, the next batch finds memory dirty and the message
file gone, so the hook's no-summary screen fires ahead of the run and the
stale-merge guard is never reached: a prepared merge that `/gitlore:resolve`
owns is met with a request to summarize the pending changes and get approval.
And the clean-memory branch removes only the trigger while telling the agent
both IPC files are gone; a message file surviving a discarded memory edit is
left on disk against that claim, harmless because the freshness gate refuses it
later.
