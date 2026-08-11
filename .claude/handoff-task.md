## Current task

Sweep A of `plans/memory-hygiene-sweep.md`. Step 1 — clearing the blocking
prose violations across the ddaanet tier — is done:
`scripts/check-memory-hygiene.py` reports zero for first-person,
direct-naming, name-drift, frontmatter and broken-reference. Four
`pre-rename` citations remain, and they are the next two items. Two cases in
`tests/check_memory_hygiene.bats` are red by design and hold `just precommit`
red until both the pre-rename clearing and the `just precommit` wiring land —
expected, not a regression. The checker's own output is the worklist, so
nothing needs reconstructing from prose.

## Open decisions

- Does the checker ship as part of gitlore, or stay a `scripts/` local? The
  plan deferred this until it worked, and it works. Shipping makes python3 +
  PyYAML a user-facing dependency — which is why
  `scripts/hook-manager/wire-*.sh` probes for `python3 -c 'import yaml'`
  rather than assuming it.
- The deictic check is warn-only because `here` and `now` measured ~70-80%
  anaphoric over the real store. Warn-only forever is a report nobody reads;
  the alternative is dropping those two imprecise tokens and blocking on the
  remaining five.
- What `scripts/lib/index-sync.sh:128` should cite: it names
  `feedback_memory_retrieval_in_practice`, which has no successor file. Check
  whether `docs/design.md` D17 covers the claim before dropping it.
- `memory/MEMORY.md` sits close to Claude Code's 24.4KB loader cutoff, past
  which the tail never reaches a session. Sweep B's retirement verdicts are
  the only lever that frees index bytes, so the compaction strategy waits on
  it — but the next memory write may force the call first.