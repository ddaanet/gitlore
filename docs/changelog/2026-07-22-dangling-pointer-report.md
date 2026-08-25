# 2026-07-22 — Dangling-pointer report built — the fifth compose validation, and the only one that does not refuse

Presence-authority left exactly one non-destructive addition open: name a bullet
whose target file is absent. Refusing would be wrong twice over — a dangling
line leaves the composed output correct, and a refusal blocks every later index
write over a stale line the agent fixes in one edit. That asymmetry is why it is
a *separate pass* rather than a fifth rule inside `gitlore_compose_check`: the
check's contract is "refuse and write nothing", and `gitlore_compose`'s return
value is a list of what it *wrote*. `gitlore_compose_dangling` is called by both
triggers after compose returns, so it speaks whether or not anything was written
— a store that is already byte-idempotent still reports its stale lines on the
next index edit. It scans every mounted tier's carrier as well as the root,
because a **dormant** tier's bullets never reach the root and a root-only scan
would leave them unchecked for as long as the tier sleeps; a line living in both
indexes resolves to one file and is reported once, against the root, which is
the surface the agent has loaded. Nothing is written, created or deleted on this
path, and the tests assert that directly rather than trusting the code shape. 6
cases in `tests/index_compose.bats`, 2 in `tests/cc_hook_index_compose.bats`, 1
in `tests/tier_discovery.bats`.
