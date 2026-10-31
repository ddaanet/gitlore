#!/usr/bin/env bash
# Shared setup for the add-tier suites: the script path, the tmp-repo
# lifecycle (with the local-submodule allowance both need), and the intent
# file writer both drive the script through.

# shellcheck disable=SC2034   # used by callers' @test bodies
ADD_TIER="$PLUGIN_ROOT/scripts/add-tier.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  # Submodule adds from a local path need this; scoped to the test process
  # rather than written into anyone's global config.
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always
}
teardown() { teardown_tmp_repo; }

# Write the add-tier intent to a file outside the repo; the suites hand it to
# the script on stdin (`run bash "$ADD_TIER" < "$INTENT"`), as the agent's
# quoted heredoc does.
write_intent() {
  INTENT="$BATS_TEST_TMPDIR/intent"
  printf '%s\n' "$@" > "$INTENT"
}
