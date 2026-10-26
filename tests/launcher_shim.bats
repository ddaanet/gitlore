#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

SHIM_SRC="$PLUGIN_ROOT/scripts/install/launcher-shim"

setup() {
  setup_tmp_repo
  # Clean baseline: the suite may be run from inside a gitlore-launched session
  # (GITLORE_LAUNCHED=1 in the ambient env), which would make the inject tests
  # see the anti-double-inject sentinel and pass through. The one test that
  # needs the sentinel sets it inline.
  unset GITLORE_LAUNCHED
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

# The shim strips its own directory from PATH to find the real claude, and a
# strip that misses re-execs the shim forever. A `//` is how that arrives in
# practice: macOS `$TMPDIR` ends in `/`, so every path built from it carries
# one. The call is bounded because the regression is a hang — an unbounded
# `run` would take the suite down with it instead of failing here.
bounded() {
  local secs="$1" pid dog st
  shift
  "$@" &
  pid=$!
  # The kill is expected to find nothing on the happy path; that is the point.
  ( sleep "$secs"; kill -9 "$pid" 2>/dev/null ) &
  dog=$!
  wait "$pid"; st=$?
  kill "$dog" 2>/dev/null
  return "$st"
}

@test "finds the real claude however PATH spells the shim's own directory" {
  local spelling
  for spelling in "$SHIMDIR/" "${SHIMDIR%/*}//${SHIMDIR##*/}"; do
    PATH="$spelling:$STUBDIR:$PATH" run bounded 10 "$SHIMDIR/claude" hello
    [ "$status" -eq 0 ]
    [ "$output" = "REAL:hello" ]
  done
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

@test "exit 127 when no real claude is reachable" {
  # PATH = shim dir + a minimal toolbox (the utilities the shim needs) but no claude.
  tools="$TMP_REPO/.tools"; mkdir -p "$tools"
  for t in sh git jq dirname env; do ln -s "$(command -v "$t")" "$tools/$t"; done
  run -127 env -i HOME="$HOME" PATH="$SHIMDIR:$tools" "$SHIMDIR/claude"
  [ "$status" -eq 127 ]
}

# --- Memory-path containment -------------------------------------------------
# `.gitmodules` and `.claude/settings.json` are the checkout's to write, so the
# path the shim promotes to `autoMemoryDirectory` must stay inside the repo.
# Every case runs both placements as production reaches them, by the bare name
# `claude` on PATH: the per-repo copy emit-launcher.sh writes to
# `.gitlore/bin/claude` (direnv puts that directory first), and the copy
# global-shim.sh writes to `$GITLORE_HOME/bin/claude`. The repo root carries a
# space.

# contain_repo <mempath>: an enabled gitlore repo whose `.gitmodules` names
# <mempath>; no submodule is checked out. Sets CROOT and leaves the cwd there.
contain_repo() {
  CROOT="$TMP_REPO/repo with space"
  mkdir -p "$CROOT/.claude"
  cd "$CROOT" || return 1
  git init -q -b main
  git config --file .gitmodules submodule.gitlore-memory.path "$1"
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
}

# run_both_placements <args>…: install both placements from the cwd, then run
# `claude <args>` through each, leaving OUT_/ERR_/ST_<placement> behind. The
# asserts read them through `eval`, which shellcheck cannot follow.
# shellcheck disable=SC2034
run_both_placements() {
  local base="${PATH#"$SHIMDIR:$STUBDIR:"}"
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/install/emit-launcher.sh"
  # The PATH instruction global-shim.sh prints is for a human and asserted in
  # tests/global_shim.bats.
  CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" GITLORE_HOME="$TMP_REPO/.gitlore-home" SHELL=/bin/sh \
    bash "$PLUGIN_ROOT/scripts/install/global-shim.sh" 2>/dev/null
  ST_repo=0 ST_global=0
  OUT_repo=$(PATH="$CROOT/.gitlore/bin:$STUBDIR:$base" claude "$@" 2>"$TMP_REPO/.err") \
    || ST_repo=$?
  ERR_repo=$(cat "$TMP_REPO/.err")
  OUT_global=$(PATH="$TMP_REPO/.gitlore-home/bin:$STUBDIR:$base" claude "$@" 2>"$TMP_REPO/.err") \
    || ST_global=$?
  ERR_global=$(cat "$TMP_REPO/.err")
}

# A refusal launches the real claude with the original args and no --settings,
# and says why on one stderr line.
assert_refused() {
  local p out err st
  for p in repo global; do
    eval "out=\$OUT_$p err=\$ERR_$p st=\$ST_$p"
    [ "$st" -eq 0 ] || { echo "$p: status $st"; return 1; }
    [ "$out" = "REAL:hi" ] || { echo "$p: forwarded [$out]"; return 1; }
    [[ "$err" == "gitlore: "*"memory redirect"* ]] || { echo "$p: stderr [$err]"; return 1; }
    [[ "$err" != *$'\n'* ]] || { echo "$p: stderr is not one line [$err]"; return 1; }
  done
}

# assert_injected <mempath>: both placements forwarded exactly the redirect to
# "$CROOT/<mempath>" ahead of the original args, and said nothing.
assert_injected() {
  local p out err want
  want=$(jq -nc --arg p "$CROOT/$1" '{autoMemoryDirectory:$p}')
  for p in repo global; do
    eval "out=\$OUT_$p err=\$ERR_$p"
    [ "$out" = "REAL:--settings $want hi" ] || { echo "$p: forwarded [$out]"; return 1; }
    [ -z "$err" ] || { echo "$p: stderr [$err]"; return 1; }
  done
}

@test "refuses a memory path that climbs out with a leading .." {
  contain_repo ../x
  run_both_placements hi
  assert_refused
}

@test "refuses a memory path whose .. components climb past the root" {
  contain_repo a/../..
  run_both_placements hi
  assert_refused
}

@test "refuses an absolute memory path" {
  contain_repo /etc/gitlore-memory
  run_both_placements hi
  assert_refused
}

@test "refuses a memory directory that is a symlink out of the repo" {
  contain_repo memory
  mkdir "$TMP_REPO/outside"
  ln -s "$TMP_REPO/outside" "$CROOT/memory"
  run_both_placements hi
  assert_refused
}

# Before the submodule is initialised the directory does not exist, so the
# check falls to its nearest existing ancestor: a symlinked parent would have
# Claude Code create the memory directory outside the repo.
@test "refuses a missing memory directory below a parent symlinked out of the repo" {
  contain_repo a/memory
  mkdir "$TMP_REPO/outside"
  ln -s "$TMP_REPO/outside" "$CROOT/a"
  run_both_placements hi
  assert_refused
}

@test "refuses a memory path that is a dangling symlink" {
  contain_repo memory
  ln -s "$TMP_REPO/not-yet" "$CROOT/memory"
  run_both_placements hi
  assert_refused
}

@test "accepts a memory directory whose name contains two dots" {
  contain_repo my..memory
  mkdir "$CROOT/my..memory"
  run_both_placements hi
  assert_injected my..memory
}

@test "still injects before the memory submodule is initialised" {
  contain_repo memory
  run_both_placements hi
  assert_injected memory
}

@test "outside any repo both placements pass through silently" {
  CROOT="$TMP_REPO/norepo"; mkdir -p "$CROOT"; cd "$CROOT" || return 1
  export GIT_CEILING_DIRECTORIES="$TMP_REPO"
  run_both_placements hi
  [ "$OUT_repo" = "REAL:hi" ] && [ -z "$ERR_repo" ]
  [ "$OUT_global" = "REAL:hi" ] && [ -z "$ERR_global" ]
}
