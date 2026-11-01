#!/usr/bin/env bats
# tests/evals/setups/*.sh — the scenario fixtures the eval tier runs after its
# base fixture. The eval runner reaches them only through the claude CLI, so
# nothing else exercises them; each is run here the way run-evals.sh runs it
# (`cd` into the repo, `bash <script>`, no arguments).
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

setup() {
  setup_tmp_repo
  isolate_home
  # A tier remote is a local bare repo, and the mount's clone refuses file
  # transport unless the environment allows it (the eval base fixture exports
  # the same three).
  export GIT_CONFIG_COUNT=1
  export GIT_CONFIG_KEY_0=protocol.file.allow
  export GIT_CONFIG_VALUE_0=always
}
teardown() { teardown_tmp_repo; }

@test "mounted-tier setup leaves a clean store with the acme tier mounted and listed active" {
  make_parent_with_memory
  setup_script="$PLUGIN_ROOT/tests/evals/setups/mounted-tier.sh"
  [ -x "$setup_script" ]

  run bash -c 'cd "$1" && bash "$2"' _ "$TMP_REPO" "$setup_script"
  [ "$status" -eq 0 ]

  # Mounted: a real submodule checkout at its path, registered in memory's own
  # .gitmodules, and recorded as a gitlink at the tier's current commit.
  [ -s memory/acme/.git ]
  [ "$(git config --file memory/.gitmodules --get submodule.acme.path)" = "acme" ]
  tier_head=$(git -C memory/acme rev-parse HEAD)
  [ "$(git -C memory rev-parse HEAD:acme)" = "$tier_head" ]
  [ "$tier_head" = "$(git -C memory/acme rev-parse live)" ]

  # Active: listed in the manifest, as gitlore defines it (gitlore_active_tiers).
  [ "$(gitlore_tier_paths memory)" = "acme" ]
  [ "$(gitlore_active_tiers memory)" = "acme" ]

  # Clean: neither the store nor the tier has anything uncommitted.
  [ -z "$(git -C memory status --porcelain)" ]
  [ -z "$(git -C memory/acme status --porcelain)" ]
}
