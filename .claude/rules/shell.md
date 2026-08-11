---
paths:
  - "**/*.sh"
  - "**/*.bash"
  - "**/*.bats"
  - "hooks/**"
  - "scripts/**"
---

# Shell

- **Whitespace safety is essential, never a nit.** Splitting on whitespace is a
  defect on sight. Before assigning severity to a parsing bug, run it against an
  input containing a space — `git config --get-regexp | awk '{print $2}'` on
  `path = dir with spaces/tier` emits part of the *key*, not a truncated path.
  Default to NUL-delimited forms: `git config -z --get-regexp`, `find -print0`,
  `read -r -d ''`, `find -mindepth 1 -maxdepth 1 -print -quit` over `ls -A`.

- **No `2>/dev/null`** unless failure is normal *and* the message is expected.
  Prefer, in order: a guard that removes the expected case (`[ -f "$f" ]`,
  `[ -e path/.git ]`, `rev-parse -q --verify MERGE_HEAD`); capture-and-match
  (`err=$(cmd 2>&1)` then `case "$err"`) when failure modes differ; the redirect
  only when provoking the error *is* the mechanism, with the reason inline.
  Never replace git's message with a guess.
  Details: `memory/ddaanet/no-stderr-suppression.md`.

- **Git hook env leak.** Git invokes hooks with repo-local `GIT_*` vars. A
  submodule-aware hook must clear the full set — `unset $(git rev-parse
  --local-env-vars)`, not just `GIT_DIR`/`GIT_INDEX_FILE`/`GIT_WORK_TREE` —
  except `GIT_INDEX_FILE`, which a staging hook captures before the unset and
  restores for its `git add`. Details: `memory/ddaanet/git-hook-env-leak.md`.

- **`git -C` into an unchecked-out submodule operates on the parent.** Guard
  every tier/submodule loop with `[ -e "$path/.git" ]` first.

- **shellcheck**: a comment whose first word is `shellcheck` parses as a
  malformed directive and fails lint. shellcheck lints `.bats` too.

- **bats**: a bare top-level `! cmd` in a `@test` asserts nothing (SC2314). Use
  `run ! cmd`.

- **`$TMPDIR` is unset under `dangerouslyDisableSandbox`**, so `$TMPDIR/foo`
  becomes `/foo`. Use an absolute scratchpad path.
