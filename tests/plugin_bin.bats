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

@test "bin: gitlore-commit-memory is executable and reaches commit-memory.sh" {
  [ -x "$PLUGIN_ROOT/bin/gitlore-commit-memory" ]
  run_bare "$(cd "$PLUGIN_ROOT" && pwd)/bin/gitlore-commit-memory" --bogus
  # Not an exec failure (126 not executable, 127 not found).
  [ "$status" -ne 126 ]
  [ "$status" -ne 127 ]
  # commit-memory.sh's own usage refusal.
  [ "$status" -eq 2 ]
  [[ "$output" == *"usage: commit-memory.sh"* ]]
}

@test "bin: gitlore-push-memory is executable and reaches push-memory.sh" {
  [ -x "$PLUGIN_ROOT/bin/gitlore-push-memory" ]
  run_bare "$(cd "$PLUGIN_ROOT" && pwd)/bin/gitlore-push-memory"
  [ "$status" -ne 126 ]
  [ "$status" -ne 127 ]
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to publish"* ]]
}

@test "bin: gitlore-merge-memory is executable and reaches merge-memory.sh" {
  [ -x "$PLUGIN_ROOT/bin/gitlore-merge-memory" ]
  run_bare "$(cd "$PLUGIN_ROOT" && pwd)/bin/gitlore-merge-memory"
  [ "$status" -ne 126 ]
  [ "$status" -ne 127 ]
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing to reconcile"* ]]
}
