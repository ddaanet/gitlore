## Current task

Nothing in flight. The v0.5.0 release closed the recall-skill work, so the next session picks from the remainder — `memory/MEMORY.md` is the pressing one: the index-sync hook now asks for under 17.1KB, and past 24.4KB Claude Code's own loader silently drops the tail.

## Open decisions

- How to bring the index under budget: retire whole entries, or move detail out of the routing lines into the topic files they already point at. Retiring under-triggers facts that still hold; shortening lines is what left merged-in triggers unroutable before, and `gate-cache-must-cover-every-check` — whose own widen is still outstanding — is the standing example of the cost.