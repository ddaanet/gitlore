#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# Each @test is its own subshell; per-test exports are consumed within that same
# test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2154,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/gh-mock

RUN_INSTALL="$PLUGIN_ROOT/scripts/install/run.sh"

setup() {
  setup_tmp_repo
  isolate_home
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  # The install flow calls `gh repo view <name> --json sshUrl -q .sshUrl` to
  # discover the remote URL; the mock returns this when GH_MOCK_REMOTE_URL is set.
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
}
teardown() { teardown_tmp_repo; }

# Stand in for a GitHub repository: a bare repo that every git operation
# addressed to $1 (an ssh or https literal) reaches through insteadOf. What git
# stores in config stays the literal, so a test can tell the ssh url the remote
# keeps from the https url `.gitmodules` records. $2 names the bare repo.
fake_github_repo() {
  local bare="$TMP_REPO/.fake-github/${2:?}.git"
  git init -q --bare "$bare"
  git config --global "url.$bare.insteadOf" "$1"
}

@test "install configures memory submodule remote via gh repo create" {
  bash "$RUN_INSTALL" memory
  url=$(git -C memory config --get remote.origin.url || true)
  [ -n "$url" ]
}

@test "install rewrites .gitmodules URL from placeholder to real remote" {
  bash "$RUN_INSTALL" memory
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" != *"$GITLORE_T_PLACEHOLDER_URL"* ]]
}

@test "install records gh repo create with --private (no --source flag)" {
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory
  grep -q 'repo create' "$log"
  grep -q -- '--private' "$log"
  # --source=. is intentionally omitted: gh's --source rejects gitfile-pointed
  # submodule worktrees, so we wire origin and push by hand instead.
  run grep -q -- '--source' "$log"
  [ "$status" -ne 0 ]
}

@test "install completes local-only when gh is unauthed (no abort)" {
  GH_MOCK_EXIT_AUTH_STATUS=1 run --separate-stderr bash "$RUN_INSTALL" memory
  [ "$status" -eq 0 ]
  [ -d memory ]
  [ -f .claude/settings.json ]
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [ "$url" = "$GITLORE_T_PLACEHOLDER_URL" ]
}

@test "install aborts cleanly when gh repo create fails (name collision)" {
  GH_MOCK_EXIT_REPO_CREATE=1 \
    GH_MOCK_STDERR_REPO_CREATE="GraphQL: Name already exists on this account" \
    run --separate-stderr bash "$RUN_INSTALL" memory
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"/gitlore:resolve"* ]]
}

@test "install is idempotent (no second gh repo create call on re-run)" {
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory
  count=$(grep -c 'repo create' "$log" || true)
  [ "$count" -eq 1 ]
}

@test "auto mode with no gh leaves a local-only install (placeholder URL kept)" {
  # Build a PATH without gh but with the tools run.sh needs.
  local no_gh_bin="$TMP_REPO/.no-gh-bin"
  mkdir -p "$no_gh_bin"
  for tool in bash sh git jq mktemp mv dirname basename find grep sed awk sort cat cp rm mkdir touch chmod tail stat; do
    bin=$(command -v "$tool") || { echo "no $tool on PATH to build the gh-less PATH from" >&2; return 1; }
    ln -sf "$bin" "$no_gh_bin/$tool"
  done
  PATH="$no_gh_bin" run --separate-stderr bash "$RUN_INSTALL" memory
  [ "$status" -eq 0 ]
  [ -d memory ]
  [ -f .claude/settings.json ]
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" == *"gitlore-placeholder"* ]]
  [[ "$stderr" == *"local-only"* ]]
}

@test "url mode repoints a synced placeholder origin instead of reading it as wired" {
  # The store's origin may already exist, holding the .gitmodules placeholder
  # (absolutized) from an earlier sync. The placeholder names no repository, so
  # the slot is still gitlore's to fill: `remote add` fails on an existing origin,
  # while `config` repoints it either way.
  bash "$RUN_INSTALL" memory local
  git -C memory config remote.origin.url "$TMP_REPO/.git/gitlore-placeholder"
  local remote="$TMP_REPO/.existing-remote.git"
  git init -q --bare "$remote"
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" memory url "$remote"
  [ "$status" -eq 0 ]
  [ "$(git -C memory config --get remote.origin.url)" = "$remote" ]
  git -C "$remote" show-ref --verify --quiet refs/heads/live
  [ "$(git config --file .gitmodules submodule.gitlore-memory.url)" = "$remote" ]
}

@test "url mode wires an existing remote and pushes live" {
  local remote="$TMP_REPO/.existing-remote.git"
  git init -q --bare "$remote"
  run bash "$RUN_INSTALL" memory url "$remote"
  [ "$status" -eq 0 ]
  url=$(git -C memory config --get remote.origin.url)
  [ "$url" = "$remote" ]
  # live was pushed to the existing remote.
  git -C "$remote" show-ref --verify --quiet refs/heads/live
  gm=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [ "$gm" = "$remote" ]
}

@test "local mode keeps placeholder and never calls gh" {
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory local
  url=$(git config --file .gitmodules submodule.gitlore-memory.url)
  [[ "$url" == *"gitlore-placeholder"* ]]
  [ ! -f "$log" ] || ! grep -q 'repo create' "$log"
}

@test "auto mode (gh available) names the remote <parent-base>-memory" {
  git remote add origin "https://github.com/acme/project.git"
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory
  grep -q 'repo create' "$log"
  grep -q 'project-memory' "$log"
}

@test "auto mode creates a public remote when the parent is public" {
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY="PUBLIC"
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory
  grep -q -- '--public' "$log"
}

