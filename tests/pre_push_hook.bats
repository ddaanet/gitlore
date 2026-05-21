#!/usr/bin/env bats

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
    cd memory
    git checkout -q live
    echo new-fact > FACT.md
    git add FACT.md
    git commit -q -m "Add fact"
  )
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}
teardown() { teardown_tmp_repo; }

@test "pre-push pushes memory live to its origin" {
  run bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  local_sha=$(git -C memory rev-parse live)
  remote_sha=$(git --git-dir="$MEMORY_REMOTE" rev-parse live)
  [ "$local_sha" = "$remote_sha" ]
}

@test "pre-push fails with /gitlore:resolve hint when memory has no remote" {
  git -C memory remote remove origin
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"/gitlore:resolve"* ]] || [[ "${output}${stderr}" == *"no remote"* ]]
}

@test "pre-push fails with divergence hint when remote diverged" {
  (
    cd "$(mktemp -d "$TMP_REPO/clone.XXXXXX")"
    git clone -q "$MEMORY_REMOTE" .
    git checkout -q live
    echo remote-only > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "remote-only commit"
    git push -q origin live
  )
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"diverged"* ]] || [[ "${output}${stderr}" == *"/gitlore:resolve"* ]]
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
