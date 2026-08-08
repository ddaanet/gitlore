# 2026-08-08 — Active recall became a skill the agent runs, and the hook, request file and ledger came out

Recall shipped as an IPC round trip: the agent wrote up to five store-relative
paths to `.claude/gitlore-recall`, a `PostToolBatch` hook validated and resolved
them, read the bodies, and emitted the bytes as `additionalContext`. The
argument for reading on the agent's behalf was that a hook cannot force a `Read`
anyway, so emitting the content directly was one round trip instead of two with
the selection auditable in a file.

Two measured limits sink that. A large `additionalContext` is not delivered
whole — at 15.6KB the harness writes it to a `tool-results/…-additionalContext.txt`
file and inlines about 2KB — and memory bodies are not small: 57 of the 122 in
this repo's own store exceed 2KB on their own, mean 3.2KB, largest 19KB. A
five-entry fetch was therefore delivering a fraction of itself. And injected
text never registers in the file-read ledger, which is keyed off actual `Read`
calls, so an `Edit` on a recalled memory failed until the agent Read it anyway.
That is not a corner: a memory worth recalling mid-task is frequently one about
to be corrected, so the common path paid for the same body twice.

`skills/recall/SKILL.md` is now the entire mechanism — decide from the index
already in context with no tool calls, select at most five, `Read` them in one
batch — and the selection rules are prose adapted from the prompt Claude Code
gives its own memory-selection classifier. Deleted with the old channel:
`scripts/lib/recall.sh`, `scripts/cc-hooks/recall-batch.sh`, the request file
and its `.gitignore` entry, the content-addressed ledger, and the ledger's
`SessionStart`/`PreCompact` reset. `recall-reset.sh` survives as
`nudge-reset.sh`, which is all it still did — re-arming the index byte-budget
and plugin-upgrade notices.

What this gives up is unconditional delivery, and D18 now states it plainly: a
directive can be deferred mid-task, and on non-compliance nothing arrives and
nothing reports it. The machinery that bought unconditional delivery was buying
a truncated payload that had to be re-read before it could be edited.

The eval had to change with it, and would otherwise have gone quietly
meaningless. Its old proof that active recall ran was a `Write` of the request
file; with no request file, the scenario's trigger sitting in the user's prompt
meant Claude Code's own prompt-time classifier could satisfy every assertion.
The scenario now keeps all trigger tokens out of the prompt — the error string
reaches the agent only as the output of a probe script it runs — and the
assertion checks the *order*: the body was read after the call that surfaced the
trigger, which is the one thing prompt-time recall cannot do.
