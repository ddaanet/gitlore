#!/usr/bin/env bats

load helpers/setup

EMIT="$PLUGIN_ROOT/scripts/emit-wrappers.sh"

setup()    { setup_tmp_repo; }
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

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
  [[ "$output" == *"gitlore skipped"* ]]
  # "gitlore skipped" alone is emitted by BOTH branches: drop the -z guard and
  # an empty HOOKS_DIR falls through to the stale branch, which says the plugin
  # was upgraded when it was never installed. Pin the discriminator...
  [[ "$output" == *"not installed"* ]]
  # ...and the recovery act, which is the only thing this exit-0 path gives the
  # user (NFR8/D5). Token, not sentence: rewording stays free.
  [[ "$output" == *"marketplace"* ]]
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
  [[ "$output" == *"claude -c"* ]]   # the recovery act for this branch
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
  git worktree add -q -b feat "$WT" >/dev/null
  ( cd "$WT" && bash "$EMIT" )
  # The wrapper must land in the shared common dir (= the main worktree's .git),
  # NOT next to the gitlink file (which would fail to write).
  [ -x "$TMP_REPO/.git/gitlore-pre-commit" ]
  [ -x "$TMP_REPO/.git/gitlore-pre-push" ]
}
