#!/usr/bin/env bats
# Guards version-sync between this repo's .claude-plugin/plugin.json and the
# gitlore entry in the sibling marketplace repo's .claude-plugin/marketplace.json
# (see ../claude-plugins). The two `version` fields are independent strings; a
# `/plugin marketplace update` shows the marketplace value, so drift misreports
# the installed version. This check fails the build when they diverge.
#
# Tests are fixture-driven (temp JSON) so they're deterministic regardless of
# whether the sibling marketplace repo is checked out on this machine.

load helpers/setup

SCRIPT() { run "$PLUGIN_ROOT/scripts/check-version.sh" "$@"; }

setup() {
  setup_tmp_repo
  PLUGIN_JSON="$TMP_REPO/plugin.json"
  MARKET_JSON="$TMP_REPO/marketplace.json"
}

teardown() { teardown_tmp_repo; }

write_plugin() { printf '{"name":"gitlore","version":"%s"}\n' "$1" >"$PLUGIN_JSON"; }
write_market() {
  printf '{"plugins":[{"name":"other","version":"9.9.9"},{"name":"gitlore","version":"%s"}]}\n' \
    "$1" >"$MARKET_JSON"
}

@test "check-version: matching versions exit 0" {
  write_plugin "0.1.1"
  write_market "0.1.1"
  SCRIPT "$PLUGIN_JSON" "$MARKET_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"0.1.1"* ]]
}

@test "check-version: drift exits non-zero and names both versions" {
  write_plugin "0.2.0"
  write_market "0.1.1"
  SCRIPT "$PLUGIN_JSON" "$MARKET_JSON"
  [ "$status" -ne 0 ]
  [[ "$output" == *"0.2.0"* ]]
  [[ "$output" == *"0.1.1"* ]]
}

@test "check-version: missing marketplace.json skips with exit 0" {
  write_plugin "0.1.1"
  SCRIPT "$PLUGIN_JSON" "$TMP_REPO/does-not-exist.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skip"* ]]
}

@test "check-version: gitlore absent from marketplace exits non-zero" {
  write_plugin "0.1.1"
  printf '{"plugins":[{"name":"other","version":"9.9.9"}]}\n' >"$MARKET_JSON"
  SCRIPT "$PLUGIN_JSON" "$MARKET_JSON"
  [ "$status" -ne 0 ]
}
