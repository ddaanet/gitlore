#!/usr/bin/env bats

load helpers/setup
load helpers/gh-mock

RUN_INSTALL="$PLUGIN_ROOT/scripts/install/run.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  # The install flow calls `gh repo view <name> --json sshUrl -q .sshUrl` to
  # discover the remote URL; the mock returns this when GH_MOCK_REMOTE_URL is set.
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
}
teardown() { teardown_tmp_repo; }

@test "install configures memory submodule remote via gh repo create" {
  bash "$RUN_INSTALL" memory "echo precommit"
  url=$(git -C memory config --get remote.origin.url 2>/dev/null || true)
  [ -n "$url" ]
}

@test "install rewrites .gitmodules URL from placeholder to real remote" {
  bash "$RUN_INSTALL" memory "echo precommit"
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" != *"gitlore-placeholder"* ]]
}

@test "install records gh repo create with --private (no --source flag)" {
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo precommit"
  grep -q 'repo create' "$log"
  grep -q -- '--private' "$log"
  # --source=. is intentionally omitted: gh's --source rejects gitfile-pointed
  # submodule worktrees, so we wire origin and push by hand instead.
  ! grep -q -- '--source' "$log"
}

@test "install completes local-only when gh is unauthed (no abort)" {
  GH_MOCK_EXIT_AUTH_STATUS=1 run --separate-stderr bash "$RUN_INSTALL" memory "echo pc"
  [ "$status" -eq 0 ]
  [ -d memory ]
  [ -f .claude/settings.json ]
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" == *"gitlore-placeholder"* ]]
}

@test "install aborts cleanly when gh repo create fails (name collision)" {
  GH_MOCK_EXIT_REPO_CREATE=1 \
    GH_MOCK_STDERR_REPO_CREATE="GraphQL: Name already exists on this account" \
    run --separate-stderr bash "$RUN_INSTALL" memory "echo precommit"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"/gitlore:resolve"* ]]
}

@test "install is idempotent (no second gh repo create call on re-run)" {
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo precommit"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo precommit"
  count=$(grep -c 'repo create' "$log" || true)
  [ "$count" -eq 1 ]
}

@test "auto mode with no gh leaves a local-only install (placeholder URL kept)" {
  # Build a PATH without gh but with the tools run.sh needs.
  local no_gh_bin="$TMP_REPO/.no-gh-bin"
  mkdir -p "$no_gh_bin"
  for tool in bash sh git jq mktemp mv dirname basename find grep sed awk sort cat cp rm mkdir touch chmod tail stat; do
    bin=$(command -v "$tool" 2>/dev/null || true)
    [ -n "$bin" ] && ln -sf "$bin" "$no_gh_bin/$tool"
  done
  GITLORE_HOME="$TMP_REPO/.test-home" PATH="$no_gh_bin" run --separate-stderr bash "$RUN_INSTALL" memory "echo pc"
  [ "$status" -eq 0 ]
  [ -d memory ]
  [ -f .claude/settings.json ]
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" == *"gitlore-placeholder"* ]]
  [[ "$stderr" == *"local-only"* ]]
}

@test "url mode wires an existing remote and pushes live" {
  local remote="$TMP_REPO/.existing-remote.git"
  git init -q --bare "$remote"
  bash "$RUN_INSTALL" memory "echo pc" url "$remote"
  url=$(git -C memory config --get remote.origin.url)
  [ "$url" = "$remote" ]
  # live was pushed to the existing remote.
  git -C "$remote" show-ref --verify --quiet refs/heads/live
  gm=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [ "$gm" = "$remote" ]
}

@test "local mode keeps placeholder and never calls gh" {
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo pc" local
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" == *"gitlore-placeholder"* ]]
  [ ! -f "$log" ] || ! grep -q 'repo create' "$log"
}

@test "auto mode (gh available) names the remote <parent-base>-memory" {
  git remote add origin "https://github.com/acme/project.git"
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo pc"
  grep -q 'repo create' "$log"
  grep -q 'project-memory' "$log"
}

@test "auto mode creates a public remote when the parent is public" {
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY="PUBLIC"
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory "echo pc"
  grep -q -- '--public' "$log"
}
