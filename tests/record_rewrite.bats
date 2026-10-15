#!/usr/bin/env bats
# scripts/record-rewrite.sh <store> <commit-map> (D61): run by hand after
# `git filter-repo`, before the force-push, it appends the changed lines of the
# commit-map to the append-only `gitlore/rewrites` record on origin.
# Fixture: helpers/rewrite-fixtures.bash.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2153,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/rewrite-fixtures

SCRIPT="$PLUGIN_ROOT/scripts/record-rewrite.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  BARE="$TMP_REPO/.bare-memory.git"
  ZEROS=0000000000000000000000000000000000000000
  make_parent_with_memory
  rewrite_remote_history memory "$BARE"
  rewrite_position_clone memory fresh
  # The first rewrite's record is already on the remote; tests that need no
  # record drop it. Its map is republished in ascending order and the second
  # rewrite's changed lines are written descending, so old map + new lines is
  # sorted in neither direction: a green that sorts the map cannot match.
  OLD_MAP=$(git --git-dir="$BARE" show refs/heads/gitlore/rewrites:map | LC_ALL=C sort)
  OLD_RECORD_TIP=$(rewrite_replace_record "$BARE" "$OLD_MAP")
  # A second rewrite of the same store: new ids for N1/N2, a dropped commit, an
  # unchanged one. The commits exist as objects only; no ref names them. A
  # committer of their own: rewrite_recommit's fixed identity would reproduce
  # N1/N2 byte for byte whenever both rewrites land in the same second.
  RW_M1=$(second_recommit "$RW_N1" "$RW_P")
  RW_M2=$(second_recommit "$RW_N2" "$RW_M1")
  [ "$RW_M1" != "$RW_N1" ]
  [ "$RW_M2" != "$RW_N2" ]
  RW_DROPPED=$(git -C memory commit-tree "$RW_P^{tree}" -p "$RW_P" -m dropped)
  EXPECTED_NEW=$(printf '%s\n' "$RW_N1 $RW_M1" "$RW_N2 $RW_M2" "$RW_DROPPED $ZEROS" | LC_ALL=C sort -r)
  MAP="$TMP_REPO/commit-map"
  local changed=() line
  while IFS= read -r line || [ -n "$line" ]; do changed+=("$line"); done <<< "$EXPECTED_NEW"
  rewrite_write_commit_map "$MAP" "$RW_P $RW_P" "${changed[@]}"
}
teardown() { teardown_tmp_repo; }

# Same tree and parent as $1, a second rewrite's committer.
# Args: $1=old commit  $2=new parent
second_recommit() {
  GIT_AUTHOR_NAME=second GIT_AUTHOR_EMAIL=second@t \
  GIT_COMMITTER_NAME=second GIT_COMMITTER_EMAIL=second@t \
    git -C memory commit-tree "$1^{tree}" -p "$2" -m "$(git -C memory log -1 --format=%s "$1")"
}

# Point the remote's record at a fresh root commit holding version 1 and the
# given map. Prints the new tip. Args: $1=bare  $2=map text
rewrite_replace_record() {
  local bare="$1" mblob vblob tree commit
  mblob=$(printf '%s\n' "$2" | git --git-dir="$bare" hash-object -w --stdin) || return 1
  vblob=$(printf '1\n' | git --git-dir="$bare" hash-object -w --stdin) || return 1
  tree=$(printf '100644 blob %s\tmap\n100644 blob %s\tversion\n' "$mblob" "$vblob" \
    | git --git-dir="$bare" mktree) || return 1
  commit=$(git --git-dir="$bare" -c user.email=t@t -c user.name=t commit-tree "$tree" -m "record rewrite") || return 1
  git --git-dir="$bare" update-ref refs/heads/gitlore/rewrites "$commit" || return 1
  printf '%s\n' "$commit"
}

drop_remote_record() { git --git-dir="$BARE" update-ref -d refs/heads/gitlore/rewrites; }

remote_refs() { git --git-dir="$BARE" for-each-ref; }

# --- the record is created ---

