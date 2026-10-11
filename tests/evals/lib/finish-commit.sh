#!/usr/bin/env bash
# Sourced by the assertions that grade a memory commit. The caller defines
# `fail <reason>` (print, exit 1) and has EVAL_REPO / PLUGIN_ROOT in the
# environment.
#
# After the user approves, the agent has three correct ways to finish, and which
# one it picks is not what the scenarios grade:
#   - run commit-memory.sh with the summary (`-m`);
#   - write the summary AND the commit trigger, and let the PostToolBatch hook
#     run commit-memory.sh on its behalf;
#   - write the summary and STOP. Nothing consumes it on its own — no parent
#     hook commits memory — so the assertion runs commit-memory.sh on the
#     summary, as the product does for a bare `commit-memory.sh -F <file>`.
# Grading the stop-point instead of the outcome would fail a flow whose fact is
# committed, so the assertions grade the same end state whichever ran.

# settle_commit_path <memory-dir> <baseline-sha> <summary-file>
# Leaves memory committed, or fails. Sets `path_taken` for the failure messages
# of the checks that follow.
settle_commit_path() {
  local mem="$1" baseline="$2" msgfile="$3" commit_err
  if [ "$(git -C "$mem" rev-parse HEAD)" != "$baseline" ]; then
    path_taken="the agent committed memory itself"
    return 0
  fi
  if [ -f "$msgfile" ]; then
    if ! commit_err=$( (cd "$EVAL_REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
          bash "$PLUGIN_ROOT/scripts/commit-memory.sh" -F "$msgfile") 2>&1 ); then
      fail "commit-memory.sh failed on the approved summary — ${commit_err//$'\n'/ }"
    fi
    path_taken="the agent stopped after writing the summary; commit-memory.sh finished it"
    return 0
  fi
  # No summary on disk and memory has not moved: the agent never committed, with
  # two distinguishable causes worth naming separately.
  if [ -f "$EVAL_REPO/.claude/gitlore-commit-memory" ]; then
    fail "no commit-msg file, but the commit trigger IS present — the agent asked for the commit without ever writing the approved summary, so the batch hook is parked waiting for it"
  fi
  fail "no commit-msg file and no trigger, and memory never moved — the agent did not write the approved summary after Turn 2"
}

# check_memory_pointer_staged
# The commit moved memory HEAD, so commit-memory.sh stages the memory gitlink in
# the parent index — otherwise the user's next parent commit records a stale
# pointer.
check_memory_pointer_staged() {
  local staged
  staged=$(git -C "$EVAL_REPO" diff --cached --name-only) || \
    fail "could not list the parent's staged paths"
  printf '%s\n' "$staged" | grep -qxF 'memory' || \
    fail "the parent index does not have 'memory' staged after the commit ($path_taken) — the gitlink floats until the user stages it"
}
