#!/usr/bin/env bats
# scripts/cross-rewrite.sh <store> (D62): run by hand from the project root, it
# maps a store's HEAD, `live` and `main` through the rewrite record, checks the
# trees match modulo gitlinks, checks the new commits out and stages the store's
# gitlink in its parent. Fixtures: helpers/rewrite-fixtures.bash and
# helpers/cross-fixtures.bash. This file covers discovery and a tier's own
# crossing; the memory store and the parent are cross_rewrite_memory.bats.
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

# A tier with HEAD on O1 and live on O2, the remote rewritten as $1 says:
#   ok      O1->N1, O2->N2
#   chain   a second rewrite on top: N1->X1, N2->X2
#   dropped the second rewrite dropped N2 (chain ends in 40 zeros)
#   tree    O2 maps to Z, whose tree differs from O2's outside any gitlink
tier_two_refs() {
  case "$1" in
    chain) cx_tier_setup chain ;;
    *) cx_tier_setup single ;;
  esac
  case "$1" in
    dropped)
      cx_record_commit "$BARE_TIER" "$(cx_record_map "$BARE_TIER")
$RW_N2 $CX_ZEROS" append
      ;;
    tree)
      CX_Z=$(cx_commit "$BARE_TIER" "$(cx_tree "$BARE_TIER" "$RW_N2^{tree}" "$RW_P" rw-extra.md extra)" "$RW_N1" rewritten "old two")
      git --git-dir="$BARE_TIER" update-ref refs/heads/live "$CX_Z"
      cx_record_commit "$BARE_TIER" "$RW_O1 $RW_N1
$RW_O2 $CX_Z"
      ;;
  esac
  cx_position "$TIER" "$RW_O1" "$RW_O2"
}

# --- discovery ---

@test "cross: the script exists, is executable and starts with the env shebang" {
  [ -f "$CROSS" ]
  [ -x "$CROSS" ]
  [ "$(head -1 "$CROSS")" = "#!/usr/bin/env bash" ]
}

# --- a tier: the crossing itself ---

@test "cross tier: HEAD and live on recorded old commits move to the mapped ids" {
  tier_old
  main_before=$(git -C "$TIER" rev-parse main)
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_O2" ]
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_N2" ]
  cx_detached "$TIER"
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N2" ]
  [ "$(git -C "$TIER" rev-parse refs/remotes/origin/live)" = "$RW_N2" ]
  # main was on the shared prefix: already crossed, left alone.
  [ "$(git -C "$TIER" rev-parse main)" = "$main_before" ]
  [ -f "$TIER/rw-o2.md" ]
  [ -z "$(git -C "$TIER" status --porcelain)" ]
  cx_assert_no_archive "$TIER" "$RW_O2"
}

@test "cross tier: main on a recorded commit moves too" {
  tier_old
  git -C "$TIER" update-ref refs/heads/main "$RW_O1"
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse main)" = "$RW_N1" ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N2" ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_N2" ]
}

@test "cross tier: refs on different recorded commits each move to their own mapped id" {
  tier_two_refs ok
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_N1" ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N2" ]
}

@test "cross tier: a chain is followed to its final id" {
  tier_two_refs chain
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$CX_X1" ]
  [ "$(git -C "$TIER" rev-parse live)" = "$CX_X2" ]
  cx_detached "$TIER"
  [ "$(git -C "$TIER" rev-parse refs/remotes/origin/live)" = "$CX_X2" ]
}

@test "cross tier: the record and the remote live are fetched by refspec, no archive branch" {
  tier_old
  [ -z "$(git -C "$TIER" rev-parse -q --verify refs/gitlore/rewrites || true)" ]
  [ "$(git -C "$TIER" rev-parse refs/remotes/origin/live)" != "$RW_N2" ]
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse refs/gitlore/rewrites)" = "$(git --git-dir="$BARE_TIER" rev-parse refs/heads/gitlore/rewrites)" ]
  [ -n "$(git -C "$TIER" ls-remote origin 'refs/heads/gitlore/archive/*')" ]
  cx_assert_no_archive "$TIER" "$RW_O2"
}

