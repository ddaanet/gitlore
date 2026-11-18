#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/index-compose

# gitlore_compose_up checks the root-bullets producer's status before the
# writer sees anything, as gitlore_compose_pass does: a producer that fails
# printing nothing must not rewrite the root index with no bullets.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "compose_up leaves root untouched when the bullets producer fails" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet existing.md "already here"
  gitlore_compose memory
  grep -qF 'ddaanet/existing.md' memory/MEMORY.md
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"

  # The producer fails before printing a byte.
  gitlore_compose_root_bullets() { return 1; }

  run gitlore_compose_up memory ddaanet :
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not compose memory/MEMORY.md; it was left untouched"* ]]
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
}
