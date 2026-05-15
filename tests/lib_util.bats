#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "gitlore_memory_path returns empty when no .gitmodules" {
  run gitlore_memory_path
  [ "$status" -ne 0 ]
}

@test "gitlore_memory_path reads from .gitmodules using gitlore-memory submodule name" {
  cat > .gitmodules <<'EOF'
[submodule "gitlore-memory"]
  path = memory
  url = ./bare.git
EOF
  run gitlore_memory_path
  [ "$status" -eq 0 ]
  [ "$output" = "memory" ]
}

@test "gitlore_memory_path supports custom subpath" {
  cat > .gitmodules <<'EOF'
[submodule "gitlore-memory"]
  path = .claude/memory
  url = ./bare.git
EOF
  run gitlore_memory_path
  [ "$status" -eq 0 ]
  [ "$output" = ".claude/memory" ]
}

@test "gitlore_has_submodule returns 1 when missing" {
  run gitlore_has_submodule
  [ "$status" -eq 1 ]
}

@test "gitlore_has_submodule returns 0 when present" {
  cat > .gitmodules <<'EOF'
[submodule "gitlore-memory"]
  path = memory
  url = ./bare.git
EOF
  run gitlore_has_submodule
  [ "$status" -eq 0 ]
}
