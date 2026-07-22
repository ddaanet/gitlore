#!/usr/bin/env bash
# Eval repo lifecycle helpers.
# Source this file, then call setup_eval_repo <initial_memory> and teardown_eval_repo.
set -euo pipefail

unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) captures below
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
  # No eval may reach the network, so every remote in a fixture is a local bare
  # repo — and `protocol.file.allow` defaults to `user`, which blocks exactly the
  # clone `git submodule add` performs when mounting a tier. Repo config does not
  # reach it: the transport policy is read by the CLONE, a fresh process with a
  # fresh repo. GIT_CONFIG_* does reach it, and survives the hooks' local-env-var
  # unset (that list has no GIT_CONFIG_*). Exported here rather than per fixture
  # so it also reaches the `claude` subprocess, whose hooks run the real mount.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always
  # Suppress launcher warning: eval bypasses the shim intentionally
  export GITLORE_LAUNCHED=1

  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory "true"
  # Install detects no hook manager; wire directly so the pre-commit hook fires
  # during the eval's parent git commit.
  bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"

  # Wire the CC hooks into settings.json, copied wholesale from the plugin's own
  # hooks/hooks.json with ${CLAUDE_PLUGIN_ROOT} resolved. This bypasses the plugin
  # marketplace (which requires a cached install) and works in both interactive and
  # eval runs; the eval runner passes `--setting-sources project`, so claude loads
  # hooks from <cwd>/.claude/settings.json.
  #
  # Derived, never hand-listed: a hand-written subset is a registration the evals
  # never exercise, and the whole point of an eval is that it walks the wiring
  # production ships ([[feedback_test_the_invocation_path]]). The subset here was
  # PostToolUse alone, which would have left every PostToolBatch hook — composition,
  # the commit gate, recall, add-tier — dark.
  local tmp
  tmp=$(mktemp)
  jq --arg plugin_root "$PLUGIN_ROOT" --slurpfile hooks "$PLUGIN_ROOT/hooks/hooks.json" '
    .hooks = ($hooks[0].hooks
              | walk(if type == "string"
                     then gsub("\\$\\{CLAUDE_PLUGIN_ROOT\\}"; $plugin_root)
                     else . end))
  ' .claude/settings.json > "$tmp" && mv "$tmp" .claude/settings.json

  # Skills and commands are plugin-scoped, and the eval repo has no plugin
  # installed — copy them in so their prompt contracts are what the agent reads.
  # Without this, /add-tier is an unknown command and the recall skill never
  # activates, and the scenario silently grades a different flow.
  mkdir -p .claude/skills .claude/commands
  cp -R "$PLUGIN_ROOT/skills/." .claude/skills/
  cp "$PLUGIN_ROOT"/commands/*.md .claude/commands/

  git add .claude/settings.json .claude/gitlore-hook-setup .claude/skills .claude/commands
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