# --- a tier: already crossed ---

@test "cross tier: a second run finds nothing to cross" {
  tier_old
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"nothing to cross"* ]]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_N2" ]
  before=$(cx_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"nothing to cross"* ]]
  [ "$(cx_snapshot "$TIER")" = "$before" ]
}

@test "cross tier: refs already on the remote's live need nothing" {
  tier_old
  git -C "$TIER" fetch -q origin +refs/heads/live:refs/remotes/origin/live
  cx_position "$TIER" "$RW_N2" "$RW_N2"
  before=$(rewrite_store_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"nothing to cross"* ]]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
}

@test "cross tier: one ref already crossed, one not — only the old one moves" {
  tier_old
  git -C "$TIER" fetch -q origin +refs/heads/live:refs/remotes/origin/live
  git -C "$TIER" checkout -q --detach "$RW_N2"
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" != *"nothing to cross"* ]]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_N2" ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N2" ]
}

# --- a tier: refusals leave everything as it was ---

@test "cross tier: a modified tracked file refuses before anything is fetched" {
  tier_old
  echo changed >> "$TIER/MEMORY.md"
  before=$(cx_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" == *"uncommitted"* ]]
  [ "$(cx_snapshot "$TIER")" = "$before" ]
  [ "$(git -C "$TIER" rev-parse refs/remotes/origin/live)" = "$RW_P" ]
  [ -z "$(git -C "$TIER" rev-parse -q --verify refs/gitlore/rewrites || true)" ]
}

@test "cross tier: a staged file refuses before anything is fetched" {
  tier_old
  echo staged > "$TIER/staged.md"
  git -C "$TIER" add staged.md
  before=$(cx_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" == *"uncommitted"* ]]
  [ "$(cx_snapshot "$TIER")" = "$before" ]
  [ "$(git -C "$TIER" rev-parse refs/remotes/origin/live)" = "$RW_P" ]
}

@test "cross tier: an untracked file refuses before anything is fetched" {
  tier_old
  echo stray > "$TIER/stray.md"
  before=$(cx_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" == *"uncommitted"* ]]
  [ "$(cx_snapshot "$TIER")" = "$before" ]
  [ "$(git -C "$TIER" rev-parse refs/remotes/origin/live)" = "$RW_P" ]
  [ -z "$(git -C "$TIER" rev-parse -q --verify refs/gitlore/rewrites || true)" ]
}

@test "cross tier: no record on the remote refuses" {
  tier_old
  git --git-dir="$BARE_TIER" update-ref -d refs/heads/gitlore/rewrites
  before=$(rewrite_store_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" == *"no rewrite record"* ]]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
}

@test "cross tier: a chain ending in 40 zeros refuses naming the ref, nothing moves" {
  tier_two_refs dropped
  # main maps fine too, so a ref moved before live's check is visible.
  git -C "$TIER" update-ref refs/heads/main "$RW_O1"
  before=$(rewrite_store_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" == *"dropped"* ]]
  [[ "$output$stderr" == *"live"* ]]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_O1" ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_O2" ]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
}

@test "cross tier: main dropped while HEAD and live map fine refuses, nothing moves" {
  tier_two_refs dropped
  cx_position "$TIER" "$RW_O1" "$RW_O1" "$RW_O2"
  before=$(rewrite_store_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" == *"dropped"* ]]
  [[ "$output$stderr" == *"main"* ]]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_O1" ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_O1" ]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
}

@test "cross tier: a new tree that differs outside gitlinks refuses naming the ref and both ids" {
  tier_two_refs tree
  before=$(rewrite_store_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" == *"live"* ]]
  [[ "$output$stderr" == *"${RW_O2:0:7}"* ]]
  [[ "$output$stderr" == *"${CX_Z:0:7}"* ]]
  # HEAD's own mapping was fine, and still nothing moved.
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_O1" ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_O2" ]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
}

@test "cross tier: local-only commits on old history refuse with the base and a cherry-pick" {
  cx_tier_setup single
  rewrite_position_clone "$TIER" old
  before=$(rewrite_store_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" == *"cherry-pick"* ]]
  # The base is the newest recorded first-parent ancestor, O2, not O1.
  [[ "$output$stderr" == *"${RW_O2:0:7}"* ]]
  [[ "$output$stderr" == *"${RW_N2:0:7}"* ]]
  [[ "$output$stderr" != *"${RW_N1:0:7}"* ]]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_LOCAL" ]
}

@test "cross tier: a commit on history unrelated to the remote's live refuses plainly" {
  cx_tier_setup single
  rewrite_position_clone "$TIER" fresh
  # A root commit: no merge-base with origin/live, no recorded ancestor.
  empty=$(git -C "$TIER" mktree </dev/null)
  unrelated=$(git -C "$TIER" -c user.email=t@t -c user.name=t commit-tree "$empty" -m unrelated)
  cx_position "$TIER" "$unrelated" "$unrelated"
  run git -C "$TIER" merge-base "$unrelated" refs/remotes/origin/live
  [ "$status" -ne 0 ]
  before=$(rewrite_store_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" != *"cherry-pick"* ]]
  [[ "$output$stderr" != *"nothing to cross"* ]]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$unrelated" ]
}

# A store already on new history with a commit of its own past the remote's live.
tier_crossed_with_local_commit() {
  cx_tier_setup single
  git -C "$TIER" fetch -q origin +refs/heads/live:refs/remotes/origin/live +refs/heads/gitlore/rewrites:refs/gitlore/rewrites
  cx_position "$TIER" "$RW_N2" "$RW_N2"
  echo mine > "$TIER/cx-mine.md"
  git -C "$TIER" add cx-mine.md
  git -C "$TIER" -c user.email=t@t -c user.name=t commit -q -m "Mine"
  git -C "$TIER" update-ref refs/heads/live HEAD
  CX_MINE=$(git -C "$TIER" rev-parse HEAD)
}

@test "cross tier: a crossed store with a local commit on new history needs nothing" {
  tier_crossed_with_local_commit
  [ "$(git -C "$TIER" rev-parse HEAD^)" = "$RW_N2" ]
  before=$(cx_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"nothing to cross"* ]]
  [ "$(cx_snapshot "$TIER")" = "$before" ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$CX_MINE" ]
}

# live on a local commit over the old O2, HEAD already crossed: the refusal is
# about `live`.
tier_live_local_on_old() {
  cx_tier_setup single
  rewrite_position_clone "$TIER" old
  git -C "$TIER" checkout -q --detach "$RW_N2"
}

@test "cross tier: the cherry-pick refusal prints runnable git commands with full ids" {
  tier_live_local_on_old
  before=$(rewrite_store_snapshot "$TIER")
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$output$stderr" == *"git -C \"$TIER\" checkout --detach $RW_N2"* ]]
  [[ "$output$stderr" == *"git -C \"$TIER\" cherry-pick $RW_O2..$RW_LOCAL"* ]]
  [[ "$output$stderr" == *"git -C \"$TIER\" update-ref refs/heads/live HEAD"* ]]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
}

@test "cross tier: running the printed commands, then the script, completes the crossing" {
  tier_live_local_on_old
  run --separate-stderr "$CROSS" "$TIER"
  refused
  cmds=$(printf '%s\n' "$output$stderr" | grep -E '^[[:space:]]*git -C ' | sed -E 's/^[[:space:]]+//' || true)
  [ "$(printf '%s\n' "$cmds" | grep -c .)" -ge 3 ]
  while IFS= read -r c; do
    [ -n "$c" ] || continue
    bash -c "$c"
  done <<< "$cmds"
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse live)" = "$(git -C "$TIER" rev-parse HEAD)" ]
  [ "$(git -C "$TIER" rev-parse live^)" = "$RW_N2" ]
  [ "$(git -C "$TIER" show live:rw-local.md)" = "local" ]
  [ "$(git -C "$TIER" rev-parse live)" != "$RW_LOCAL" ]
}
