# Recall artifact — batch-retry approval freshness

Read each file listed. Absolute paths where the file lives outside this repo.

## Shell and bats rules for this repo

- `/Users/david/code/gitlore/.claude/rules/shell.md` — whitespace safety, no
  `2>/dev/null`, `set -e` under the Bash tool, `$TMPDIR`, bats `run !`.
- `/Users/david/code/gitlore/tests/helpers/commit-memory.bash` — the
  `commit_memory.bats` fixture (`$CMD`, `make_parent_with_memory`).

## Test and directive discipline

- `/Users/david/.claude/plugins/cache/ddaanet/craft/0.2.0/skills/test-discipline/SKILL.md`
  — a test is evidence only when a state of the world fails it; the stale test's
  red is its refusal wording, not its exit status.
- `/Users/david/.claude/plugins/cache/ddaanet/craft/0.2.0/skills/directive-writing/SKILL.md`
  — the hook's re-approval `additionalContext` carries acts only; the
  `systemMessage` is one curt lowercase line; the trigger file is withheld.

## The mechanism being changed

- `/Users/david/code/gitlore/docs/references/commit-gate.md` — the IPC files and
  the retry contract (Mechanism, "Both IPC files are removed only on a complete
  commit").
- `/Users/david/code/gitlore/docs/references/git-hooks.md` — D50, D53, D54:
  which failures restamp the approval and why freshness is mtime order.
