#!/usr/bin/env bats

load helpers/setup

EMIT="$PLUGIN_ROOT/scripts/install/emit-launcher.sh"
setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() { teardown_tmp_repo; }

@test "fresh repo: writes executable shim and .envrc PATH_add" {
  bash "$EMIT"
  [ -x .gitlore/bin/claude ]
  diff .gitlore/bin/claude "$PLUGIN_ROOT/scripts/install/launcher-shim"
  grep -qxF 'PATH_add .gitlore/bin' .envrc
}

@test "existing .envrc: inserts after the last pre-existing PATH_add" {
  printf 'PATH_add node_modules/.bin\nlayout python\n' > .envrc
  bash "$EMIT"
  # Our line is immediately after node_modules/.bin (so it wins the front slot).
  [ "$(grep -nxF 'PATH_add .gitlore/bin' .envrc | cut -d: -f1)" = "2" ]
  grep -qxF 'layout python' .envrc
}

@test "idempotent: re-run leaves a single PATH_add .gitlore/bin" {
  bash "$EMIT"; bash "$EMIT"
  [ "$(grep -cxF 'PATH_add .gitlore/bin' .envrc)" -eq 1 ]
}
