# Agent instructions

@.claude/token-efficient.md

gitlore is a Claude Code plugin that makes Claude's auto-memory versioned,
shared and git-backed. `docs/design.md` is the living design doc and the
memory of the design — read it before touching anything structural, and
record decisions there rather than in a memory file.

## Recall

Spontaneous recall is nil, and CC's passive recall fires a per-query classifier
against the *user prompt* that does not re-select later in the conversation.
Facts whose trigger only appears mid-task — a git error string, a `2>/dev/null`
in a file you just read, an empty `$TMPDIR` — never surface on their own.

So recall actively, at two checkpoints: after reading the task input, and again
after exploring the code, before writing anything durable. Scan the index in
`memory/MEMORY.md` (already in context — re-read it only after a compaction, or
if it was edited this session), name the entries that match what you now know,
and Read them in one batch.

`memory/MEMORY.md` is a routing table, not the content. Its lines exist to let
you decide read-or-skip; the fact lives in the file.

## Working with my human partner

- A defect you have verified is not made someone else's call by who authored it.
  Flagging is not the cautious option when the fix is cheap and removes nothing.
- Match plan length to the work — a full spec is for real design decisions.

## Memory and commits

- Never `git commit` inside `memory/` or a tier. Writing a memory file is an
  ordinary edit; committing the parent repo records, gates and pushes it.
- `memory/` moves in lockstep with the parent: committed before the root commit,
  pushed alongside every parent push. Lockstep is `live` vs `origin/live` — the
  memory tree's `main` may legitimately sit ahead.
- Handoff files (`.claude/handoff-task.md`, `.claude/handoff.md`) are
  tooling-managed. Write them only through the handoff skill, and fold them into
  the same commit as the work they describe.
- Conventional-commit prefixes are required in the **parent** repo; the gitmoji
  hook rewrites them. The memory approval summary is still a commit message —
  subject line, blank line, body — but takes no prefix: a memory commit is
  always documentation, so the prefix carries no information. The body is one
  **paragraph** per changed memory file, opening with a bold
  `**<Kind> <tier>/<slug>:**` prefix — the kind being New, Update, Augment,
  Reduce, or Remove — then prose on what the fact now claims and what prompted
  the change. The canonical wording, with a literal template, lives in
  `reference/memory-approval-clause.txt` (see docs/design.md D19).
- After a compaction, check `PWD`, `CLAUDE_PROJECT_DIR` and the gitStatus block
  against what the summary describes before acting — a summary says what, not
  where. If they disagree, stop and say so; don't `cd` to reconcile.

## Design

- Self-triggering skill when the condition is mechanical and detectable; a
  command only for an explicitly user-initiated action.

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
