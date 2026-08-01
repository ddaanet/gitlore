#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

DRIFT="$PLUGIN_ROOT/scripts/cc-hooks/worktree-drift.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

enable_gitlore() {
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
}

add_linked_worktree() {
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
}

@test "EnterWorktree into a linked worktree of a gitlore repo warns of memory drift (D15)" {
  make_parent_with_memory
  enable_gitlore
  add_linked_worktree
  payload=$(jq -nc --arg cwd "$WT" '{tool_name:"EnterWorktree", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("worktree")'
  echo "$output" | jq -e '.systemMessage | test("memory")'
}

@test "ExitWorktree back in the launch repo is silent (D15)" {
  make_parent_with_memory
  enable_gitlore
  payload=$(jq -nc --arg cwd "$TMP_REPO" '{tool_name:"ExitWorktree", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# Every negative below is the warning fixture with exactly one thing flipped —
# a fixture that stops short of the drift predicate comes out silent whichever
# guard is deleted, and pins nothing.
@test "no warning when gitlore is disabled in the launch repo's settings" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":false}}\n' > .claude/settings.json
  add_linked_worktree
  payload=$(jq -nc --arg cwd "$WT" '{tool_name:"EnterWorktree", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no warning when the launch repo has no settings.json at all" {
  make_parent_with_memory
  add_linked_worktree
  payload=$(jq -nc --arg cwd "$WT" '{tool_name:"EnterWorktree", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no warning when the launch repo has no memory submodule" {
  # Enabled in settings, drifted into a linked worktree — and still nothing to
  # say, because there is no memory store to strand.
  enable_gitlore
  add_linked_worktree
  payload=$(jq -nc --arg cwd "$WT" '{tool_name:"EnterWorktree", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "no warning when the cwd is a worktree of an unrelated repo" {
  # Different toplevel, but a different git common dir too — /add-dir into
  # somebody else's checkout is not drift, and warning about it would be wrong.
  make_parent_with_memory
  enable_gitlore
  other="$TMP_REPO-other"
  git init -q -b main "$other"
  payload=$(jq -nc --arg cwd "$other" '{tool_name:"EnterWorktree", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  rm -rf "$other"
}

# Over-determined on purpose. Deleting the `-n "$cwd" && -n "$launch"` bail
# alone leaves this green: an empty launch root makes the settings.json path
# `/.claude/settings.json`, and two later checks bail on their own. What this
# test does catch is the regression the bail exists to prevent — filling the
# missing root in from the session cwd and warning on a comparison against a
# guess. Reachability confirmed by breaking the bail and that fallback together.
@test "no warning when CLAUDE_PROJECT_DIR is unset" {
  make_parent_with_memory
  enable_gitlore
  add_linked_worktree
  payload=$(jq -nc --arg cwd "$WT" '{tool_name:"EnterWorktree", cwd:$cwd}')
  run env -u CLAUDE_PROJECT_DIR bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ignores non-worktree tools" {
  make_parent_with_memory
  enable_gitlore
  add_linked_worktree
  # The warning fixture exactly, under a tool name the matcher excludes.
  payload=$(jq -nc --arg cwd "$WT" '{tool_name:"Bash", cwd:$cwd}')
  CLAUDE_PROJECT_DIR="$TMP_REPO" run bash "$DRIFT" <<<"$payload"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
