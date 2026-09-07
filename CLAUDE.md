# Agent instructions

@.claude/token-efficient.md

gitlore is a Claude Code plugin that makes Claude's auto-memory versioned,
shared and git-backed. `docs/design.md` is the living design doc and the
memory of the design — read it before touching anything structural, and
record decisions there rather than in a memory file. It is a hub: its
Architecture sections summarize, `docs/decisions.md` holds one conclusion line
per decision and every rejected alternative by name, and the linked
`docs/references/` node holds the mechanism and the argument. Read the decisions
index whole before weighing a new decision. Never make a claim about how
something behaves from the hub — make it from the node, and for a bug report
from the script the node names.

## Working with my human partner

- A defect you have verified is not made someone else's call by who authored it.
  Flagging is not the cautious option when the fix is cheap and removes nothing.
- Match plan length to the work — a full spec is for real design decisions.

## Memory and commits

- `memory/` moves in lockstep with the parent: committed before the root commit,
  pushed alongside every parent push. Lockstep is `live` vs `origin/live` — the
  memory tree's `main` may legitimately sit ahead.
- Handoff files (`.claude/handoff-task.md`, `.claude/handoff.md`) are
  tooling-managed. Write them only through the handoff skill, and fold them into
  the same commit as the work they describe.
- A memory approval summary takes no conventional-commit prefix. Don't prepare
  that summary in advance: commit the parent, and the pre-commit hook emits the
  format, the file to write it to, and the approval protocol at the moment it
  blocks.

## Writing

- State current truth in the present tense. Don't frame text as a correction of
  a previous version — git history is the changelog. Commit messages excepted.
- `docs/design.md` follows the six-section living-doc structure.
- `docs/` holds what is true now — the living design, the changelog, and
  reference material. Prospective content — plans, specs, briefs — goes in
  `plans/` at the repo root. A brief arriving from a session in *another*
  repository goes in `inbox/`, never the repo root, where it reads as a
  tracked project document.

## Testing

- Test the invocation path, not just the code: assert discovery and `[ -x ]`,
  and that `just test` actually reaches the suite. Green means nothing until you
  know what ran.
- `just format-docs` (first step of `precommit`) hard-wraps `docs/` and `plans/`
  with the rumdl pinned in `uv.lock`; `uv sync` once materializes `.venv/bin`,
  which `.envrc` puts on `PATH` — with PyYAML, so the wiring suite does not
  depend on the system python. A pin mismatch stops the recipe rather than
  wrapping.
- `just precommit` is the gate before every commit. One invocation (lint, the
  unit suite, the integration suite) runs ~9 minutes, past the Bash tool's
  10-minute foreground wait, so from an agent run it with
  `run_in_background: true` — a background task has no duration cap and runs
  across turns in the main session; the completion notification carries the
  verdict (`plans/index-edit-propagation/background-run-timeout-probe.md`).
  Only if the run dies, fall back to `just lint`, `just test-integration` and
  `just test-unit` as separate sequential calls (the box will not take two
  suites at once); each records its own sentinel. `just evals`
  drives the real claude CLI and costs time and money — run it explicitly, not
  as part of a release. `just release` depends on `prerelease`, which is just
  `precommit`.
- macOS is a target: bash 3.2 and BSD `sed`/`mktemp`/`grep`/`find`/`stat`.
  `tests/helpers/bsd-stubs.bash` shadows a tool with its BSD-strict contract so
  a GNU-ism fails on Linux; `tests/bsd_portability.bats` holds the lock-ins.
- `test-unit`/`test-integration` run bats through `scripts/run-bats.sh`, not
  bare `bats`: it shows only `not ok` blocks plus a pass/fail count and
  stashes the full TAP stream in a logged tmp file. Don't pipe raw `bats`
  output through `tail` — a run is hundreds of lines and a truncated tail can
  crop the one `not ok` line that matters. Invoke `bats` directly only when
  deliberately inspecting the full stream (e.g. debugging the wrapper
  itself).

@memory/ddaanet/shared-claude.md
