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

@test "exits 1 with memory-merger directive when branch diverged from live" {
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
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"flavor=branch-vs-live"* ]]
  [[ "$output$stderr" == *"continue-after-branch-merge"* ]]
}

@test "resolves PLUGIN_ROOT from gitlore.hooksDir when CLAUDE_PLUGIN_ROOT is unset" {
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  unset CLAUDE_PLUGIN_ROOT
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "commits and ff-pushes to live from detached HEAD" {
  make_parent_with_memory
  (cd memory && git checkout -q --detach worktree)
  echo dirty > memory/notes.md
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'memory: add notes\n' > "$msgfile"

  bash "$HOOK"
  head=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$head" = "$live" ]
}

@test "ignores parent GIT_DIR/GIT_INDEX_FILE leaked by 'git commit'" {
  # Regression: when git invokes the pre-commit hook, it sets GIT_DIR /
  # GIT_INDEX_FILE / GIT_WORK_TREE to relative paths under the parent repo.
  # `git -C memory <cmd>` inherits them and tries to resolve `.git/index` under
  # the submodule's gitfile, producing "fatal: .git/index: index file open
  # failed: Not a directory". The hook must unset these before touching the
  # submodule. Reproduced before fix; this test pins the fix.
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'memory: add notes\n' > "$msgfile"

  # Simulate the leaked env. Relative paths matter — git uses them under
  # whatever CWD `git -C ...` switches to.
  export GIT_DIR=.git
  export GIT_INDEX_FILE=.git/index
  export GIT_WORK_TREE=.

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
  [ "$status" -eq 0 ]
  [[ "${output}${stderr}" != *"index file open failed"* ]]
  # And the commit-and-push path actually fired:
  wt=$(git -C memory rev-parse worktree)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
}

@test "exits 0 in a session-less linked worktree where the memory worktree is absent" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  [ ! -e "$WT/memory/.git" ]   # git created the gitlink dir but did not init the submodule
  cd "$WT"
  run bash "$HOOK"
  [ "$status" -eq 0 ]
  rm -rf "$WT"
}
