#!/usr/bin/env bats
# D70 Q4: the store gate retired. SessionStart removes the `pre-commit` the gate
# left in memory/ and in each mounted tier when it is byte-identical to the
# wrapper `gitlore_emit_hook_wrapper <path> memory-pre-commit` writes, and unsets
# the `gitlore.hooksDir` mirrored beside it. Any other pre-commit is the user's
# and stays, byte for byte. A fresh install plants none.
#
# $output is bats' capture; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/cc-hook-session-start

# Write the retired gate's wrapper to $1, byte for byte as the emitter did.
write_retired_wrapper() {
  PLUGIN_ROOT="$PLUGIN_ROOT" bash -c '
    source "$PLUGIN_ROOT/scripts/lib/util.sh"
    gitlore_emit_hook_wrapper "$1" memory-pre-commit' _ "$1"
}

# Print the hooks dir of the store at $1.
store_hooks_dir() { git -C "$1" rev-parse --git-path hooks; }

# Leave the store at $1 as the retired gate left it: the wrapper in its hooks
# dir (or $2 as the hook's text when given) and gitlore.hooksDir mirrored.
leave_gate() {
  local dir hooks
  dir="$1"
  hooks=$(store_hooks_dir "$dir")
  mkdir -p "$hooks"
  if [ -n "${2:-}" ]; then
    printf '%s' "$2" > "$hooks/pre-commit"
    chmod +x "$hooks/pre-commit"
  else
    write_retired_wrapper "$hooks/pre-commit"
  fi
  git -C "$dir" config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

hook_of() { printf '%s/pre-commit\n' "$(store_hooks_dir "$1")"; }
hooksdir_of() { git -C "$1" config --local --get gitlore.hooksDir || true; }

start_session() {
  enable_gitlore
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
}

@test "SessionStart removes the retired gate wrapper from memory and a tier and unsets both hooksDir mirrors" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  leave_gate memory
  leave_gate memory/ddaanet
  [ -x "$(hook_of memory)" ]
  [ -x "$(hook_of memory/ddaanet)" ]

  start_session

  [ ! -e "$(hook_of memory)" ]
  [ ! -e "$(hook_of memory/ddaanet)" ]
  [ -z "$(hooksdir_of memory)" ]
  [ -z "$(hooksdir_of memory/ddaanet)" ]
}

@test "SessionStart leaves a foreign pre-commit in memory and a tier byte for byte" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  # One byte off the wrapper: a trailing space on the last line.
  foreign=$(write_retired_wrapper "$BATS_TEST_TMPDIR/w" && cat "$BATS_TEST_TMPDIR/w"; printf x)
  foreign="${foreign%x} "
  leave_gate memory "$foreign"
  leave_gate memory/ddaanet "#!/bin/sh
echo my own check
"
  cp "$(hook_of memory)" "$BATS_TEST_TMPDIR/mem.before"
  cp "$(hook_of memory/ddaanet)" "$BATS_TEST_TMPDIR/tier.before"

  start_session

  cmp "$(hook_of memory)" "$BATS_TEST_TMPDIR/mem.before"
  cmp "$(hook_of memory/ddaanet)" "$BATS_TEST_TMPDIR/tier.before"
  [ -x "$(hook_of memory)" ]
  [ -x "$(hook_of memory/ddaanet)" ]
}

@test "SessionStart on a fresh install plants no pre-commit in memory or a tier and mirrors no hooksDir" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  [ ! -e "$(hook_of memory)" ]
  [ ! -e "$(hook_of memory/ddaanet)" ]

  start_session
  # A second start is the same.
  start_session

  [ ! -e "$(hook_of memory)" ]
  [ ! -e "$(hook_of memory/ddaanet)" ]
  [ -z "$(hooksdir_of memory)" ]
  [ -z "$(hooksdir_of memory/ddaanet)" ]
}
