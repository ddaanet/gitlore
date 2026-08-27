#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  # Add a memory commit so we have something to push.
  (
    cd memory || exit 1
    git checkout -q live
    echo new-fact > FACT.md
    git add FACT.md
    git commit -q -m "Add fact"
  )
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  [ -n "${CLONE:-}" ] && rm -rf "$CLONE"
  teardown_tmp_repo
}

@test "pre-push pushes memory live to its origin" {
  run bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  local_sha=$(git -C memory rev-parse live)
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  [ "$local_sha" = "$remote_sha" ]
}

@test "pre-push lets the parent push through when memory has no remote" {
  git -C memory remote remove origin
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"no remote of its own"* ]]
}

@test "pre-push fails with divergence hint when remote diverged" {
  (
    clone_dir=$(mktemp -d "$TMP_REPO/clone.XXXXXX") || exit 1
    cd "$clone_dir" || exit 1
    git clone -q "$MEMORY_REMOTE" .
    git checkout -q live
    echo remote-only > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "remote-only commit"
    git push -q origin live
  )
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"flavor=head-vs-remote"* ]]
  [[ "$output$stderr" == *"continue-after-merge"* ]]
}

@test "pre-push fails when remote is unreachable" {
  git -C memory remote set-url origin /this/path/does/not/exist.git
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"unreachable"* ]] || [[ "${output}${stderr}" == *"network"* ]]
}

@test "pre-push is a no-op when no submodule registered" {
  rm -f .gitmodules
  run bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
}

@test "exits 0 in a session-less linked worktree where the memory worktree is absent" {
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  run bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
}

# The skip at the top of the hook is silent by design so a session-less worktree
# never blocks the parent push. But it also fires when memory IS initialized in
# this clone and its pinned commit sits ahead of the memory remote — and then the
# parent push publishes a gitlink nobody can resolve. The three cases below pin
# the discrimination: warn only when the committed gitlink is not already
# reachable on the memory remote.

@test "memory-absent skip warns when the committed gitlink is unpublished" {
  # memory `live` is one commit ahead of its origin (setup made it so). Commit
  # that gitlink in the parent, then push from a worktree with no memory.
  git add memory
  git commit -q -m "Bump memory gitlink"
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null
  [ ! -e "$WT/memory/.git" ]
  cd "$WT"
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"not checked out"* ]]
  [[ "$output$stderr" == *"submodule update --init"* ]]
}

@test "memory-absent skip stays silent when the gitlink is already published" {
  git -C memory push -q origin HEAD:live
  git add memory
  git commit -q -m "Bump memory gitlink"
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null
  cd "$WT"
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  [ -z "$output$stderr" ]
}

@test "memory-absent skip stays silent when memory was never initialized here" {
  # Fresh-clone shape: the module store does not exist, so nothing local can be
  # ahead of the remote and there is nothing to warn about.
  CLONE="$TMP_REPO-clone"
  git clone -q "$TMP_REPO" "$CLONE"
  cd "$CLONE"
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  [ ! -e "$(git rev-parse --git-path modules/gitlore-memory)" ]
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  [ -z "$output$stderr" ]
  cd "$TMP_REPO"
}
