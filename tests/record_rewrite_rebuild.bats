#!/usr/bin/env bats
# scripts/record-rewrite.sh --rebuild (D63): repairs a damaged `gitlore/rewrites`
# record in place. It keeps every readable line of the record on the remote,
# drops the rest and reports their line numbers, merges the commit-map and
# pushes one fast-forward on the tip it read, so the record is never absent
# from the remote and never rewritten.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2153,SC2030,SC2031,SC2016
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/rewrite-fixtures

SCRIPT="$PLUGIN_ROOT/scripts/record-rewrite.sh"

setup() {
  setup_tmp_repo
  REMOTE="$TMP_REPO/remote.git"
  git init -q --bare "$REMOTE"
  git init -q store
  git -C store config user.email t@t
  git -C store config user.name t
  git -C store commit -q --allow-empty -m base
  git -C store remote add origin "$REMOTE"
  UPDATES="$TMP_REPO/updates.log"
  printf '#!/bin/sh\nprintf "%%s %%s %%s\\n" "$1" "$2" "$3" >> "%s"\n' "$UPDATES" > "$REMOTE/hooks/update"
  chmod 755 "$REMOTE/hooks/update"
  A=$(id_n 1); B=$(id_n 2); C=$(id_n 3); D=$(id_n 4); E=$(id_n 5)
}
teardown() { teardown_tmp_repo; }

id_n() { printf '%040x' "$1"; }

# Publish a record holding the given version bytes and map bytes (neither gets
# a newline added) as a root commit, replacing any record. Sets TIP.
# Args: $1=version bytes  $2=map bytes
publish() {
  local vblob mblob tree
  vblob=$(printf '%s' "$1" | git -C store hash-object -w --stdin)
  mblob=$(printf '%s' "$2" | git -C store hash-object -w --stdin)
  tree=$(printf '100644 blob %s\tmap\n100644 blob %s\tversion\n' "$mblob" "$vblob" | git -C store mktree)
  TIP=$(git -C store commit-tree "$tree" -m "record rewrite")
  git -C store push -q -f origin "$TIP:refs/heads/gitlore/rewrites"
  : > "$UPDATES"
}

remote_map() { git --git-dir="$REMOTE" show refs/heads/gitlore/rewrites:map; }

# A commit-map with the given changed lines.
# Args: $1...=lines
write_map() { rewrite_write_commit_map "$TMP_REPO/map" "$@"; }

@test "rebuild: a healthy record is extended, its old bytes kept" {
  publish $'1\n' "$A $B"$'\n'
  write_map "$C $D"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 0 ]
  [ "$(remote_map)" = "$A $B
$C $D" ]
  [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/gitlore/rewrites^)" = "$TIP" ]
  [ -z "$stderr" ]
}

@test "rebuild: readable lines survive, unreadable ones are dropped and reported by number, not echoed" {
  publish $'1\n' "$A $B"$'\n'"garbage \$(touch PWNED)"$'\n'"$C $D"$'\n'"short"
  write_map "$D $E"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 0 ]
  [ "$(remote_map)" = "$A $B
$C $D
$D $E" ]
  [[ "$stderr" == *"2"* ]]
  [[ "$stderr" == *"4"* ]]
  [[ "$stderr" != *"garbage"* ]]
  [[ "$stderr" != *"PWNED"* ]]
}

@test "rebuild: a version file that is damaged is replaced by version 1" {
  publish $'1\r\n' "$A $B"$'\n'
  write_map "$C $D"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$REMOTE" show refs/heads/gitlore/rewrites:version)" = "1" ]
  [ "$(remote_map)" = "$A $B
$C $D" ]
}

@test "rebuild: a record with no map file starts from an empty map" {
  local blob tree
  blob=$(printf '1\n' | git -C store hash-object -w --stdin)
  tree=$(printf '100644 blob %s\tversion\n' "$blob" | git -C store mktree)
  TIP=$(git -C store commit-tree "$tree" -m "no map")
  git -C store push -q -f origin "$TIP:refs/heads/gitlore/rewrites"
  write_map "$C $D"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 0 ]
  [ "$(remote_map)" = "$C $D" ]
}

@test "rebuild: a line that closes a chain loop is dropped and reported" {
  publish $'1\n' "$A $B"$'\n'"$B $C"$'\n'"$C $A"$'\n'
  write_map "$D $E"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 0 ]
  [ "$(remote_map)" = "$A $B
$B $C
$D $E" ]
  [[ "$stderr" == *"3"* ]]
}

@test "rebuild: a record of a newer version is refused untouched" {
  publish $'2\n' "$A $B"$'\n'
  write_map "$C $D"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 1 ]
  [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/gitlore/rewrites)" = "$TIP" ]
}

