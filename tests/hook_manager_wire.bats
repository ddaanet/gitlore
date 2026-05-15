#!/usr/bin/env bats

load helpers/setup

WIRE_LEFTHOOK="$PLUGIN_ROOT/scripts/hook-manager/wire-lefthook.sh"
WIRE_HUSKY="$PLUGIN_ROOT/scripts/hook-manager/wire-husky.sh"

# setup() creates a bare tmp repo only; individual tests seed their own
# fixtures so lefthook and husky tests remain independent.
setup() {
  setup_tmp_repo
}
teardown() { teardown_tmp_repo; }

# ---------------------------------------------------------------------------
# lefthook tests — each seeds lefthook.yml before calling the script
# ---------------------------------------------------------------------------

@test "wire-lefthook adds gitlore command under pre-commit and pre-push" {
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' lefthook.yml
  grep -q '.git/gitlore-pre-commit' lefthook.yml
  grep -q '.git/gitlore-pre-push' lefthook.yml
}

@test "wire-lefthook is idempotent (marker present → no change)" {
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  bash "$WIRE_LEFTHOOK"
  cp lefthook.yml lefthook.yml.before
  bash "$WIRE_LEFTHOOK"
  diff lefthook.yml lefthook.yml.before
}

@test "wire-lefthook writes sentinel file" {
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  mkdir -p .claude
  bash "$WIRE_LEFTHOOK"
  [ -f .claude/gitlore-hook-setup ]
  [ "$(cat .claude/gitlore-hook-setup)" = "lefthook install" ]
}

@test "wire-lefthook preserves existing pre-commit commands" {
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  bash "$WIRE_LEFTHOOK"
  grep -q 'eslint' lefthook.yml
  grep -q '.git/gitlore-pre-commit' lefthook.yml
}

@test "wire-lefthook works with .lefthook.yml filename" {
  cat > .lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' .lefthook.yml
}

@test "wire-lefthook exits 1 when no config found" {
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# husky tests — start from clean state (no lefthook.yml)
# ---------------------------------------------------------------------------

@test "wire-husky appends guarded exec lines to .husky/pre-commit and pre-push" {
  mkdir .husky
  : > .husky/pre-commit
  : > .husky/pre-push
  run bash "$WIRE_HUSKY"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' .husky/pre-commit
  grep -q 'exec .git/gitlore-pre-commit' .husky/pre-commit
  grep -q '# gitlore: managed' .husky/pre-push
  grep -q 'exec .git/gitlore-pre-push' .husky/pre-push
}

@test "wire-husky creates missing pre-* files" {
  mkdir .husky
  bash "$WIRE_HUSKY"
  [ -f .husky/pre-commit ]
  [ -f .husky/pre-push ]
}

@test "wire-husky is idempotent" {
  mkdir .husky
  bash "$WIRE_HUSKY"
  cp .husky/pre-commit .husky/pre-commit.before
  bash "$WIRE_HUSKY"
  diff .husky/pre-commit .husky/pre-commit.before
}

@test "wire-husky writes sentinel" {
  mkdir .husky .claude
  bash "$WIRE_HUSKY"
  [ "$(cat .claude/gitlore-hook-setup)" = "npx husky" ]
}
