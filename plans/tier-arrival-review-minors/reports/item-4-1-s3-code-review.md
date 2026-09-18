# Item 4.1, slice 3 — code review

Scope: the `mktemp` arm of `continue-after-merge` in `scripts/resolve.sh` and
the comment block below it, as `1e9a6e1` left them.

## Verdict

The arm is correct. One minor fix was applied to the comment. Nothing is
UNFIXABLE.

## Correctness

- `var=$(cmd) || { …; }` reaches the brace group. The status of an
  assignment-only command is the status of its last command substitution, and
  the `||` list suspends errexit for the left-hand side. Probed under
  `set -euo pipefail`: `v=$(false) || { echo reached >&2; exit 1; }; echo after`
  printed `reached` and exited with status 1. This relies on bash semantics that
  are the same in 3.2. `local v=$(…)` would mask the status, but the variable
  here is not `local`.
- The group is `echo … >&2; exit 1` and has no `rm`. If the `echo` fails,
  errexit still ends the script non-zero, and there is no scratch file whose
  removal it could skip. So the missing removal-first ordering loses nothing.
- Between `mktemp` and the commit, the message build and the commit each have
  their own `||` arm. The build's `> "$merge_msgfile"` redirection failure is
  covered by the same arm. Nothing on that path can now abort silently.
- Out of scope, not a defect of this slice: `gitlore_merge_commit_message`
  (`scripts/lib/resolve.sh`) runs inside an `||` list, so errexit is off inside
  it. A failing `git log` in its pipeline would be masked by `sed`'s status, and
  the result would be a shorter message body, not an abort. That masking already
  existed and is harmless for a commit message.

## Shape parity

The indentation, the `\` + `|| {` brace layout, the `>&2` and `exit 1` all match
the two sibling arms. The wording is
`gitlore: the merge message file could not be created, so the merge was not committed; the merge stays prepared.`
That is the runbook string verbatim, and it carries the shared phrase
`the merge was not committed`.

## Fix applied — comment tightened (minor)

The seven-line comment read as padding. It listed all three failures by name and
said "to remove … none to remove", and "on its right-hand side … there" repeated
itself. It is now five lines, as long as the comment before the slice, and says
the same thing:

```sh
      # Each failure exit here keeps MERGE_HEAD and the merge state, so a rerun
      # lands it; only the message file is this run's to remove, and a failed
      # mktemp above created none. Each `||` group below removes it first:
      # errexit stays armed there, so a failing write to stderr would skip
      # whatever follows it and leave the scratch file behind.
```

The comment is in the present tense, and it cites no plan, memory, slice or line
number.

## Verification

- `shellcheck -x scripts/resolve.sh`: clean.
- Mutation: I saved a copy under `.git/`, removed the `mktemp` arm's `|| { … }`
  in place and ran
  `scripts/run-bats.sh tests/resolve_compose.bats --filter "a failed mktemp for the merge message file"`.
  The test **redded** at line 518 on the stderr-line assertion. The file was
  restored from the backup and the backup was deleted.
- `GITLORE_GIT_RETRY_SCHEDULE=0 scripts/run-bats.sh tests/resolve_compose.bats`
  with the fix applied: 25 passed, 0 failed.
- `git diff -- scripts/` shows only the comment rewrite in `scripts/resolve.sh`,
  5 insertions and 7 deletions. Nothing is committed.
