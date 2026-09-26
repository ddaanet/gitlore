#!/usr/bin/env bash
# Shared setup and driver for the memory-commit-batch.sh suites
# (cc_hook_memory_commit_batch.bats and cc_hook_memory_commit_batch_merge.bats).
# Source from each .bats file with: `load helpers/cc-hook-memory-commit-batch`.
set -euo pipefail

# shellcheck disable=SC2034   # used by callers' @test bodies
BATCH="$PLUGIN_ROOT/scripts/cc-hooks/memory-commit-batch.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

# The trigger file is the signal, so the payload carries nothing this hook acts
# on except `cwd` — read only to spot a trigger written against another root.
# Args: $1 = session cwd to report (default: none).
run_batch() {
  jq -nc --arg cwd "${1:-}" \
    '{hook_event_name:"PostToolBatch", tool_calls:[]} + (if $cwd == "" then {} else {cwd:$cwd} end)' \
    | bash "$BATCH"
}

# The model channel, which is what the agent actually reads.
ctx() { jq -r '.hookSpecificOutput.additionalContext // ""'; }
