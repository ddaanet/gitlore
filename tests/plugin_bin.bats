#!/usr/bin/env bats
# D70 commit 1: the plugin's bin/ names, inspected as the distributed plugin
# ships them. Claude Code puts a plugin's bin/ on PATH
# directly (no symlink), so each name must work when run by its own path with no
# CLAUDE_PLUGIN_ROOT in the environment.

load helpers/setup

# Runs "$@" by path from a fresh non-gitlore git repo under `env -i`, so only
# PATH and HOME survive: nothing in the environment can locate the plugin.
run_bare() {
  local dir
  dir="$(mktemp -d)"
  git -C "$dir" init -q
  # shellcheck disable=SC2016 # $1 expands in the inner shell
  run env -i PATH="$PATH" HOME="$HOME" bash -c 'cd "$1" && shift && "$@"' _ "$dir" "$@" </dev/null
  rm -rf "$dir"
}

@test "bin: dist.include lists bin" {
  grep -qxF 'bin' "$PLUGIN_ROOT/dist.include"
}

@test "bin: gitlore-commit is executable and reaches commit-memory.sh" {
  [ -x "$PLUGIN_ROOT/bin/gitlore-commit" ]
  run_bare "$(cd "$PLUGIN_ROOT" && pwd)/bin/gitlore-commit" --bogus
  # Not an exec failure (126 not executable, 127 not found).
  [ "$status" -ne 126 ]
  [ "$status" -ne 127 ]
  # commit-memory.sh's own usage refusal.
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: gitlore-commit"* ]]
}

@test "bin: gitlore-push is executable and reaches push-memory.sh" {
  [ -x "$PLUGIN_ROOT/bin/gitlore-push" ]
  run_bare "$(cd "$PLUGIN_ROOT" && pwd)/bin/gitlore-push"
  [ "$status" -ne 126 ]
  [ "$status" -ne 127 ]
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to publish"* ]]
}

@test "bin: gitlore-merge is executable and reaches merge-memory.sh" {
  [ -x "$PLUGIN_ROOT/bin/gitlore-merge" ]
  run_bare "$(cd "$PLUGIN_ROOT" && pwd)/bin/gitlore-merge"
  [ "$status" -ne 126 ]
  [ "$status" -ne 127 ]
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to reconcile"* ]]
}

@test "bin: gitlore-add-tier is executable and reaches add-tier.sh" {
  [ -x "$PLUGIN_ROOT/bin/gitlore-add-tier" ]
  # A non-gitlore repo with no stdin: add-tier.sh's own refusal.
  run_bare "$(cd "$PLUGIN_ROOT" && pwd)/bin/gitlore-add-tier"
  [ "$status" -ne 126 ]
  [ "$status" -ne 127 ]
  [ "$status" -eq 1 ]
  [[ "$output" == *"gitlore: add-tier failed"* ]]
}

@test "bin: gitlore-compose is executable and reaches its script" {
  [ -x "$PLUGIN_ROOT/bin/gitlore-compose" ]
  # A non-gitlore repo: whatever the script says there, it is not an exec failure.
  run_bare "$(cd "$PLUGIN_ROOT" && pwd)/bin/gitlore-compose"
  [ "$status" -ne 126 ]
  [ "$status" -ne 127 ]
  [ "$status" -eq 0 ]
}

@test "bin: the retired -memory names are gone and exactly the five short names ship" {
  for old in gitlore-commit-memory gitlore-push-memory gitlore-merge-memory; do
    [ ! -e "$PLUGIN_ROOT/bin/$old" ]
  done
  [ "$(find "$PLUGIN_ROOT/bin" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort | paste -sd, -)" = "gitlore-add-tier,gitlore-commit,gitlore-compose,gitlore-merge,gitlore-push" ]
}
