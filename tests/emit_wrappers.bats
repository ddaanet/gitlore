#!/usr/bin/env bats

load helpers/setup

EMIT="$PLUGIN_ROOT/scripts/emit-wrappers.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "emit-wrappers writes both wrapper files and makes them executable" {
  run bash "$EMIT"
  [ "$status" -eq 0 ]
  [ -x .git/gitlore-pre-commit ]
  [ -x .git/gitlore-pre-push ]
}

@test "wrapper exits 0 with hint when gitlore.hooksDir unset" {
  bash "$EMIT"
  run .git/gitlore-pre-commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore skipped"* ]] || \
    [[ "$(cat <<<"$output")" == *"gitlore skipped"* ]]
}

@test "wrapper execs the real hook when gitlore.hooksDir set" {
  bash "$EMIT"
  fake="$TMP_REPO/fakehooks"
  mkdir -p "$fake"
  cat > "$fake/pre-commit" <<'EOF'
#!/usr/bin/env bash
echo "real-hook-ran"
exit 0
EOF
  chmod +x "$fake/pre-commit"
  git config gitlore.hooksDir "$fake"
  run .git/gitlore-pre-commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"real-hook-ran"* ]]
}

@test "wrapper exits 0 with hint when gitlore.hooksDir is set but GC'd" {
  bash "$EMIT"
  # Point hooksDir at a directory that does not contain the hook (simulates a
  # plugin upgrade that GC'd the old version's cache before SessionStart re-pins).
  git config gitlore.hooksDir "$TMP_REPO/gone-cache/scripts/git-hooks"
  run .git/gitlore-pre-commit
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore skipped"* ]]
  [[ "$output" == *"stale"* ]]
}

@test "emit-wrappers is idempotent" {
  bash "$EMIT"
  cp .git/gitlore-pre-commit .git/gitlore-pre-commit.before
  bash "$EMIT"
  diff .git/gitlore-pre-commit .git/gitlore-pre-commit.before
}

@test "emit-wrappers in a linked worktree writes to the shared common dir, not the gitlink file" {
  echo seed > f && git add f && git commit -q -m seed
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat "$WT" >/dev/null 2>&1
  ( cd "$WT" && bash "$EMIT" )
  # The wrapper must land in the shared common dir (= the main worktree's .git),
  # NOT next to the gitlink file (which would fail to write).
  [ -x "$TMP_REPO/.git/gitlore-pre-commit" ]
  [ -x "$TMP_REPO/.git/gitlore-pre-push" ]
  rm -rf "$WT"
}
