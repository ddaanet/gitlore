#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/gh-mock

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
}
teardown() { teardown_tmp_repo; }

@test "resolve: errors when no memory submodule registered" {
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"not installed"* ]] || [[ "$output$stderr" == *"/gitlore:install"* ]]
}

@test "resolve: derives plugin root from \$0 when CLAUDE_PLUGIN_ROOT is unset" {
  # Dogfood-driven: continuation commands run from sub-agents whose shell may
  # not inherit CLAUDE_PLUGIN_ROOT. The script must derive its root from $0.
  unset CLAUDE_PLUGIN_ROOT
  run --separate-stderr bash "$RESOLVE"
  # Either "not installed" (gitmodules empty) or some other gitlore-prefixed
  # message — never "CLAUDE_PLUGIN_ROOT must be set".
  [[ "$output$stderr" != *"CLAUDE_PLUGIN_ROOT must be set"* ]]
}

@test "resolve: creates remote when memory has no origin.url" {
  make_parent_with_memory
  git -C memory remote remove origin 2>/dev/null || true
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  grep -q 'repo create' "$log"
  [ -n "$(git -C memory config --get remote.origin.url)" ]
}

@test "resolve: reports unreachable remote without calling gh repo create" {
  make_parent_with_memory
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin /does/not/exist.git
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"unreachable"* ]] || [[ "$output$stderr" == *"network"* ]] || [[ "$output$stderr" == *"auth"* ]]
  ! grep -q 'repo create' "$log" 2>/dev/null
}

@test "resolve: pushes live when remote exists but has no live branch" {
  make_parent_with_memory
  bare="$TMP_REPO/.recover-remote.git"
  git init -q --bare "$bare"
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin "$bare"
  run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  remote_live=$(git --git-dir="$bare" rev-parse live 2>/dev/null || echo MISSING)
  [ "$remote_live" != "MISSING" ]
}

@test "resolve: no-op when healthy" {
  make_parent_with_memory
  bare="$TMP_REPO/.healthy-remote.git"
  git init -q --bare "$bare"
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin "$bare"
  git -C memory push -q origin live
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  ! grep -q 'repo create' "$log" 2>/dev/null
}
