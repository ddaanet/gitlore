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

@test "emit-wrappers is idempotent" {
  bash "$EMIT"
  cp .git/gitlore-pre-commit .git/gitlore-pre-commit.before
  bash "$EMIT"
  diff .git/gitlore-pre-commit .git/gitlore-pre-commit.before
}
