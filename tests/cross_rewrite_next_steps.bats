#!/usr/bin/env bats
# scripts/cross-rewrite.sh (D62, D63): a refusal about a store that is absent,
# a remote that cannot be reached or a record that cannot be read names the
# command that resolves it; the diagnosing refusals are
# cross_rewrite_diagnoses.bats. Fixtures: helpers/rewrite-fixtures.bash and
# helpers/cross-fixtures.bash.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2153,SC2030,SC2031,SC2016
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

# The refusal case: exit 1, prefixed, and nothing in the store moved.
refused() {
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"cross-rewrite:"* ]]
}

# Replace the tier remote's record with one whose tree holds only the named
# file, holding `1`. Args: $1=version|map
tier_record_with_only() {
  local blob tree commit
  blob=$(printf '1\n' | git --git-dir="$BARE_TIER" hash-object -w --stdin)
  tree=$(printf '100644 blob %s\t%s\n' "$blob" "$1" | git --git-dir="$BARE_TIER" mktree)
  commit=$(git --git-dir="$BARE_TIER" -c user.email=t@t -c user.name=t commit-tree "$tree" -m "partial record")
  git --git-dir="$BARE_TIER" update-ref refs/heads/gitlore/rewrites "$commit"
}

# The refusal in $stderr rebuilds the record at the origin of the store $1 from
# scratch: it deletes the record branch there, records a commit-map with the
# absolute path of record-rewrite.sh, checks with ls-remote, says that a rewrite
# whose commit-map is gone drops out, and offers no in-place repair.
# Args: $1=store path.
assert_rebuild_named() {
  local abs root
  abs=$(cd "$1" && pwd -P)
  root=$(cd "$PLUGIN_ROOT" && pwd -P)
  [[ "$stderr" == *"Rebuild the record of $abs from scratch"* ]]
  [[ "$stderr" == *"git -C \"$abs\" push origin --delete gitlore/rewrites"* ]]
  [[ "$stderr" == *"$root/scripts/record-rewrite.sh\" \"$abs\" \""* ]]
  [[ "$stderr" == *"git -C \"$abs\" ls-remote origin gitlore/rewrites"* ]]
  [[ "$stderr" == *"commit-map is no longer at hand drops out"* ]]
  [[ "$stderr" == *"run this again"* ]]
  [[ "$stderr" != *"--rebuild"* ]]
  [[ "$stderr" != *"Ask the owner"* ]]
}

# --- the next step ---

# Runs the command a refusal prints after "Check it out with: ", from an
# unrelated directory, as a person pasting it would.
run_printed_checkout() {
  local cmd="${stderr#*Check it out with: }"
  cmd="${cmd%%$'\n'*}"
  run bash -c "cd / && $cmd"
  [ "$status" -eq 0 ]
}

@test "cross: a tier that is not checked out is refused with a checkout command that works" {
  cx_tier_setup single
  cx_memory_setup mapped
  git -C memory submodule deinit -q -f ddaanet
  [ ! -e memory/ddaanet/.git ]
  [ -z "$(git -C memory status --porcelain)" ]
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"not a checked-out store"* ]]
  run_printed_checkout
  [ -e memory/ddaanet/.git ]
}

@test "cross: a memory store that is not checked out is refused with a checkout command that works" {
  make_parent_with_memory
  git submodule deinit -q -f memory
  [ ! -e memory/.git ]
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$stderr" == *"not a checked-out store"* ]]
  run_printed_checkout
  [ -e memory/.git ]
}

@test "cross: a store whose directory does not exist is refused with the root form" {
  run --separate-stderr "$CROSS" no/such/store
  refused
  [[ "$stderr" == *'git submodule update --init -- "no/such/store"'* ]]
}

@test "cross memory: a tier that is not checked out is refused, naming the checkout command" {
  cx_tier_setup single
  cx_memory_setup mapped
  git -C memory submodule deinit -q -f ddaanet
  [ ! -e memory/ddaanet/.git ]
  [ -z "$(git -C memory status --porcelain)" ]
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$stderr" == *"not checked out"* ]]
  [[ "$stderr" == *'git -C "memory" submodule update --init -- "ddaanet"'* ]]
}

@test "cross tier: a record with no version file is refused, naming the rebuild" {
  cx_tier_setup single
  tier_record_with_only map
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"version"* ]]
  assert_rebuild_named "$TIER"
}

@test "cross tier: a record with no map file is refused, naming the rebuild" {
  cx_tier_setup single
  tier_record_with_only version
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"map"* ]]
  assert_rebuild_named "$TIER"
}

