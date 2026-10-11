# 2026-10-11 — SessionStart reports and never moves memory

**`SessionStart` no longer fast-forwards memory (D59).** The hook detached HEAD
at `live` and, when the store was clean, ran `merge --ff-only live`; it now
moves nothing. A fresh clone still gets a local `live`, created from the
checked-out gitlink rather than from `origin/live`, which may be ahead of it.
The divergence exit and the fast-forward-failure exit are gone with the move, so
the relay drain and the rest of the pass no longer sit behind an early return.

The reason is what the move could ever serve. The store is sized for one clone
per project, and in a single checkout HEAD equals `live` by construction — a
commit advances both — so the fast-forward never had work. A separately launched
linked worktree was the one case it reached, and a move the user does not see
rewrites the checkout under their edits. `/gitlore:merge` takes that case over,
where the move is a command the user ran.

**The hook reports instead.** Each line rides the `systemMessage` and, because
it names an act, the agent's `additionalContext`, and none is fatal. Dirty:
uncommitted changes present. `live` strictly ahead of a clean HEAD: N commits on
`live` not checked out here, run `/gitlore:merge`. HEAD and `live` diverged: run
`/gitlore:resolve`, then start a fresh session. HEAD at `live`:
`memory ready (detached at live).`; HEAD ahead of `live`: `memory ready.` — both
to the user only, so the `systemMessage` is never empty.

For a real remote the hook then runs a read-only `fetch origin live` and
compares `origin/live` with `live`: strictly ahead reports N upstream memory
commits, diverged reports that upstream has diverged (both name
`/gitlore:merge`), and equal or behind is silent. A remote with no `live` ref is
silent — nothing upstream to take, and the line would otherwise fire in every
store that was never published. Any other fetch failure is named with git's own
message.

**`/gitlore:merge` takes the local move (T5).** For the memory root only, a
local `live` that strictly contains HEAD is taken before the remote: a clean
store is checked out detached at `live` and the run says HEAD was fast-forwarded
onto its local `live`; a dirty store is reported, nothing moves, and the run
exits 0 without claiming the store finished.

**The commit instruction carries the summary on stdin.** The agent-facing
instruction (the standing `additionalContext`, the submodule gate's block
message) now reads `commit-memory.sh -F -` with the approved summary through a
quoted heredoc, not `-m "<approved summary>"`. The summary is prose derived from
memory content; templated into a double-quoted `-m` argument, a backtick or
`$(…)` in it would be run by the agent's shell.
