#!/usr/bin/env bats
# scripts/cross-rewrite.sh (D62): the refusals of a ref on a dropped commit and
# the commands every refusal prints. A dropped main against a stale
# refs/remotes/origin/main, a HEAD attached to a branch above a dropped base, and
# a store given as a relative path whose printed commands run from anywhere.
# Fixtures: helpers/rewrite-fixtures.bash and helpers/cross-fixtures.bash.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2153,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/rewrite-fixtures
load helpers/cross-fixtures

CROSS="$PLUGIN_ROOT/scripts/cross-rewrite.sh"
TIER=memory/ddaanet

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  BARE_TIER="$TMP_REPO/.bare-ddaanet.git"
}
teardown() { teardown_tmp_repo; }

# The refusal case: exit 1 and prefixed.
refused() {
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cross-rewrite:"* ]]
}

# A tier whose second rewrite dropped N2 (O2 -> N2 -> zeros), with the remote's
# live on N1 and its main deleted. The clone still tracks the main the mount
# fetched before the rewrite: refs/remotes/origin/main is stale, not absent.
tier_dropped_remote_without_main() {
  cx_tier_setup single
  cx_record_commit "$BARE_TIER" "$(cx_record_map "$BARE_TIER")
$RW_N2 $CX_ZEROS" append
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$RW_N1"
  git --git-dir="$BARE_TIER" update-ref -d refs/heads/main
  # Premises: the remote has no main, the clone still resolves one.
  run git --git-dir="$BARE_TIER" rev-parse -q --verify refs/heads/main
  [ "$status" -ne 0 ]
  git -C "$TIER" rev-parse -q --verify refs/remotes/origin/main > /dev/null
}

# --- a stale origin/main ---

@test "cross tier: a dropped main whose remote main is gone is refused with the delete, not a move to the stale tracking ref" {
  tier_dropped_remote_without_main
  cx_position "$TIER" "$RW_O1" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"has no main"* ]]
  [[ "$stderr" != *"update-ref refs/heads/main refs/remotes/origin/main"* ]]
  delete=$(printf '%s\n' "$stderr" | grep '^  git .*update-ref -d refs/heads/main')
  [ -n "$delete" ]
  run bash -c "cd / && $delete"
  [ "$status" -eq 0 ]
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_N1" ]
}

@test "cross tier: a dropped main with local work whose remote main is gone is refused with the listing only" {
  tier_dropped_remote_without_main
  rewrite_position_clone "$TIER" old
  cx_position "$TIER" "$RW_O1" "$RW_O1" "$RW_LOCAL"
  before=$(rewrite_store_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"has no main to replay them onto"* ]]
  [[ "$stderr" == *"A person must decide"* ]]
  [[ "$stderr" == *"git -C \"$TMP_REPO/$TIER\" log --oneline $RW_O2..$RW_LOCAL"* ]]
  [[ "$stderr" != *"refs/remotes/origin/main"* ]]
  [[ "$stderr" != *"cherry-pick"* ]]
  [[ "$stderr" != *"update-ref"* ]]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
}

# --- HEAD attached to a branch above a dropped base ---

@test "cross tier: HEAD attached to main above a dropped base replays onto the remote's main and ends with main's update-ref" {
  cx_tier_setup single
  cx_record_commit "$BARE_TIER" "$(cx_record_map "$BARE_TIER")
$RW_N2 $CX_ZEROS" append
  # The remote's live and main are on different commits.
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$RW_N1"
  git --git-dir="$BARE_TIER" update-ref refs/heads/main "$RW_P"
  # One local commit L above O2, with HEAD attached to main on it; live is
  # crossable, so main is the only ref the work sits on.
  rewrite_position_clone "$TIER" old
  git -C "$TIER" checkout -q -B main "$RW_LOCAL"
  git -C "$TIER" update-ref refs/heads/live "$RW_O1"
  [ "$(git -C "$TIER" symbolic-ref HEAD)" = refs/heads/main ]
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"HEAD of"* ]]
  [[ "$stderr" == *"git -C \"$TMP_REPO/$TIER\" log --oneline $RW_O2..$RW_LOCAL"* ]]
  [[ "$stderr" == *"checkout --detach refs/remotes/origin/main"* ]]
  [[ "$stderr" == *"git -C \"$TMP_REPO/$TIER\" update-ref refs/heads/main HEAD"* ]]
  [[ "$stderr" != *"checkout --detach refs/remotes/origin/live"* ]]
}

@test "cross tier: the replay HEAD's refusal prints, run once, settles HEAD and main together" {
  cx_tier_setup single
  cx_record_commit "$BARE_TIER" "$(cx_record_map "$BARE_TIER")
$RW_N2 $CX_ZEROS" append
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$RW_N1"
  git --git-dir="$BARE_TIER" update-ref refs/heads/main "$RW_P"
  rewrite_position_clone "$TIER" old
  git -C "$TIER" checkout -q -B main "$RW_LOCAL"
  git -C "$TIER" update-ref refs/heads/live "$RW_O1"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  cmds=$(printf '%s\n' "$stderr" | grep -E '^  git -C ' | grep -v ' log ' || true)
  [ "$(printf '%s\n' "$cmds" | grep -c .)" -eq 3 ]
  while IFS= read -r c; do
    run bash -c "cd / && $c"
    [ "$status" -eq 0 ]
  done <<< "$cmds"
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$(git -C "$TIER" rev-parse main)" ]
  [ "$(git -C "$TIER" rev-parse main^)" = "$RW_P" ]
  # One replay satisfies both: the rerun has nothing left to refuse.
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" show main:rw-local.md)" = "local" ]
}

# --- a store given as a relative path ---

# The printed commands run from an unrelated directory, as a person pasting them
# would, so every store path in them must be absolute.
run_printed() {
  local c
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    run bash -c "cd / && $c"
    [ "$status" -eq 0 ]
  done <<< "$1"
}

@test "cross tier: a relative store's dropped-commit move runs from another directory" {
  cx_tier_setup single
  cx_record_commit "$BARE_TIER" "$(cx_record_map "$BARE_TIER")
$RW_N2 $CX_ZEROS" append
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$RW_N1"
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  move=$(printf '%s\n' "$stderr" | grep '^  git .*update-ref')
  [ -n "$move" ]
  run_printed "$move"
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N1" ]
}

@test "cross tier: a relative store's replay commands run from another directory" {
  cx_tier_setup single
  rewrite_position_clone "$TIER" old
  git -C "$TIER" checkout -q --detach "$RW_N2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"cherry-pick $RW_O2..$RW_LOCAL"* ]]
  cmds=$(printf '%s\n' "$stderr" | grep -E '^  git -C ')
  run_printed "$cmds"
  [ "$(git -C "$TIER" show live:rw-local.md)" = "local" ]
}

@test "cross tier: a relative store's inspection command runs from another directory" {
  cx_tier_setup single
  rewrite_position_clone "$TIER" fresh
  empty=$(git -C "$TIER" mktree < /dev/null)
  unrelated=$(git -C "$TIER" -c user.email=t@t -c user.name=t commit-tree "$empty" -m unrelated)
  cx_position "$TIER" "$unrelated" "$unrelated"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"neither on the remote's history"* ]]
  cmds=$(printf '%s\n' "$stderr" | grep -E '^  git -C ')
  run_printed "$cmds"
}