@test "cross tier: a record of a version this script does not read is refused, naming the update" {
  cx_tier_setup single
  work=$(mktemp -d "$TMP_REPO/work.XXXXXX")
  git clone -q "$BARE_TIER" "$work"
  git --git-dir="$BARE_TIER" update-ref -d refs/heads/gitlore/rewrites
  rewrite_publish_record "$work" "$RW_O1 $RW_N1" 2
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"not version 1"* ]]
  [[ "$stderr" == *"Update gitlore"* ]]
}

# Replace the tier remote's record with one holding the given version bytes
# (no newline added) and the record's map.
tier_record_version() {
  local vblob mblob tree commit
  vblob=$(printf '%s' "$1" | git --git-dir="$BARE_TIER" hash-object -w --stdin)
  mblob=$(cx_record_map "$BARE_TIER" | git --git-dir="$BARE_TIER" hash-object -w --stdin)
  tree=$(printf '100644 blob %s\tmap\n100644 blob %s\tversion\n' "$mblob" "$vblob" \
    | git --git-dir="$BARE_TIER" mktree)
  commit=$(git --git-dir="$BARE_TIER" -c user.email=t@t -c user.name=t commit-tree "$tree" -m "record")
  git --git-dir="$BARE_TIER" update-ref refs/heads/gitlore/rewrites "$commit"
}

@test "cross tier: a version that is not an integer is a damaged record, not a newer format" {
  local bad
  cx_tier_setup single
  for bad in "" $'1\r' "one" "1.5" "-2" "0"; do
    tier_record_version "$bad"
    run --separate-stderr "$CROSS" "$TIER"
    refused
    [[ "$stderr" == *"not a version number"* ]]
    assert_rebuild_named "$TIER"
    [[ "$stderr" != *"Update gitlore"* ]]
  done
}

@test "cross tier: a version that is an integer above 1 is a newer format" {
  cx_tier_setup single
  tier_record_version "12"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"Update gitlore"* ]]
  [[ "$stderr" != *"--delete"* ]]
}

@test "cross tier: a remote that cannot be fetched from is refused, saying to run it again" {
  cx_tier_setup single
  git -C "$TIER" remote set-url origin "$TMP_REPO/no-such-remote.git"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"could not fetch"* ]]
  [[ "$stderr" == *"run this again"* ]]
}

@test "cross tier: a remote with no record is refused, naming the command that publishes it" {
  cx_tier_setup single
  git --git-dir="$BARE_TIER" update-ref -d refs/heads/gitlore/rewrites
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"no rewrite record"* ]]
  [[ "$stderr" == *'record-rewrite.sh" "$MIRROR" "$MIRROR/filter-repo/commit-map" '* ]]
  [[ "$stderr" != *"--delete"* ]]
}

# Runs the indented lines of the refusal in $stderr, as a person would paste
# them: from an unrelated directory, stopping at the first failure. A
# `<commit-map>` placeholder is first replaced by $1 when given.
# Args: $1=commit-map path (optional)
run_printed_rebuild() {
  printf '%s\n' "$stderr" | grep '^  ' > "$TMP_REPO/rebuild.sh"
  [ "$(wc -l < "$TMP_REPO/rebuild.sh")" -eq 3 ]
  if [ -n "${1:-}" ]; then
    sed "s|<commit-map>|$1|" "$TMP_REPO/rebuild.sh" > "$TMP_REPO/rebuild.sub"
    mv "$TMP_REPO/rebuild.sub" "$TMP_REPO/rebuild.sh"
  fi
  run bash -ec "cd / && . $(printf '%q' "$TMP_REPO/rebuild.sh")"
}

