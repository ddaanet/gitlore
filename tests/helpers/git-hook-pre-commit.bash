#!/usr/bin/env bash
# Shared setup for the pre-commit hook suites: the hook path and the tmp-repo
# lifecycle both suites drive it through.

# shellcheck disable=SC2034   # used by callers' @test bodies
HOOK="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }
