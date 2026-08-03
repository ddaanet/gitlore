## Current task

No thread is mid-flight. One finding from this session is written up but not
acted on: `brief-tier-repin-eats-merge.md` records that `SessionStart`'s
unconditional `git submodule update` re-pins a tier to its recorded gitlink,
so any session starting between `/gitlore:merge` and the memory commit walks
the tier's HEAD back off the merge commit and reverts the merged fact files,
silently. `/gitlore:push` shares the continuation and the window. The instance
that happened this session was repaired from the tier's `live` branch and
recorded; the hole is still open.

## Open decisions

- Whether to land the proposed fix: stage the moved tier gitlink in
  `continue-after-merge` (`git -C "$mempath" add -- "$tier"`), so
  `submodule update` — which reads the index — pins at the merged commit
  instead of reverting to it. Cheap, but it touches a documented invariant
  on a path `/gitlore:push` shares, and it needs a bats test asserting the
  tier HEAD still *contains the merge commit* after a SessionStart pass — a
  test that only checks `git status` clean passes in both worlds.
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