@test "rebuild: a commit-map line that contradicts a kept line is refused untouched" {
  publish $'1\n' "$A $B"$'\n'
  write_map "$A $C"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"second rewrite"* ]]
  [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/gitlore/rewrites)" = "$TIP" ]
}

@test "rebuild: the remote's record is updated once, as a fast-forward, never deleted" {
  publish $'1\n' "$A $B"$'\n'"bad"$'\n'
  write_map "$C $D"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$UPDATES")" -eq 1 ]
  new=$(git --git-dir="$REMOTE" rev-parse refs/heads/gitlore/rewrites)
  [ "$(cat "$UPDATES")" = "refs/heads/gitlore/rewrites $TIP $new" ]
  git --git-dir="$REMOTE" merge-base --is-ancestor "$TIP" "$new"
}

@test "record-rewrite: without --rebuild a damaged record is still refused" {
  publish $'1\n' "$A $B"$'\n'"bad"$'\n'
  write_map "$C $D"
  run --separate-stderr "$SCRIPT" store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 1 ]
  [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/gitlore/rewrites)" = "$TIP" ]
}

# A `git` shim ahead of the real one on PATH. When the script pushes, it first
# runs the given command against the remote, so the record moves between the
# script's read and its push. Args: $1...=the git arguments to run on REMOTE
move_remote_before_push() {
  local real
  real=$(command -v git)
  mkdir -p "$TMP_REPO/shim"
  {
    printf '#!/bin/sh\n'
    printf 'for a in "$@"; do\n  if [ "$a" = push ]; then\n    %q --git-dir=%q' "$real" "$REMOTE"
    printf ' %q' "$@"
    printf '\n    break\n  fi\ndone\nexec %q "$@"\n' "$real"
  } > "$TMP_REPO/shim/git"
  chmod 755 "$TMP_REPO/shim/git"
  PATH="$TMP_REPO/shim:$PATH"
}

# Publish a child of the current TIP holding the given version and map bytes.
# Sets ROOT to the parent and TIP to the child.
publish_child() {
  local vblob mblob tree
  ROOT="$TIP"
  vblob=$(printf '%s' "$1" | git -C store hash-object -w --stdin)
  mblob=$(printf '%s' "$2" | git -C store hash-object -w --stdin)
  tree=$(printf '100644 blob %s\tmap\n100644 blob %s\tversion\n' "$mblob" "$vblob" | git -C store mktree)
  TIP=$(git -C store commit-tree "$tree" -p "$ROOT" -m "record rewrite")
  git -C store push -q -f origin "$TIP:refs/heads/gitlore/rewrites"
}

@test "rebuild: a record rolled back to an ancestor between the read and the push is refused" {
  publish $'1\n' "$A $B"$'\n'
  publish_child $'1\n' "$A $B"$'\n'"bad"$'\n'
  write_map "$C $D"
  move_remote_before_push update-ref refs/heads/gitlore/rewrites "$ROOT"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"refused the record"* ]]
  [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/gitlore/rewrites)" = "$ROOT" ]
}

@test "rebuild: a record deleted between the read and the push is refused, not recreated" {
  publish $'1\n' "$A $B"$'\n'"bad"$'\n'
  write_map "$C $D"
  move_remote_before_push update-ref -d refs/heads/gitlore/rewrites
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"refused the record"* ]]
  run git --git-dir="$REMOTE" rev-parse -q --verify refs/heads/gitlore/rewrites
  [ "$status" -ne 0 ]
}

@test "rebuild: a record created between a read that found none and the push is refused" {
  write_map "$C $D"
  git -C store push -q origin HEAD:refs/heads/other
  move_remote_before_push update-ref refs/heads/gitlore/rewrites "$(git -C store rev-parse HEAD)"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"refused the record"* ]]
  [ "$(git --git-dir="$REMOTE" rev-parse refs/heads/gitlore/rewrites)" = "$(git -C store rev-parse HEAD)" ]
}

@test "rebuild: a map with CRLF line endings keeps its lines" {
  publish $'1\n' "$A $B"$'\r\n'"$C $D"$'\r\n'
  write_map "$D $E"
  run --separate-stderr "$SCRIPT" --rebuild store "$TMP_REPO/map" "$REMOTE"
  [ "$status" -eq 0 ]
  [ "$(remote_map)" = "$A $B
$C $D
$D $E" ]
  [[ "$stderr" == *"carriage return"* ]]
  [ -z "$(git --git-dir="$REMOTE" show refs/heads/gitlore/rewrites:map | tr -d '\n0-9a-f ')" ]
}
