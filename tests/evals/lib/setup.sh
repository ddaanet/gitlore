#!/usr/bin/env bash
# Eval repo lifecycle helpers.
# Source this file, then call setup_eval_repo <initial_memory> and teardown_eval_repo.
set -euo pipefail

EVAL_LIB_DIR="${EVAL_LIB_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
PLUGIN_ROOT="${PLUGIN_ROOT:-$(cd "$EVAL_LIB_DIR/../../.." && pwd)}"

# shellcheck disable=SC1091
source "$EVAL_LIB_DIR/../../helpers/gh-mock.bash"

setup_eval_repo() {
  local initial_memory="$1"

  EVAL_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-eval.XXXXXX")"
  export EVAL_REPO
  # gh-mock.bash uses TMP_REPO as the bindir location
  TMP_REPO="$EVAL_REPO"
  export TMP_REPO

  cd "$EVAL_REPO"
  git init -q -b main
  git config user.email "eval@test.com"
  git config user.name "Eval Test"

  # Fake gh binary (writes to $TMP_REPO/.gh-mock-bin/)
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$EVAL_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"

  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export CLAUDECODE=1
  # Suppress launcher warning: eval bypasses the shim intentionally
  export GITLORE_LAUNCHED=1

  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory "true"
  # Install detects no hook manager; wire directly so the pre-commit hook fires
  # during the eval's parent git commit.
  bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"
  git add .claude/gitlore-hook-setup
  git commit -q -m "Install gitlore"

  printf '%s\n' "$initial_memory" > memory/MEMORY.md
  git -C memory add MEMORY.md
  git -C memory commit -q -m "initial memory"
}

teardown_eval_repo() {
  if [ -n "${EVAL_REPO:-}" ] && [ -d "$EVAL_REPO" ]; then
    rm -rf "$EVAL_REPO"
  fi
}
