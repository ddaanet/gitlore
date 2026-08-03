## Current task

No thread is mid-flight. The tier re-pin hole described in
`plans/brief-tier-repin-eats-merge.md` is closed: both paths that advance a tier
— the fast-forward branch of `gitlore_merge_stores` and the merge continuation —
stage the moved gitlink in the memory store, so `SessionStart`'s unconditional
`submodule update` pins at the advanced commit instead of reverting to it.

## Open decisions

- `memory/ddaanet/shared-claude.md` states "refer to the user as 'my human
  partner', never by name" and its own final section says "get David's
  call". Correcting it is a shared-tier edit that changes what every
  mounting repo loads, so it is David's to make.
- Whether gitlore's recall replaces `additionalContext` injection with an
  instruction to batch-Read the memory files not yet in context. Injection
  truncates past ~2KB into a spill file and does not satisfy the Read
  requirement, so a memory just shown still needs a Read before it can be
  edited; a Read-based recall primes the update path and simplifies the ledger.
  What it gives up is unconditional delivery, since an instruction can be
  deferred mid-task — which is the condition recall exists for. Needs a
  `docs/design.md` entry stating what happens on non-compliance.