#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

PRECOMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"
EMIT_GATE="$PLUGIN_ROOT/scripts/emit-memory-gate.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

# Wire the live gate: emit the submodule wrapper and point it at the real plugin.
wire_gate() {
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  bash "$EMIT_GATE"
}

@test "a naked 'git -C memory commit' is blocked by the gate" {
  make_parent_with_memory
  wire_gate
  echo dirty > memory/notes.md
  git -C memory add -A
  CLAUDECODE=1 run --separate-stderr git -C memory commit -m "sneaky direct commit"
  [ "$status" -ne 0 ]
  [[ "${output}${stderr}" == *"blocked"* ]]
  [[ "${output}${stderr}" == *"commit the PARENT"* ]]
}

@test "the blessed parent pre-commit path passes the gate and records memory" {
  make_parent_with_memory
  wire_gate
  echo dirty > memory/notes.md
  msgfile=$(git -C memory rev-parse --git-path gitlore-commit-msg)
  printf 'memory: add notes\n' > "$msgfile"

  run bash "$PRECOMMIT"
  [ "$status" -eq 0 ]
  wt=$(git -C memory rev-parse worktree)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
  [ ! -f "$msgfile" ]
}