@test "cross tier: a damaged record is refused with a from-scratch rebuild, and the printed commands make the crossing succeed" {
  cx_tier_setup single
  tier_record_with_only map
  # The commit-map of the rewrite is in the clone's own git dir.
  mapdir=$(git -C "$TIER" rev-parse --git-path filter-repo)
  case "$mapdir" in /*) ;; *) mapdir="$TIER/$mapdir" ;; esac
  mkdir -p "$mapdir"
  rewrite_write_commit_map "$mapdir/commit-map" "$RW_P $RW_P" "$RW_O1 $RW_N1" "$RW_O2 $RW_N2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  assert_rebuild_named "$TIER"
  [[ "$stderr" == *"$(cd "$mapdir" && pwd -P)/commit-map\""* ]]
  [[ "$stderr" != *"<commit-map>"* ]]
  run_printed_rebuild
  [ "$status" -eq 0 ]
  [[ "$output" == *"refs/heads/gitlore/rewrites"* ]]
  [ "$(git --git-dir="$BARE_TIER" show refs/heads/gitlore/rewrites:version)" = 1 ]
  [ "$(git --git-dir="$BARE_TIER" show refs/heads/gitlore/rewrites:map)" = "$RW_O1 $RW_N1
$RW_O2 $RW_N2" ]
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N2" ]
}

@test "cross tier: with no commit-map in the clone the refusal says where it is and names the one placeholder" {
  cx_tier_setup single
  tier_record_with_only map
  run --separate-stderr "$CROSS" "$TIER"
  refused
  assert_rebuild_named "$TIER"
  [[ "$stderr" == *".git/filter-repo/commit-map of the clone that ran the rewrite"* ]]
  [ "$(printf '%s' "$stderr" | grep -o '<[a-z-]*>' | sort -u)" = "<commit-map>" ]
  # The mirror the rewrite ran in holds the commit-map.
  mirror="$TMP_REPO/mirror.git"
  git clone -q --mirror "$BARE_TIER" "$mirror"
  mkdir "$mirror/filter-repo"
  rewrite_write_commit_map "$mirror/filter-repo/commit-map" "$RW_P $RW_P" "$RW_O1 $RW_N1" "$RW_O2 $RW_N2"
  run_printed_rebuild "$mirror/filter-repo/commit-map"
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$BARE_TIER" show refs/heads/gitlore/rewrites:map)" = "$RW_O1 $RW_N1
$RW_O2 $RW_N2" ]
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N2" ]
}

@test "cross tier: the record of two rewrites is rebuilt with one record-rewrite.sh call per commit-map, oldest first" {
  cx_tier_setup chain
  tier_record_with_only map
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  assert_rebuild_named "$TIER"
  rewrite_write_commit_map "$TMP_REPO/map1" "$RW_P $RW_P" "$RW_O1 $RW_N1" "$RW_O2 $RW_N2"
  rewrite_write_commit_map "$TMP_REPO/map2" "$RW_P $RW_P" "$RW_N1 $CX_X1" "$RW_N2 $CX_X2"
  # The delete line, one record line per map in rewrite order, the check.
  printf '%s\n' "$stderr" | grep '^  ' > "$TMP_REPO/printed.sh"
  {
    sed -n 1p "$TMP_REPO/printed.sh"
    sed -n 2p "$TMP_REPO/printed.sh" | sed "s|<commit-map>|$TMP_REPO/map1|"
    sed -n 2p "$TMP_REPO/printed.sh" | sed "s|<commit-map>|$TMP_REPO/map2|"
    sed -n 3p "$TMP_REPO/printed.sh"
  } > "$TMP_REPO/rebuild.sh"
  run bash -ec "cd / && . $(printf '%q' "$TMP_REPO/rebuild.sh")"
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$BARE_TIER" show refs/heads/gitlore/rewrites:map)" = "$RW_O1 $RW_N1
$RW_O2 $RW_N2
$RW_N1 $CX_X1
$RW_N2 $CX_X2" ]
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse live)" = "$CX_X2" ]
}

@test "cross: a git that fails to report the object format fails with git's own message" {
  cx_tier_setup single
  real=$(command -v git)
  mkdir "$TMP_REPO/stub"
  cat > "$TMP_REPO/stub/git" <<STUB
#!/bin/sh
case "\$*" in *--show-object-format*) echo "stub-git: unknown option" >&2; exit 129 ;; esac
exec "$real" "\$@"
STUB
  chmod 755 "$TMP_REPO/stub/git"
  before=$(rewrite_store_snapshot "$TIER")
  PATH="$TMP_REPO/stub:$PATH" run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"stub-git: unknown option"* ]]
  [[ "$stderr" != *"could not read the object format"* ]]
  [ "$(rewrite_store_snapshot "$TIER")" = "$before" ]
}

@test "cross tier: a record whose chain does not end prints the rebuild" {
  cx_tier_setup single
  cx_record_commit "$BARE_TIER" "$RW_O2 $RW_N2
$RW_N2 $RW_O2"
  cx_position "$TIER" "$RW_O2" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"does not end"* ]]
  assert_rebuild_named "$TIER"
}

@test "cross tier: a relative origin url is printed absolute, so it holds under -C \"\$MIRROR\"" {
  cx_tier_setup single
  git --git-dir="$BARE_TIER" update-ref -d refs/heads/gitlore/rewrites
  git -C "$TIER" remote set-url origin ../../.bare-ddaanet.git
  [ "$(git -C "$TIER" remote get-url origin)" = ../../.bare-ddaanet.git ]
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *'record-rewrite.sh" "$MIRROR" "$MIRROR/filter-repo/commit-map" '"$BARE_TIER"* ]]
  [[ "$stderr" != *"../../.bare-ddaanet.git"* ]]
}

@test "cross: a tier whose memory store is not checked out prints the memory step before the tier step" {
  cx_tier_setup single
  cx_memory_setup mapped
  # The project pins the memory commit that holds the tier.
  git add memory
  git submodule deinit -q -f memory
  [ ! -e memory/.git ]
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"submodule update --init -- \"memory\" && "* ]]
  run_printed_checkout
  [ -e memory/ddaanet/.git ]
}
