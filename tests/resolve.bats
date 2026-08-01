#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

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
  # The positive is what proves the run got past root derivation: with the
  # variable unset the script still reaches its own logic and says gitlore's
  # own thing. On its own the refutation below cannot tell that apart from a
  # script that died earlier for some other reason.
  [[ "$output$stderr" == *"not installed"* ]] || [[ "$output$stderr" == *"/gitlore:install"* ]]
  [[ "$output$stderr" != *"$GITLORE_T_PLUGIN_ROOT_UNSET"* ]]
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
  run grep -q 'repo create' "$log"
  [ "$status" -ne 0 ]
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

@test "resolve: the merge state file parses when the store path holds a quote" {
  # The state file records the store path, and its first reader is `jq -r
  # .flavor` in the stale-merge guard. A path containing a `"` or a `\` written
  # by string interpolation yields invalid JSON, and the guard's failure surfaces
  # as a blocked commit with a jq syntax error rather than as a merge.
  store="$TMP_REPO/we\"ird \\ store"
  mkdir -p "$store"
  git init -q "$store"
  git -C "$store" config user.email "test@example.com"
  git -C "$store" config user.name "Test"
  echo seed > "$store/SEED.md"
  git -C "$store" add SEED.md
  git -C "$store" commit -q -m seed
  sha=$(git -C "$store" rev-parse HEAD)

  gitlore_write_merge_state "$store" head-vs-live "$sha" "$sha" live continue-after-merge

  statefile=$(gitlore_merge_state_file "$store")
  [ -f "$statefile" ]
  run jq -r .flavor "$statefile"
  [ "$status" -eq 0 ]
  [ "$output" = "head-vs-live" ]
  [ "$(jq -r .store "$statefile")" = "$store" ]
  [ "$(jq -r '.changed_files | type' "$statefile")" = "array" ]
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
  run grep -q 'repo create' "$log"
  [ "$status" -ne 0 ]
}