# --- the url `.gitmodules` records ------------------------------------------
# A recursive clone has to work with no GitHub SSH key, so the tracked
# `.gitmodules` carries the https form while the submodule's own remote — the
# one pushes go through — keeps the ssh url it was given.

@test "auto mode records the https url in .gitmodules and keeps the ssh url on the remote" {
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_REMOTE_URL="git@github.com:alice/project-memory.git"
  fake_github_repo "$GH_MOCK_REMOTE_URL" memory
  run bash "$RUN_INSTALL" memory
  [ "$status" -eq 0 ]
  [ "$(git config --file .gitmodules submodule.gitlore-memory.url)" = "https://github.com/alice/project-memory.git" ]
  [ "$(git -C memory config --get remote.origin.url)" = "git@github.com:alice/project-memory.git" ]
  git -C "$TMP_REPO/.fake-github/memory.git" show-ref --verify --quiet refs/heads/live
}

@test "auto mode re-run with an https .gitmodules and an ssh remote wires nothing twice" {
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_REMOTE_URL="git@github.com:alice/project-memory.git"
  fake_github_repo "$GH_MOCK_REMOTE_URL" memory
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory
  GH_MOCK_LOG="$log" bash "$RUN_INSTALL" memory
  [ "$(grep -c 'repo create' "$log")" -eq 1 ]
  [ "$(git config --file .gitmodules submodule.gitlore-memory.url)" = "https://github.com/alice/project-memory.git" ]
  [ "$(git -C memory config --get remote.origin.url)" = "git@github.com:alice/project-memory.git" ]
}

@test "url mode rewrites an ssh GitHub url given by the person, keeping it on the remote" {
  fake_github_repo "git@github.com:acme/notes-memory.git" notes
  run bash "$RUN_INSTALL" memory url "git@github.com:acme/notes-memory.git"
  [ "$status" -eq 0 ]
  [ "$(git config --file .gitmodules submodule.gitlore-memory.url)" = "https://github.com/acme/notes-memory.git" ]
  [ "$(git -C memory config --get remote.origin.url)" = "git@github.com:acme/notes-memory.git" ]
  git -C "$TMP_REPO/.fake-github/notes.git" show-ref --verify --quiet refs/heads/live
}

@test "url mode rewrites an ssh:// GitHub url the same way" {
  fake_github_repo "ssh://git@github.com/acme/notes-memory" notes
  run bash "$RUN_INSTALL" memory url "ssh://git@github.com/acme/notes-memory"
  [ "$status" -eq 0 ]
  [ "$(git config --file .gitmodules submodule.gitlore-memory.url)" = "https://github.com/acme/notes-memory.git" ]
  [ "$(git -C memory config --get remote.origin.url)" = "ssh://git@github.com/acme/notes-memory" ]
}

@test "url mode leaves an https url as given" {
  fake_github_repo "https://github.com/acme/notes-memory.git" notes
  run bash "$RUN_INSTALL" memory url "https://github.com/acme/notes-memory.git"
  [ "$status" -eq 0 ]
  [ "$(git config --file .gitmodules submodule.gitlore-memory.url)" = "https://github.com/acme/notes-memory.git" ]
  [ "$(git -C memory config --get remote.origin.url)" = "https://github.com/acme/notes-memory.git" ]
}

@test "url mode leaves a non-GitHub ssh url as given" {
  fake_github_repo "git@git.example.org:acme/notes-memory.git" notes
  run bash "$RUN_INSTALL" memory url "git@git.example.org:acme/notes-memory.git"
  [ "$status" -eq 0 ]
  [ "$(git config --file .gitmodules submodule.gitlore-memory.url)" = "git@git.example.org:acme/notes-memory.git" ]
}

# --- a private repository under a public parent -----------------------------
# An anonymous `clone --recurse-submodules` aborts at a private repository
# whatever the url form, so a confirmed-public parent with a confirmed-private
# memory remote gets one stderr line. Unknown visibility stays silent.

@test "url mode warns once when a public parent gets a private memory remote" {
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY_MAP=$'acme/project=PUBLIC\nacme/project-memory=PRIVATE'
  fake_github_repo "git@github.com:acme/project-memory.git" memory
  run --separate-stderr bash "$RUN_INSTALL" memory url "git@github.com:acme/project-memory.git"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$stderr" | grep -c 'is private but this repository is public')" -eq 1 ]
  [[ "$stderr" == *"git@github.com:acme/project-memory.git"* ]]
}

@test "url mode does not warn when the memory remote is public too" {
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY_MAP=$'acme/project=PUBLIC\nacme/project-memory=PUBLIC'
  fake_github_repo "git@github.com:acme/project-memory.git" memory
  run --separate-stderr bash "$RUN_INSTALL" memory url "git@github.com:acme/project-memory.git"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"is private but this repository is public"* ]]
}

@test "url mode does not warn when the parent is private" {
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY_MAP=$'acme/project=PRIVATE\nacme/project-memory=PRIVATE'
  fake_github_repo "git@github.com:acme/project-memory.git" memory
  run --separate-stderr bash "$RUN_INSTALL" memory url "git@github.com:acme/project-memory.git"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"is private but this repository is public"* ]]
}

@test "url mode stays silent when the memory remote's visibility cannot be read" {
  git remote add origin "https://github.com/acme/project.git"
  export GH_MOCK_VISIBILITY_MAP='acme/project=PUBLIC'
  fake_github_repo "git@github.com:acme/project-memory.git" memory
  run --separate-stderr bash "$RUN_INSTALL" memory url "git@github.com:acme/project-memory.git"
  [ "$status" -eq 0 ]
  [[ "$stderr" != *"is private but this repository is public"* ]]
}
