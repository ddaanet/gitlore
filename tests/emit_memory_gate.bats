#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

EMIT="$PLUGIN_ROOT/scripts/emit-memory-gate.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

@test "no-op (exit 0) when there is no gitlore-memory submodule" {
  run bash "$EMIT"
  [ "$status" -eq 0 ]
}

@test "no-op (exit 0) when the submodule worktree is absent (session-less linked worktree)" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  [ ! -e "$WT/memory/.git" ]
  ( cd "$WT" && run bash "$EMIT"; [ "$status" -eq 0 ] || exit 1 )
  rm -rf "$WT"
}

@test "writes an executable pre-commit into the submodule hooks dir" {
  make_parent_with_memory
  run bash "$EMIT"
  [ "$status" -eq 0 ]
  hookfile="$(git -C memory rev-parse --git-path hooks)/pre-commit"
  [ -x "$hookfile" ]
}

@test "emitted wrapper exits 0 with hint when gitlore.hooksDir is unset" {
  make_parent_with_memory
  bash "$EMIT"
  hookfile="$(git -C memory rev-parse --git-path hooks)/pre-commit"
  git config --unset gitlore.hooksDir 2>/dev/null || true
  run "$hookfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore skipped"* ]]
}

@test "emitted wrapper exits 0 with hint when gitlore.hooksDir is stale (GC'd)" {
  make_parent_with_memory
  bash "$EMIT"
  hookfile="$(git -C memory rev-parse --git-path hooks)/pre-commit"
  git config gitlore.hooksDir "$TMP_REPO/gone-cache/scripts/git-hooks"
  run "$hookfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore skipped"* ]]
  [[ "$output" == *"stale"* ]]
}

@test "emitted wrapper execs memory-pre-commit when gitlore.hooksDir is set" {
  make_parent_with_memory
  bash "$EMIT"
  hookfile="$(git -C memory rev-parse --git-path hooks)/pre-commit"
  fake="$TMP_REPO/fakehooks"
  mkdir -p "$fake"
  printf '#!/usr/bin/env sh\necho memory-gate-ran\nexit 0\n' > "$fake/memory-pre-commit"
  chmod +x "$fake/memory-pre-commit"
  git config gitlore.hooksDir "$fake"
  run "$hookfile"
  [ "$status" -eq 0 ]
  [[ "$output" == *"memory-gate-ran"* ]]
}

@test "emit-memory-gate is idempotent" {
  make_parent_with_memory
  bash "$EMIT"
  hookfile="$(git -C memory rev-parse --git-path hooks)/pre-commit"
  cp "$hookfile" "$hookfile.before"
  bash "$EMIT"
  diff "$hookfile" "$hookfile.before"
}
