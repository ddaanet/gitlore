# Dispatch constraints: unadoptable tier arrival

Binding on every executor and reviewer this run dispatches.

## Environment

- Repository root: `/Users/david/code/gitlore`, branch `main`. Work there; never
  `cd` elsewhere in a command that then touches git. Never create, switch or
  delete branches or worktrees.
- macOS is a target: bash 3.2 (no associative arrays, `mapfile`, `${v,,}`,
  `$BASHPID`) and BSD `sed`/`grep`/`find`/`stat`/`mktemp`. Read
  `.claude/rules/shell.md` before writing shell.
- Scratch probes run only in `d=$(mktemp -d "${TMPDIR:?}/probe.XXXXXX")`. A `cd`
  into an unset `$TMPDIR` does not abort a Bash tool command, and the following
  git commands then run in the gitlore repo.
- `.claude/handoff-task.md` and `.claude/handoff-todo.md` carry unrelated
  uncommitted edits. Never stage or commit them. Stage by explicit path only;
  never `git add -A`, `git add .` or `git commit -a`.
- Never `--no-verify`. The parent pre-commit hook is the gitlore memory gate; it
  passes when `memory/` is untouched.

## Tests

- Run bats through `scripts/run-bats.sh <file> [--filter <regex>]`, one file at
  a time, in the foreground. Never two suites at once (the box has ~2GB RAM).
  Never pipe the output through `tail`.
- A test holding a ref or index lock exports `GITLORE_GIT_RETRY_SCHEDULE=0`
  first, as `tests/resolve_compose.bats:221` does.
- Fixtures come from `tests/helpers/` and the suite's own helpers, never a
  hand-run throwaway repo.
- `shellcheck` every edited script and `.bats` file.
- Do not run `just precommit`, `just test`, `just test-unit` or
  `just test-integration`: the orchestrator owns the full gate at phase
  boundaries.

## Code

- Source files cite neither `plans/` nor `memory/`, nor a runbook item, slice or
  line number.
- Match the surrounding code's comment density, naming and idiom.
- Whitespace safety: paths may contain spaces; never split on whitespace.

## Reporting

Write the report to the path the prompt names and reply with that path only, or
`blocked: <reason>`.
