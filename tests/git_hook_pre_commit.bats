#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

HOOK="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

@test "exits 0 when gitlore is not configured" {
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "exits 0 when memory clean and at live" {
  make_parent_with_memory
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "exits 1 with hint when memory dirty and no approved summary" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"approved commit summary"* ]] || \
    [[ "${output}${stderr}" == *"Prepare a summary"* ]]
}

@test "commits and ff-pushes to live when summary is fresh" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'memory: add notes\n' > "$msgfile"

  bash "$HOOK"
  wt=$(git -C memory rev-parse worktree)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ ! -f "$msgfile" ]
}

@test "exits 1 with /gitlore:resolve hint when branch diverged from live" {
  make_parent_with_memory
  (
    cd memory
    git checkout -q live
    echo "live-only" > MEMORY.md
    git commit -aq -m "Diverging commit on live"
    git checkout -q worktree
  )
  echo dirty > memory/notes.md
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'memory: add notes\n' > "$msgfile"

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"/gitlore:resolve"* ]]
}
