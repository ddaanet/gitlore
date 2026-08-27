# 2026-08-27 — SessionStart writes the root index scaffold back into a store that has none (D14, D34)

A memory store can have no root `MEMORY.md`: an install whose CC auto-memory
dir existed but held nothing copied nothing, skipped the scaffold branch and
committed an empty tree. The installer no longer does that, but the stores it
already made are out there, and one of them ran with a mounted tier for weeks
before its first tier divergence exposed the gap — the merge continuation died
on `add -- MEMORY.md` before committing the synthesis. Composition tolerated the
absence (`gitlore_compose_up` returns early without a root index), so nothing
composed into it and nothing said why; the stale-index report ran every
session and could not notice, because the pointers it checks are read out of
the very file that was not there.

`SessionStart` now checks for the file after the fast-forward and before the
tier pin, and writes the installer's `# Memory Index` scaffold when it is
missing. It is written as an ordinary uncommitted file, never committed by the
hook: the next FR11 commit carries it under review like any other memory
change, which keeps SessionStart out of the commit path and the gate the one
place memory commits happen. The user hears about it on `systemMessage` (D14);
an unwritable store is reported on the same channel rather than aborting the
session. Running after the fast-forward means a clean store syncs first instead
of being marked dirty by its own repair; running before composition means the
tier lines surface this session rather than next.

One case in `tests/cc_hook_session_start.bats`, watched failing on the
scaffold's absence: `live` and the detached `HEAD` both lack the index, the hook
writes it, `HEAD` does not move, and `status` reports the file untracked. The
clean-store case asserts the negative — no notice, and a clean tree after the
run.
