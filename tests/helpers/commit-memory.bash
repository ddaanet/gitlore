#!/usr/bin/env bash
# Shared setup and driver for the commit-memory.sh suites (commit_memory.bats
# and its siblings). Source from each .bats file with: `load helpers/commit-memory`.
set -euo pipefail

# shellcheck disable=SC2034   # used by callers' @test bodies
CMD="$PLUGIN_ROOT/scripts/commit-memory.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

# The driver the approval cases share: gitlore_sync_memory_to_live called
# the way the pre-commit hook calls it, on the summary file as it stands.
# $1 = optional shell text run after the libraries are sourced, to stand a
# function in for a state no fixture reaches.
write_sync_driver() {
  driver="$BATS_TEST_TMPDIR/driver.sh"
  cat > "$driver" <<DRIVER
#!/usr/bin/env bash
set -euo pipefail
source "$PLUGIN_ROOT/scripts/lib/util.sh"
source "$PLUGIN_ROOT/scripts/lib/log.sh"
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"
${1:-}
gitlore_sync_memory_to_live memory
DRIVER
}
