#!/usr/bin/env bats

load helpers/setup

WIRE_LEFTHOOK="$PLUGIN_ROOT/scripts/hook-manager/wire-lefthook.sh"

setup() {
  setup_tmp_repo
  cat > lefthook.yml <<'EOF'
pre-commit:
  commands:
    eslint:
      run: eslint {staged_files}
EOF
}
teardown() { teardown_tmp_repo; }

@test "wire-lefthook adds gitlore command under pre-commit and pre-push" {
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' lefthook.yml
  grep -q '.git/gitlore-pre-commit' lefthook.yml
  grep -q '.git/gitlore-pre-push' lefthook.yml
}

@test "wire-lefthook is idempotent (marker present → no change)" {
  bash "$WIRE_LEFTHOOK"
  cp lefthook.yml lefthook.yml.before
  bash "$WIRE_LEFTHOOK"
  diff lefthook.yml lefthook.yml.before
}

@test "wire-lefthook writes sentinel file" {
  mkdir -p .claude
  bash "$WIRE_LEFTHOOK"
  [ -f .claude/gitlore-hook-setup ]
  [ "$(cat .claude/gitlore-hook-setup)" = "lefthook install" ]
}

@test "wire-lefthook preserves existing pre-commit commands" {
  bash "$WIRE_LEFTHOOK"
  grep -q 'eslint' lefthook.yml
  grep -q '.git/gitlore-pre-commit' lefthook.yml
}

@test "wire-lefthook works with .lefthook.yml filename" {
  mv lefthook.yml .lefthook.yml
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 0 ]
  grep -q '# gitlore: managed' .lefthook.yml
}

@test "wire-lefthook exits 1 when no config found" {
  rm lefthook.yml
  run bash "$WIRE_LEFTHOOK"
  [ "$status" -eq 1 ]
}
