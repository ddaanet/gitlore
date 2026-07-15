#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

SHIM_SRC="$PLUGIN_ROOT/scripts/install/launcher-shim"

setup() {
  setup_tmp_repo
  # Clean baseline: the suite may be run from inside a gitlore-launched session
  # (GITLORE_LAUNCHED=1 in the ambient env), which would make the inject test
  # see the anti-double-inject sentinel and pass through. The one test that
  # needs the sentinel sets it inline.
  unset GITLORE_LAUNCHED
  unset GITLORE_AUTO_CLAUDE_PLUGIN_DIR
  SHIMDIR="$TMP_REPO/.shimdir"; STUBDIR="$TMP_REPO/.stubdir"
  mkdir -p "$SHIMDIR" "$STUBDIR"
  cp "$SHIM_SRC" "$SHIMDIR/claude"; chmod 755 "$SHIMDIR/claude"
  # Recording stub: prints its args so we can assert what the shim forwarded.
  printf '#!/bin/sh\necho "REAL:$*"\n' > "$STUBDIR/claude"; chmod 755 "$STUBDIR/claude"
  export PATH="$SHIMDIR:$STUBDIR:$PATH"
}
teardown() { teardown_tmp_repo; }

@test "passthrough when not in a gitlore repo" {
  run "$SHIMDIR/claude" hello
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:hello" ]
}

@test "passthrough when GITLORE_LAUNCHED already set (anti-double-inject)" {
  make_parent_with_memory
  mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run "$SHIMDIR/claude" hi
  [ "$output" = "REAL:hi" ]
}

@test "passthrough when submodule present but gitlore disabled" {
  make_parent_with_memory
  mkdir -p .claude; printf '{"gitlore":{"enabled":false}}\n' > .claude/settings.json
  run "$SHIMDIR/claude" hi
  [ "$output" = "REAL:hi" ]
}

@test "injects --settings autoMemoryDirectory in an enabled gitlore repo" {
  make_parent_with_memory
  mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [[ "$output" == *"--settings"* ]]
  [[ "$output" == *"autoMemoryDirectory"* ]]
  [[ "$output" == *"$TMP_REPO/memory"* ]]
  [[ "$output" == *"hi"* ]]
}

@test "no --plugin-dir by default, even in a plugin checkout" {
  mkdir -p .claude-plugin; printf '{"name":"x"}\n' > .claude-plugin/plugin.json
  run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:hi" ]
}

@test "no --plugin-dir when opted in but no plugin.json" {
  GITLORE_AUTO_CLAUDE_PLUGIN_DIR=1 run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:hi" ]
}

@test "injects --plugin-dir . when opted in inside a plugin checkout" {
  mkdir -p .claude-plugin; printf '{"name":"x"}\n' > .claude-plugin/plugin.json
  GITLORE_AUTO_CLAUDE_PLUGIN_DIR=1 run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:--plugin-dir . hi" ]
}

@test "--plugin-dir composes with the autoMemoryDirectory injection" {
  make_parent_with_memory
  mkdir -p .claude; printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  mkdir -p .claude-plugin; printf '{"name":"x"}\n' > .claude-plugin/plugin.json
  GITLORE_AUTO_CLAUDE_PLUGIN_DIR=1 run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [[ "$output" == *"--settings"* ]]
  [[ "$output" == *"autoMemoryDirectory"* ]]
  [[ "$output" == *"--plugin-dir . hi"* ]]
}

@test "GITLORE_LAUNCHED suppresses --plugin-dir (anti-double-inject)" {
  mkdir -p .claude-plugin; printf '{"name":"x"}\n' > .claude-plugin/plugin.json
  GITLORE_LAUNCHED=1 GITLORE_AUTO_CLAUDE_PLUGIN_DIR=1 run "$SHIMDIR/claude" hi
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:hi" ]
}

@test "PATH stripping survives BSD paste (no implicit stdin)" {
  # macOS/BSD paste errors out when given no file operand; GNU defaults to
  # stdin. Shadow paste with a BSD-strict wrapper to catch the GNU-ism.
  real_paste=$(command -v paste)
  bsd="$TMP_REPO/.bsdtools"; mkdir -p "$bsd"
  cat > "$bsd/paste" <<EOF
#!/bin/sh
ok=0
for a in "\$@"; do case "\$a" in -) ok=1 ;; -*) ;; *) ok=1 ;; esac; done
[ "\$ok" -eq 1 ] || { echo 'usage: paste [-s] [-d delimiters] file ...' >&2; exit 1; }
exec "$real_paste" "\$@"
EOF
  chmod 755 "$bsd/paste"
  PATH="$bsd:$PATH" run "$SHIMDIR/claude" hello
  [ "$status" -eq 0 ]
  [ "$output" = "REAL:hello" ]
}

@test "exit 127 when no real claude is reachable" {
  # PATH = shim dir + a minimal toolbox (the utilities the shim needs) but no claude.
  tools="$TMP_REPO/.tools"; mkdir -p "$tools"
  for t in sh tr grep paste git jq dirname env; do ln -s "$(command -v "$t")" "$tools/$t"; done
  run -127 env -i HOME="$HOME" PATH="$SHIMDIR:$tools" "$SHIMDIR/claude"
  [ "$status" -eq 127 ]
}