@test "record-rewrite: with no record on origin it creates one holding only version and map" {
  drop_remote_record
  # Run as the owner runs it, through its shebang and mode.
  run --separate-stderr "$SCRIPT" memory "$MAP"
  [ "$status" -eq 0 ]
  [ -n "$(git --git-dir="$BARE" for-each-ref refs/heads/gitlore/rewrites)" ]
  tip=$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)
  [ "$(git --git-dir="$BARE" ls-tree --name-only "$tip" | paste -sd, -)" = "map,version" ]
  [ "$(git --git-dir="$BARE" show "$tip:version")" = "1" ]
  # Changed lines only: no header, no unchanged P line, the dropped one kept;
  # compared as bytes, so the final newline the next append relies on counts.
  git --git-dir="$BARE" show "$tip:map" | cmp - <(printf '%s\n' "$EXPECTED_NEW")
  # A first record is a root commit.
  [ "$(git --git-dir="$BARE" rev-list --count "$tip")" -eq 1 ]
}

# --- the record is appended to ---

@test "record-rewrite: an existing record is extended by a fast-forward, old lines byte-identical" {
  run --separate-stderr bash "$SCRIPT" memory "$MAP"
  [ "$status" -eq 0 ]
  tip=$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)
  [ "$tip" != "$OLD_RECORD_TIP" ]
  [ "$(git --git-dir="$BARE" rev-parse "$tip^")" = "$OLD_RECORD_TIP" ]
  git --git-dir="$BARE" show "$OLD_RECORD_TIP:map" > "$TMP_REPO/old-map"
  git --git-dir="$BARE" show "$tip:map" > "$TMP_REPO/new-map"
  size=$(wc -c < "$TMP_REPO/old-map")
  head -c "$size" "$TMP_REPO/new-map" | cmp - "$TMP_REPO/old-map"
  tail -c +"$((size + 1))" "$TMP_REPO/new-map" | cmp - <(printf '%s\n' "$EXPECTED_NEW")
  [ "$(git --git-dir="$BARE" show "$tip:version")" = "1" ]
  [ "$(git --git-dir="$BARE" ls-tree --name-only "$tip" | paste -sd, -)" = "map,version" ]
}

@test "record-rewrite: running again with the same commit-map adds nothing and says so" {
  run --separate-stderr bash "$SCRIPT" memory "$MAP"
  [ "$status" -eq 0 ]
  tip=$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)
  [ "$tip" != "$OLD_RECORD_TIP" ]
  nlines=$(git --git-dir="$BARE" show "$tip:map" | wc -l)
  run --separate-stderr bash "$SCRIPT" memory "$MAP"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"already"* ]]
  [ "$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)" = "$tip" ]
  [ "$(git --git-dir="$BARE" show "$tip:map" | wc -l)" = "$nlines" ]
}

# --- refusals ---

# Run the script expecting a refusal that pushes nothing.
# Args: $1=store  $2=commit-map
assert_refused_untouched() {
  local before
  before=$(remote_refs)
  run --separate-stderr bash "$SCRIPT" "$1" "$2"
  [ "$status" -ne 0 ]
  [ -n "$output$stderr" ]
  [ "$(remote_refs)" = "$before" ]
}

@test "record-rewrite: a commit-map whose lines are not 40-hex pairs is refused" {
  drop_remote_record
  # filter-repo's own header, so a refusal cannot come from the header.
  rewrite_write_commit_map "$TMP_REPO/bad-map" "not-a-hash also-not"
  assert_refused_untouched memory "$TMP_REPO/bad-map"
  [ -z "$(git --git-dir="$BARE" for-each-ref refs/heads/gitlore/rewrites)" ]
}

@test "record-rewrite: a half-valid commit-map is refused whole" {
  rewrite_write_commit_map "$TMP_REPO/half-map" "$RW_N1 $RW_M1" "$RW_N2 short"
  assert_refused_untouched memory "$TMP_REPO/half-map"
  [ "$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)" = "$OLD_RECORD_TIP" ]
}

@test "record-rewrite: a commit-map with no changed lines is refused" {
  rewrite_write_commit_map "$TMP_REPO/same-map" "$RW_P $RW_P" "$RW_N1 $RW_N1"
  assert_refused_untouched memory "$TMP_REPO/same-map"
  [ "$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)" = "$OLD_RECORD_TIP" ]
}

