# 2026-08-14 — The merge directive authorizes its own dispatch instead of offering it (D24)

A `just release` in the `handoff` repo was blocked at `git push` by gitlore's
pre-push hook: the shared `ddaanet` tier had diverged from `origin/live`, 24
changed files, 3 conflicted. The hook printed the directive it was built to
print, naming the sub-agent, the state file and the continuation command. The
agent read it, reported the blocker, offered dispatching or merging inline, and
stopped. The answer was "you should dispatch as instructed by gitlore" — the
intent all along. The release stalled on a round trip the directive's own
wording could have prevented, with the version bumped and tagged locally and
nothing pushed.

The cause is not in this repo at all: the harness carries a blanket
`Do not call the AgentTool unless the user requested it`, no scope and no
rationale, above every surface a repo controls. So the fix could only be the
text. Every other blocking gitlore directive asks for an act the agent performs
itself — write the approval summary, write the trigger file — and this is the
one that needs someone else's permission.
`dispatch the memory-merger sub-agent with state file:` names the agent and
grants nothing; read literally it is an option, and the agent treated it as one.

`gitlore_emit_merge_directive` now states the licence: the dispatch is a
required step of the git operation that triggered the merge, and the request for
that operation is the request for this dispatch. That satisfies the harness rule
*as written* — a dispatch the user asked for is permitted — so nothing is
excepted, overridden or configured per machine. Keeping the argument in the text
is also what bounds it: the authorization is visibly this dispatch's, derived
from this operation, rather than a standing permission to skip a gate. Two
smaller corrections ride along. The name is emitted plugin-qualified,
`gitlore:memory-merger`, since a bare one fails discovery with
`Agent type not found`. And the continuation line, which had read
`on approval, the sub-agent must run:`, now reads `on approval of its synthesis`
— with a dispatch that needs no confirmation and a merge that still needs
approval in the same directive, the two were one word apart from being
conflated.

One emitter serves every flavor and both continuations, so the shape covers the
stale-state `abort-then-retry` directive as well as `continue-after-merge`, and
any directive added later that names a sub-agent. `scripts/install/preflight.sh`
mentions the sub-agent too and is left alone: it explains why
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is wanted at install time, and asks for
no dispatch.

`skills/resolve/SKILL.md` carries a verbatim copy of the directive for the agent
to parse against, so it moved with the emitter and gained a sentence naming the
property. The new test in `tests/resolve_merge_local.bats` pins the qualified
name, the instruction, the argument that licenses it and the approval the
dispatch does *not* cover — watched red against the old wording first, on the
qualified-name assertion.
