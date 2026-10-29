#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/gh-mock

COMMIT_MEMORY="$PLUGIN_ROOT/scripts/commit-memory.sh"
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
  [[ "${output}${stderr}" == *"commit-memory"* ]]
  [[ "${output}${stderr}" != *"PARENT"* ]]
}

@test "the blessed commit-memory path passes the gate and records memory" {
  make_parent_with_memory
  wire_gate
  echo dirty > memory/notes.md

  run bash "$COMMIT_MEMORY" <<'EOF'
== memory ==
memory: add notes
EOF
  [ "$status" -eq 0 ]
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" = "$live" ]
}

# D58: the parent commit no longer meets the FR11 gate. The approval is asked
# for by the agent before it calls commit-memory.sh, so a subagent whose parent
# commit used to block now commits and records the gitlink it found.
@test "a parent commit over dirty, unapproved memory succeeds and records the gitlink it found" {
  export CLAUDECODE=1
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory
  git commit -q -m "install gitlore"
  found=$(git -C memory rev-parse HEAD)
  echo dirty > memory/notes.md
  echo change > tracked.txt
  git add tracked.txt

  run git commit -m "parent change over dirty memory"
  [ "$status" -eq 0 ]
  [ "$(git rev-parse HEAD:memory)" = "$found" ]
  # Nothing approved, so nothing was committed in memory on the way.
  [ "$(git -C memory rev-parse HEAD)" = "$found" ]
  [ -n "$(git -C memory status --porcelain)" ]
}
