#!/usr/bin/env bats
# Each @test is its own subshell; the per-test `export GITLORE_GIT_RETRY_SCHEDULE`
# is consumed by the `run` on the next line within that same test. shellcheck's
# "modified in a subshell / might be lost" is a false positive here.
# shellcheck disable=SC2030,SC2031

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

@test "agent-written IPC files resolve under the parent .claude/, not the gitdir" {
  make_parent_with_memory
  local dir="$TMP_REPO/.claude"
  # The agent writes these, so they must live where the agent can write.
  [ "$(gitlore_commit_msg_file memory)"     = "$dir/gitlore-memory-message" ]
  [ "$(gitlore_commit_trigger_file memory)" = "$dir/gitlore-commit-memory" ]
  [[ "$(gitlore_commit_msg_file memory)"     != *".git/"* ]]
  [[ "$(gitlore_commit_trigger_file memory)" != *".git/"* ]]
}

@test "the nudge marker lives in the memory gitdir, not the working tree" {
  make_parent_with_memory
  # Hook-written (not agent-written), so it can stay in the gitdir where it never
  # dirties git status — nothing to gitignore.
  run gitlore_commit_notified_file memory
  [ "$status" -eq 0 ]
  [[ "$output" == *".git/"*gitlore-nudged ]]
  [[ "$output" != "$TMP_REPO/.claude/"* ]]
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

@test "gitlore_memory_approval_clause prints the canonical clause from reference/" {
  run gitlore_memory_approval_clause
  [ "$status" -eq 0 ]
  [ "$output" = "$(cat "$PLUGIN_ROOT/reference/memory-approval-clause.txt")" ]
  [[ "$output" == *"New, Update, Augment, Reduce, or Remove"* ]]
}

@test "the approval clause opens with the memory-writing review directive" {
  run gitlore_memory_approval_clause
  [ "$status" -eq 0 ]
  [[ "$output" == *'gitlore:memory-writing'* ]]
  # Order is the content here: the review runs BEFORE the summary is drafted,
  # so the directive has to precede the body spec it would otherwise read as a
  # footnote to. Line numbers, not a substring match, since both blocks exist.
  local directive_line body_line
  directive_line=$(printf '%s\n' "$output" | grep -n 'gitlore:memory-writing' | head -1 | cut -d: -f1)
  body_line=$(printf '%s\n' "$output" | grep -n 'The commit message is a subject line' | head -1 | cut -d: -f1)
  [ -n "$directive_line" ]
  [ -n "$body_line" ]
  [ "$directive_line" -lt "$body_line" ]
}

@test "gitlore_is_migration_stub true for a dir holding only the migration breadcrumb" {
  local dir="$TMP_REPO/cc-mem"
  mkdir -p "$dir"
  gitlore_mark_migrated "$dir"
  run gitlore_is_migration_stub "$dir"
  [ "$status" -eq 0 ]
}

@test "gitlore_is_migration_stub false for a dir holding real memory" {
  local dir="$TMP_REPO/cc-mem"
  mkdir -p "$dir"
  printf 'User is a senior engineer.\n' > "$dir/MEMORY.md"
  run gitlore_is_migration_stub "$dir"
  [ "$status" -ne 0 ]
}

@test "gitlore_is_migration_stub false for a dir with no MEMORY.md" {
  local dir="$TMP_REPO/cc-mem"
  mkdir -p "$dir"
  run gitlore_is_migration_stub "$dir"
  [ "$status" -ne 0 ]
}

# --- D13: gitlore_git lock-contention retry wrapper -------------------------

# Install a fake `git` on PATH that fails its first ($1) invocations writing
# the stderr line ($2), then succeeds printing "ok". Counts calls in
# $TMP_REPO/git-calls. Echoes the bin dir to prepend to PATH.
_fake_git() {
  local fail_until="$1" stderr_line="$2"
  local bin="$TMP_REPO/fakebin"
  mkdir -p "$bin"
  printf '0\n' > "$TMP_REPO/git-calls"
  cat > "$bin/git" <<EOF
#!/usr/bin/env bash
n=\$(cat "$TMP_REPO/git-calls")
n=\$((n + 1)); printf '%s\n' "\$n" > "$TMP_REPO/git-calls"
if [ "\$n" -le "$fail_until" ]; then
  printf '%s\n' "$stderr_line" >&2
  exit 128
fi
printf 'ok\n'
exit 0
EOF
  chmod +x "$bin/git"
  printf '%s\n' "$bin"
}

@test "gitlore_git_is_lock_error matches the documented lock signatures" {
  gitlore_git_is_lock_error "fatal: Unable to create '/r/.git/index.lock': File exists."
  gitlore_git_is_lock_error "error: cannot lock ref 'refs/heads/live': unable to..."
  gitlore_git_is_lock_error "fatal: Unable to create '/r/.git/refs/heads/x.lock': File exists"
  gitlore_git_is_lock_error "Another git process seems to be running in this repository"
}

@test "gitlore_git_is_lock_error does NOT match an unrelated error" {
  run gitlore_git_is_lock_error "fatal: not a git repository"
  [ "$status" -ne 0 ]
}

@test "gitlore_git retries on index.lock contention then succeeds" {
  local bin; bin="$(_fake_git 2 "fatal: Unable to create '/r/.git/index.lock': File exists.")"
  export GITLORE_GIT_RETRY_SCHEDULE="0 0 0 0 0 0 0"
  PATH="$bin:$PATH" run gitlore_git commit -m x
  [ "$status" -eq 0 ]
  [[ "$output" == *ok* ]]
  [ "$(cat "$TMP_REPO/git-calls")" = "3" ]   # 2 failures + 1 success
}

@test "gitlore_git fails fast on a non-lock error (no retry)" {
  local bin; bin="$(_fake_git 99 "fatal: not a git repository")"
  export GITLORE_GIT_RETRY_SCHEDULE="0 0 0 0 0 0 0"
  PATH="$bin:$PATH" run gitlore_git commit -m x
  [ "$status" -eq 128 ]
  [ "$(cat "$TMP_REPO/git-calls")" = "1" ]   # called exactly once
}

@test "gitlore_git surfaces the final stderr and exit code after exhausting retries" {
  local bin; bin="$(_fake_git 99 "fatal: Unable to create '/r/.git/index.lock': File exists.")"
  export GITLORE_GIT_RETRY_SCHEDULE="0 0 0"   # 3 retries
  PATH="$bin:$PATH" run gitlore_git commit -m x
  [ "$status" -eq 128 ]
  [[ "$output" == *index.lock* ]]
  [ "$(cat "$TMP_REPO/git-calls")" = "4" ]    # 1 initial + 3 retries
}
