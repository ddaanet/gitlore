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

@test "gitlore_probe_writable succeeds on a writable dir" {
  run gitlore_probe_writable "$TMP_REPO"
  [ "$status" -eq 0 ]
}

@test "gitlore_probe_writable fails on a read-only dir" {
  local ro="$TMP_REPO/ro"
  mkdir -p "$ro"
  chmod 555 "$ro"
  run gitlore_probe_writable "$ro"
  chmod 755 "$ro"   # restore so teardown can rm -rf
  [ "$status" -ne 0 ]
}

@test "gitlore_memory_remote_name from https origin" {
  git remote add origin "https://github.com/acme/project.git"
  run gitlore_memory_remote_name
  [ "$status" -eq 0 ]
  [ "$output" = "project-memory" ]
}

@test "gitlore_memory_remote_name from scp-style origin" {
  git remote add origin "git@github.com:acme/project.git"
  run gitlore_memory_remote_name
  [ "$output" = "project-memory" ]
}

@test "gitlore_memory_remote_name from origin without .git suffix" {
  git remote add origin "https://github.com/acme/project"
  run gitlore_memory_remote_name
  [ "$output" = "project-memory" ]
}

@test "gitlore_memory_remote_name falls back to repo basename when no origin" {
  # setup_tmp_repo created the repo with no origin; the dir basename is the temp name.
  run gitlore_memory_remote_name
  [ "$status" -eq 0 ]
  [ "$output" = "$(basename "$TMP_REPO")-memory" ]
}

@test "gitlore_parent_visibility defaults to private with no origin" {
  run gitlore_parent_visibility
  [ "$status" -eq 0 ]
  [ "$output" = "private" ]
}
