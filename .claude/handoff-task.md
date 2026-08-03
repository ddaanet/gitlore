## Current task

No thread is mid-flight. One constraint bears on whatever comes next: the
memory index is at 21.3KB against Claude Code's 24.4KB loader cutoff, so
entries past that point silently never reach a session, and each new fact
narrows the margin.

## Open decisions

- Whether gitlore's recall replaces `additionalContext` injection with an
  instruction to batch-Read the memory files not yet in context. Injection
  truncates past ~2KB into a spill file and does not satisfy the Read
  requirement, so a memory just shown still needs a Read before it can be
  edited; a Read-based recall primes the update path and simplifies the ledger.
  What it gives up is unconditional delivery, since an instruction can be
  deferred mid-task — which is the condition recall exists for. Needs a
  `docs/design.md` entry stating what happens on non-compliance.