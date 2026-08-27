#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures

CMD="$PLUGIN_ROOT/scripts/commit-memory.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

@test "exits 0 when gitlore is not configured" {
  run bash "$CMD" -m "noop"
  [ "$status" -eq 0 ]
}

@test "exits 0 when memory is clean and synced" {
  make_parent_with_memory
  run bash "$CMD"
  [ "$status" -eq 0 ]
}

@test "commit_msg_file resolves to the parent .claude/ path, not the gitdir" {
  make_parent_with_memory
  run gitlore_commit_msg_file memory
  [ "$status" -eq 0 ]
  # The equality is the whole assertion: any path inside a gitdir fails it, so a
  # separate "not under .git/" check could only ever restate it.
  [ "$output" = "$TMP_REPO/.claude/gitlore-memory-message" ]
}

@test "exits 0 in a session-less worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  run bash "$CMD" -m "noop"
  [ "$status" -eq 0 ]
}

@test "refuses dirty memory with no summary, leaving it uncommitted" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"approved summary"* ]] || \
    [[ "${output}${stderr}" == *"-m"* ]]
  [ -n "$(git -C memory status --porcelain)" ]   # still dirty, nothing committed
}

@test "-m commits dirty memory and advances live without a parent commit" {
  make_parent_with_memory
  parent_head_before=$(git rev-parse HEAD)
  echo dirty > memory/notes.md

  run bash "$CMD" -m "memory: add notes"
  [ "$status" -eq 0 ]

  # Memory committed and live advanced.
  [ -z "$(git -C memory status --porcelain)" ]
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
  # The commit-msg IPC file was consumed.
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
  # No parent commit happened.
  [ "$(git rev-parse HEAD)" = "$parent_head_before" ]
}

@test "-F - reads the summary from a heredoc" {
  make_parent_with_memory
  echo dirty > memory/notes.md

  run bash -c "'$CMD' -F - <<'EOF'
memory: from heredoc
EOF"
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: from heredoc" ]
}

@test "exits 1 with merge directive when branch diverged from live" {
  make_parent_with_memory
  # `live` advances behind the detached worktree's back (D17 branch model:
  # `live` is never checked out, so this is plumbing, not a checkout dance).
  advance_branch_with_file memory live LIVE.md live-only "Diverging commit on live"
  echo dirty > memory/notes.md

  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: add notes"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory merge prepared"* ]]
  [[ "${output}${stderr}" == *"flavor=head-vs-live"* ]]
}

@test "-m with no summary operand is a usage error, not a silent exit 1" {
  make_parent_with_memory
  run --separate-stderr bash "$CMD" -m
  [ "$status" -eq 2 ]
  [[ "$stderr" == *usage* ]]
}
