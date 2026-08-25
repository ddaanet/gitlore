# 2026-07-22 — Presence-authority settled: the index is authoritative over a pointer line's presence, and nothing is deleted to enforce it

The last open question from D17 — the index was already canonical for a line's
*text* (SPOT eval, 528 transcripts), but presence was a separate axis left open
since 2026-07-17, and the hunch at the time leaned *file-set*-authoritative. It
resolved the other way, with a constraint that does most of the work: authority
is a reading rule, not a licence to make one surface match the other. The index
says what memory contains — a file with no pointer line is not in memory — and a
line is added or removed only by the agent, deliberately. Removing a line does
**not** delete the file it named: a destructive edit as the silent consequence
of an index edit is the one surprise a memory store must not spring, and the
file is the only place the fact still lives. This closes rather than unblocks
the three passes deferred behind the question. **Coverage** contradicts the rule
(an unlisted file is unlisted on purpose; seeding a line resurrects one the user
removed). **Prune** inverts it (it lets the file set decide presence, and
destroys what may be the last trace of a lost memory) — and
file-deletion-on-line-removal, its mirror image, is refused outright. **Dedup**
was already unjustified on independent grounds. What remained open was one
non-destructive addition: a fifth compose validation reporting a bullet whose
target file is absent, which reports rather than refuses, since a dangling line
does not make the composed output wrong and refusing would block every later
write over a stale line. Built the same day (see the dangling-pointer entry
above).
