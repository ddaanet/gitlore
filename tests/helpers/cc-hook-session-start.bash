#!/usr/bin/env bash
# Shared setup for the SessionStart hook suites: the hook path both drive,
# and the tmp-repo/worktree lifecycle both need for teardown.

# shellcheck disable=SC2034   # used by callers' @test bodies
SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}
