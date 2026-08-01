#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup

GLOBAL="$PLUGIN_ROOT/scripts/install/global-shim.sh"
setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export GITLORE_HOME="$TMP_REPO/.gitlore-home"
}
teardown() { teardown_tmp_repo; }

@test "refuses without CLAUDE_PLUGIN_ROOT" {
  # This message is what tests/resolve.bats refutes, to say resolve.sh derives
  # its own root instead of bailing this way. Asserted here so that refutation
  # keeps watching a string production still emits.
  run --separate-stderr env -u CLAUDE_PLUGIN_ROOT bash "$GLOBAL"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"$GITLORE_T_PLUGIN_ROOT_UNSET"* ]]
}

@test "writes an executable global shim matching the source" {
  SHELL=/bin/bash bash "$GLOBAL"
  [ -x "$GITLORE_HOME/bin/claude" ]
  diff "$GITLORE_HOME/bin/claude" "$PLUGIN_ROOT/scripts/install/launcher-shim"
}

@test "prints a bash/zsh export PATH instruction (not auto-edited)" {
  run --separate-stderr env SHELL=/bin/zsh bash "$GLOBAL"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"export PATH=\"$GITLORE_HOME/bin:\$PATH\""* ]]
}

@test "prints a fish set -gx PATH instruction" {
  run --separate-stderr env SHELL=/usr/bin/fish bash "$GLOBAL"
  [[ "$stderr" == *"set -gx PATH $GITLORE_HOME/bin \$PATH"* ]]
}

@test "idempotent: re-run leaves a single executable shim" {
  SHELL=/bin/bash bash "$GLOBAL"; SHELL=/bin/bash bash "$GLOBAL"
  [ -x "$GITLORE_HOME/bin/claude" ]
}
