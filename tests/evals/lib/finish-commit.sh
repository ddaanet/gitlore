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
    if ! commit_err=$( (cd "$EVAL_REPO" \
          && bash "$PLUGIN_ROOT/scripts/commit-memory.sh" -F "$msgfile") 2>&1 ); then
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

# check_no_commit_before_approval <baseline-sha>
# The runner snapshots memory's HEAD at the end of turn 1, before the approval
# message. A HEAD that moved by then was committed before the user approved. An
# empty snapshot is read as absent.
check_no_commit_before_approval() {
  local baseline="$1" after1=""
  if [ -s "$EVAL_OUT_DIR/memory-after-turn1" ]; then
    after1=$(cat "$EVAL_OUT_DIR/memory-after-turn1")
  fi
  if [ -n "$after1" ] && [ "$after1" != "$baseline" ]; then
    fail "memory was committed before approval — HEAD moved during turn 1, ahead of the approval message"
  fi
}

# check_memory_pointer_staged
# The commit moved memory HEAD, so the parent must record the memory gitlink at
# that sha — otherwise the user's next parent commit records a stale pointer.
# Passes when the index entry or the parent's HEAD is memory's current HEAD. A
# clean index still lists the path, at HEAD's sha, so one comparison covers both
# "staged" and "already committed".
check_memory_pointer_staged() {
  local want idx_line idx_sha head_sha
  want=$(git -C "$EVAL_REPO/memory" rev-parse HEAD) || \
    fail "could not read memory's HEAD"
  [ -n "$want" ] || fail "could not read memory's HEAD"
  idx_line=$(git -C "$EVAL_REPO" ls-files -s -- memory)
  read -r _ idx_sha _ <<<"$idx_line"
  head_sha=$(git -C "$EVAL_REPO" rev-parse -q --verify HEAD:memory)
  if [ "$idx_sha" != "$want" ] && [ "$head_sha" != "$want" ]; then
    fail "the parent index does not have 'memory' staged after the commit ($path_taken) — the gitlink floats until the user stages it"
  fi
}
