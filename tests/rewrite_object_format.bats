#!/usr/bin/env bats
# scripts/record-rewrite.sh and scripts/cross-rewrite.sh (D61, D62) take the
# length of the record's ids from the store's object format: 40 hex digits for
# sha1, 64 for sha256, and a run of zeros that long for a dropped commit.
# The fixture is a standalone sha256 store with a bare sha256 remote:
#
#   remote live (before):  P - O1 - O2
#   remote live (after):   P - N1 - N2        (force-pushed)
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2153,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/rewrite-fixtures

RECORD="$PLUGIN_ROOT/scripts/record-rewrite.sh"
CROSS="$PLUGIN_ROOT/scripts/cross-rewrite.sh"

setup() {
  setup_tmp_repo
  REMOTE="$TMP_REPO/remote256.git"
  git init -q --bare --object-format=sha256 "$REMOTE"
  git init -q --object-format=sha256 store256
  git -C store256 config user.email t@t
  git -C store256 config user.name t
  git -C store256 remote add origin "$REMOTE"
  RW_P=$(commit256 "$(git -C store256 hash-object -t tree /dev/null)" "" P)
  RW_O1=$(commit256 "$(git -C store256 write-tree)" "$RW_P" O1)
  RW_O2=$(commit256 "$(git -C store256 write-tree)" "$RW_O1" O2)
  git -C store256 update-ref refs/heads/live "$RW_O2"
  git -C store256 checkout -q live
  git -C store256 push -q origin live
  RW_N1=$(rewrite_recommit store256 "$RW_O1" "$RW_P")
  RW_N2=$(rewrite_recommit store256 "$RW_O2" "$RW_N1")
  git -C store256 push -q -f origin "$RW_N2:refs/heads/live"
  ZEROS64=$(printf '%064d' 0)
  [ "${#RW_N2}" -eq 64 ]
  [ "$(git -C store256 rev-parse --show-object-format)" = sha256 ]
}
teardown() { teardown_tmp_repo; }

# A commit of the given tree with an optional parent. Prints its id.
# Args: $1=tree  $2=parent or empty  $3=message
commit256() {
  local parent=()
  [ -z "$2" ] || parent=(-p "$2")
  git -C store256 commit-tree "$1" "${parent[@]}" -m "$3"
}

# Publish a record holding version 1 and the given map text.
# Args: $1=map text
publish_record256() {
  local mblob vblob tree commit
  mblob=$(printf '%s\n' "$1" | git -C store256 hash-object -w --stdin)
  vblob=$(printf '1\n' | git -C store256 hash-object -w --stdin)
  tree=$(printf '100644 blob %s\tmap\n100644 blob %s\tversion\n' "$mblob" "$vblob" \
    | git -C store256 mktree)
  commit=$(git -C store256 commit-tree "$tree" -m "record rewrite")
  git -C store256 push -q origin "$commit:refs/heads/gitlore/rewrites"
}

# --- record-rewrite ---

@test "record-rewrite: a sha256 store records a commit-map of 64-hex pairs" {
  rewrite_write_commit_map "$TMP_REPO/map" "$RW_P $RW_P" "$RW_O2 $RW_N2" "$RW_O1 $RW_N1" "$RW_N2 $ZEROS64"
  run --separate-stderr "$RECORD" store256 "$TMP_REPO/map"
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$REMOTE" show refs/heads/gitlore/rewrites:map)" = "$RW_O2 $RW_N2
$RW_O1 $RW_N1
$RW_N2 $ZEROS64" ]
}

@test "record-rewrite: a sha256 store refuses a commit-map of 40-hex pairs" {
  old40=$(printf '%040d' 1)
  new40=$(printf '%040d' 2)
  rewrite_write_commit_map "$TMP_REPO/map" "$old40 $new40"
  run --separate-stderr "$RECORD" store256 "$TMP_REPO/map"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"64-hex"* ]]
  [ -z "$(git --git-dir="$REMOTE" for-each-ref refs/heads/gitlore/rewrites)" ]
}

@test "record-rewrite: a sha256 store refuses a record holding 40-hex lines" {
  publish_record256 "$(printf '%040d %040d' 1 2)"
  rewrite_write_commit_map "$TMP_REPO/map" "$RW_O2 $RW_N2"
  tip=$(git --git-dir="$REMOTE" rev-parse refs/heads/gitlore/rewrites)
  run --separate-stderr "$RECORD" store256 "$TMP_REPO/map"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"64-hex"* ]]
  [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/gitlore/rewrites)" = "$tip" ]
}

@test "record-rewrite: a sha1 store still refuses a commit-map of 64-hex pairs (control)" {
  git init -q --bare "$TMP_REPO/remote1.git"
  git init -q store1
  git -C store1 remote add origin "$TMP_REPO/remote1.git"
  [ "$(git -C store1 rev-parse --show-object-format)" = sha1 ]
  rewrite_write_commit_map "$TMP_REPO/map" "$RW_O2 $RW_N2"
  run --separate-stderr "$RECORD" store1 "$TMP_REPO/map"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"40-hex"* ]]
}

# --- cross-rewrite ---

@test "cross: a sha256 store crosses HEAD and live through a 64-hex record" {
  publish_record256 "$RW_O1 $RW_N1
$RW_O2 $RW_N2"
  [ "$(git -C store256 rev-parse HEAD)" = "$RW_O2" ]
  run --separate-stderr "$CROSS" store256
  [ "$status" -eq 0 ]
  [ "$(git -C store256 rev-parse HEAD)" = "$RW_N2" ]
  [ "$(git -C store256 rev-parse live)" = "$RW_N2" ]
}

@test "cross: a sha256 chain ending in 64 zeros is a dropped commit" {
  publish_record256 "$RW_O2 $RW_N2
$RW_N2 $ZEROS64"
  run --separate-stderr "$CROSS" store256
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"dropped"* ]]
  [ "$(git -C store256 rev-parse HEAD)" = "$RW_O2" ]
  [ "$(git -C store256 rev-parse live)" = "$RW_O2" ]
}

@test "cross: a sha256 store refuses a record of 40-hex lines without echoing it" {
  line="$(printf '%040d %040d' 1 2)"
  publish_record256 "$line"
  run --separate-stderr "$CROSS" store256
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"64-hex"* ]]
  [[ "$stderr" != *"$line"* ]]
  [ "$(git -C store256 rev-parse HEAD)" = "$RW_O2" ]
}
