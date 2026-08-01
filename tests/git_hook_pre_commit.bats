#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures

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
  [[ "${output}${stderr}" == *blockquote* ]]   # present as a draft (> ...), not a code fence
}

@test "dirty-no-summary hint interpolates the canonical memory-approval clause" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  clause=$(cat "$PLUGIN_ROOT/reference/memory-approval-clause.txt")
  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"$clause"* ]]
}

@test "commits and ff-pushes to live when summary is fresh" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  bash "$HOOK"
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ ! -f "$msgfile" ]
}

@test "exits 1 with memory-merger directive when branch diverged from live" {
  make_parent_with_memory
  # `live` advances behind the detached worktree's back (D17 branch model:
  # `live` is never checked out, so this is plumbing, not a checkout dance).
  advance_branch_with_file memory live LIVE.md live-only "Diverging commit on live"
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"flavor=head-vs-live"* ]]
  [[ "$output$stderr" == *"continue-after-merge"* ]]
}

@test "resolves PLUGIN_ROOT from gitlore.hooksDir when CLAUDE_PLUGIN_ROOT is unset" {
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  unset CLAUDE_PLUGIN_ROOT
  run bash "$HOOK"
  [ "$status" -eq 0 ]
}

@test "commit path leaves HEAD detached at the advanced live" {
  # The D17 branch model's core invariant: the commit path must never attach
  # HEAD to a branch, and `live` must land on the new commit.
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  bash "$HOOK"
  run git -C memory symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  head=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$head" = "$live" ]
  # `live` is the only branch the commit path touches — no per-worktree branch
  # is created or advanced alongside it.
  run git -C memory for-each-ref --format='%(refname:short)' --points-at HEAD refs/heads
  [ "$output" = "live" ]
}

@test "a memory pointer that cannot be staged is reported, not a bare git error" {
  # Both staging branches end the same way — the commit records a stale memory
  # SHA — so both have to say so. Without a message `set -e` aborts the commit
  # on git's own "Unable to create index.lock" and nothing connects that to the
  # memory pointer. This is the branch git takes when the hook runs with no
  # GIT_INDEX_FILE (a direct invocation, or a hook manager that does not export
  # it).
  make_parent_with_memory
  # A stranded lock is the realistic cause, and it fails `git add` for real.
  : > .git/index.lock

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  rm -f .git/index.lock
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"pointer could not be staged"* ]]
  [[ "$output$stderr" == *"stale memory SHA"* ]]
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
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  # Simulate the leaked env. Relative paths matter — git uses them under
  # whatever CWD `git -C ...` switches to.
  export GIT_DIR=.git
  export GIT_INDEX_FILE=.git/index
  export GIT_WORK_TREE=.

  # Git's message, not gitlore's, so the pairing has to provoke it: the same
  # leaked environment, aimed at the submodule the hook works in. One assertion
  # shows the message is still what this git prints and that this fixture
  # reaches the producer; the other shows the hook clears the leak first.
  run --separate-stderr git -C memory status --porcelain
  [ "$status" -ne 0 ]
  [[ "${output}${stderr}" == *"$GITLORE_T_LEAKED_GITDIR"* ]]

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  unset GIT_DIR GIT_INDEX_FILE GIT_WORK_TREE
  [ "$status" -eq 0 ]
  [[ "${output}${stderr}" != *"$GITLORE_T_LEAKED_GITDIR"* ]]
  # And the commit-and-push path actually fired:
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
}

@test "ignores parent GIT_COMMON_DIR/GIT_OBJECT_DIRECTORY leaked in a linked worktree" {
  # Regression: in a linked parent worktree git exports GIT_COMMON_DIR (and
  # GIT_OBJECT_DIRECTORY) alongside GIT_DIR. A hand-picked 4-var unset leaves
  # GIT_COMMON_DIR set, silently redirecting the submodule's refs/objects to the
  # parent's common dir. The hook must clear the full local-env-var set. This
  # points the parent's store at a bogus path: if the hook leaked it, the
  # submodule sync would touch that path and fail or write the wrong refs.
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  printf 'memory: add notes\n' > "$msgfile"

  bogus="$TMP_REPO/.bogus-common-dir"
  mkdir -p "$bogus"
  export GIT_COMMON_DIR="$bogus"
  export GIT_OBJECT_DIRECTORY="$bogus/objects"

  CLAUDECODE=1 run --separate-stderr bash "$HOOK"
  unset GIT_COMMON_DIR GIT_OBJECT_DIRECTORY
  [ "$status" -eq 0 ]
  # The submodule's own live ref advanced — refs were written to the submodule
  # store, not the bogus parent common dir.
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ ! -e "$bogus/refs/heads/live" ]
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