@test "record-rewrite: an existing record whose version is not 1 is refused" {
  drop_remote_record
  work=$(mktemp -d "$TMP_REPO/work.XXXXXX")
  git clone -q "$BARE" "$work"
  rewrite_publish_record "$work" "$OLD_MAP" 2
  v2_tip=$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)
  assert_refused_untouched memory "$MAP"
  [ "$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)" = "$v2_tip" ]
}

@test "record-rewrite: a record that exists but cannot be fetched is refused, not replaced" {
  rewrite_break_record "$BARE"
  broken_tip=$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)
  assert_refused_untouched memory "$MAP"
  [ "$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)" = "$broken_tip" ]
}

# --- what it leaves alone ---

@test "record-rewrite: the store's branches, HEAD, index and worktree are untouched" {
  before=$(rewrite_store_snapshot memory)
  remote_before=$(remote_refs | grep -v 'refs/heads/gitlore/rewrites$')
  run --separate-stderr bash "$SCRIPT" memory "$MAP"
  [ "$status" -eq 0 ]
  # Premise: it published, so an untouched store is not just a no-op.
  [ "$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)" != "$OLD_RECORD_TIP" ]
  [ "$(rewrite_store_snapshot memory)" = "$before" ]
  # The record is the only remote ref it moves.
  [ "$(remote_refs | grep -v 'refs/heads/gitlore/rewrites$')" = "$remote_before" ]
}

@test "record-rewrite: it never pushes or creates an archive branch" {
  git --git-dir="$BARE" update-ref -d refs/heads/gitlore/archive/2026-10-15
  [ -z "$(git --git-dir="$BARE" for-each-ref 'refs/heads/gitlore/archive/')" ]
  run --separate-stderr bash "$SCRIPT" memory "$MAP"
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)" != "$OLD_RECORD_TIP" ]
  [ -z "$(git --git-dir="$BARE" for-each-ref | grep '/archive/' || true)" ]
  [ -z "$(git -C memory for-each-ref | grep '/archive/' || true)" ]
}

# --- discovery ---

@test "record-rewrite: the script exists and is executable" {
  [ -f "$SCRIPT" ]
  [ -x "$SCRIPT" ]
}

# --- a bare mirror with no origin (how a rewrite is really run) ---

# A bare `git clone --mirror` of the store's remote with `origin` removed, as
# filter-repo leaves it. Sets MIRROR.
make_bare_mirror() {
  MIRROR="$TMP_REPO/memory-after.git"
  git clone -q --mirror "$BARE" "$MIRROR"
  git -C "$MIRROR" remote remove origin
  [ -z "$(git -C "$MIRROR" config --get remote.origin.url || true)" ]
  [ "$(git -C "$MIRROR" rev-parse --is-bare-repository)" = "true" ]
}

@test "record-rewrite: a bare mirror with no origin pushes to an explicit remote URL" {
  make_bare_mirror
  drop_remote_record
  run --separate-stderr bash "$SCRIPT" "$MIRROR" "$MAP" "$BARE"
  [ "$status" -eq 0 ]
  [ -n "$(git --git-dir="$BARE" for-each-ref refs/heads/gitlore/rewrites)" ]
  tip=$(git --git-dir="$BARE" rev-parse refs/heads/gitlore/rewrites)
  [ "$(git --git-dir="$BARE" ls-tree --name-only "$tip" | paste -sd, -)" = "map,version" ]
  [ "$(git --git-dir="$BARE" show "$tip:map")" = "$EXPECTED_NEW" ]
}

@test "record-rewrite: a bare mirror with no origin and no remote argument is refused, naming the remote" {
  make_bare_mirror
  drop_remote_record
  before=$(remote_refs)
  run --separate-stderr bash "$SCRIPT" "$MIRROR" "$MAP"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"origin"* ]]
  [ "$(remote_refs)" = "$before" ]
}

@test "record-rewrite: a non-bare store with origin and no remote argument still works (control)" {
  drop_remote_record
  [ "$(git -C memory rev-parse --is-bare-repository)" = "false" ]
  run --separate-stderr bash "$SCRIPT" memory "$MAP"
  [ "$status" -eq 0 ]
  [ -n "$(git --git-dir="$BARE" for-each-ref refs/heads/gitlore/rewrites)" ]
}
