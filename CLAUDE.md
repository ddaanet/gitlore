# Agent instructions

@.claude/token-efficient.md

gitlore is a Claude Code plugin that makes Claude's auto-memory versioned,
shared and git-backed. `docs/design.md` is the living design doc and the
memory of the design — read it before touching anything structural, and
record decisions there rather than in a memory file. It is a hub: its
Architecture sections summarize, and the linked `docs/references/` node holds
the mechanism. Never make a claim about how something behaves from the hub —
make it from the node, and for a bug report from the script the node names.

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
  `plans/` at the repo root.

## Testing

- Test the invocation path, not just the code: assert discovery and `[ -x ]`,
  and that `just test` actually reaches the suite. Green means nothing until you
  know what ran.
- `just format-docs` (first step of `precommit`) hard-wraps `docs/` and `plans/`
  with the rumdl pinned in `uv.lock`; `uv sync` once materializes `.venv/bin`,
  which `.envrc` puts on `PATH` — with PyYAML, so the wiring suite does not
  depend on the system python. A pin mismatch stops the recipe rather than
  wrapping.
- `just precommit` is fast and frequent. `just evals` drives the real claude
  CLI and costs time and money — run it explicitly, not as part of a release.
  `just release` depends on `prerelease`, which is just `precommit`.
- `test-unit`/`test-integration` run bats through `scripts/run-bats.sh`, not
  bare `bats`: it shows only `not ok` blocks plus a pass/fail count and
  stashes the full TAP stream in a logged tmp file. Don't pipe raw `bats`
  output through `tail` — a run is hundreds of lines and a truncated tail can
  crop the one `not ok` line that matters. Invoke `bats` directly only when
  deliberately inspecting the full stream (e.g. debugging the wrapper
  itself).

@memory/ddaanet/shared-claude.md
