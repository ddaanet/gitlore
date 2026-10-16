#!/usr/bin/env bats
# scripts/cross-rewrite.sh (D62): a refusal the user must act on names the
# command or action that resolves it, and a child store's record is fetched
# once per run however many refs and gitlinks consult it. Fixtures:
# helpers/rewrite-fixtures.bash and helpers/cross-fixtures.bash.
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

# The refusal in $stderr rebuilds the record at the origin of the store $1 with
# commands that name the mirror variable, the record script and that origin's URL.
# Args: $1=store path.
assert_rebuild_named() {
  local url
  url=$(git -C "$1" remote get-url origin)
  [[ "$stderr" == *'git -C "$MIRROR" push '*"$url"*' --delete gitlore/rewrites'* ]]
  [[ "$stderr" == *'record-rewrite.sh" "$MIRROR" "$MIRROR/filter-repo/commit-map" '*"$url"* ]]
  [[ "$stderr" == *"run this again"* ]]
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
  [[ "$stderr" == *"run this again"* ]]
}

@test "cross tier: a record with no map file is refused, naming the rebuild" {
  cx_tier_setup single
  tier_record_with_only version
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"map"* ]]
  assert_rebuild_named "$TIER"
  [[ "$stderr" == *"run this again"* ]]
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

@test "cross tier: the printed rebuild commands replace a damaged record, and the crossing then completes" {
  cx_tier_setup single
  tier_record_with_only map
  run --separate-stderr "$CROSS" "$TIER"
  refused
  # The mirror the rewrite ran in, with filter-repo's commit-map in its git dir.
  mirror="$TMP_REPO/mirror.git"
  git clone -q --mirror "$BARE_TIER" "$mirror"
  mkdir "$mirror/filter-repo"
  rewrite_write_commit_map "$mirror/filter-repo/commit-map" "$RW_P $RW_P" "$RW_O1 $RW_N1" "$RW_O2 $RW_N2"
  # Run as a person would: the indented lines, MIRROR set, from elsewhere.
  printf '%s\n' "$stderr" | grep '^  ' > "$TMP_REPO/rebuild.sh"
  [ "$(wc -l < "$TMP_REPO/rebuild.sh")" -eq 2 ]
  run bash -c "cd / && MIRROR=$(printf '%q' "$mirror") && . $(printf '%q' "$TMP_REPO/rebuild.sh")"
  [ "$status" -eq 0 ]
  [ "$(git --git-dir="$BARE_TIER" show refs/heads/gitlore/rewrites:map)" = "$RW_O1 $RW_N1
$RW_O2 $RW_N2" ]
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N2" ]
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

# --- refusals that diagnose, and what to do about each ---

@test "cross tier: a mapped commit this clone lacks names the rebuild of the record" {
  cx_tier_setup single
  cx_record_commit "$BARE_TIER" "$RW_O1 $RW_N1
$RW_O2 $(printf '%040d' 7)"
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"a commit this clone does not have"* ]]
  assert_rebuild_named "$TIER"
}

@test "cross tier: trees that differ outside gitlinks name the rebuild of the record" {
  cx_tier_setup single
  CX_Z=$(cx_commit "$BARE_TIER" "$(cx_tree "$BARE_TIER" "$RW_N2^{tree}" "$RW_P" rw-extra.md extra)" "$RW_N1" rewritten "old two")
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$CX_Z"
  cx_record_commit "$BARE_TIER" "$RW_O1 $RW_N1
$RW_O2 $CX_Z"
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"trees differ outside gitlinks"* ]]
  assert_rebuild_named "$TIER"
}

@test "cross memory: a gitlink the child's record maps elsewhere names the rebuild of the record" {
  cx_tier_setup single
  cx_memory_setup wrong
  cx_fixture_cross_tier "$RW_N2"
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$stderr" == *"in the record of"* ]]
  assert_rebuild_named "$TIER"
  assert_rebuild_named memory
}

@test "cross tier: a dropped commit prints the move to the remote's tip, which completes the crossing" {
  cx_tier_setup single
  # A second rewrite dropped N2; the remote's live is back on N1.
  cx_record_commit "$BARE_TIER" "$(cx_record_map "$BARE_TIER")
$RW_N2 $CX_ZEROS" append
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$RW_N1"
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"dropped"* ]]
  [[ "$stderr" == *"no local work"* ]]
  [[ "$stderr" == *"log --oneline"* ]]
  move=$(printf '%s\n' "$stderr" | grep '^  git .*update-ref')
  [ -n "$move" ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_O2" ]
  run bash -c "$move"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N1" ]
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_N1" ]
}

@test "cross tier: a dropped HEAD prints a detach to the remote's tip" {
  cx_tier_setup single
  cx_record_commit "$BARE_TIER" "$(cx_record_map "$BARE_TIER")
$RW_N2 $CX_ZEROS" append
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$RW_N1"
  cx_position "$TIER" "$RW_O2" "$RW_O1"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"HEAD of"* ]]
  [[ "$stderr" == *"checkout --detach refs/remotes/origin/live"* ]]
}

@test "cross tier: a commit neither on the remote's history nor recorded names the inspection and who decides" {
  cx_tier_setup single
  rewrite_position_clone "$TIER" fresh
  empty=$(git -C "$TIER" mktree </dev/null)
  unrelated=$(git -C "$TIER" -c user.email=t@t -c user.name=t commit-tree "$empty" -m unrelated)
  cx_position "$TIER" "$unrelated" "$unrelated"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"neither on the remote's history"* ]]
  [[ "$stderr" == *"log --oneline --graph $unrelated refs/remotes/origin/live"* ]]
  [[ "$stderr" == *"A person must decide"* ]]
}

# --- one fetch per child ---

# A git on PATH that logs the directory of every `git -C <dir> fetch`.
make_fetch_log_git() {
  local real
  real=$(command -v git)
  mkdir -p "$TMP_REPO/stub"
  cat > "$TMP_REPO/stub/git" <<STUB
#!/bin/sh
if [ "\$1" = -C ] && [ "\$3" = fetch ]; then printf '%s\n' "\$2" >> "$TMP_REPO/fetch.log"; fi
exec "$real" "\$@"
STUB
  chmod 755 "$TMP_REPO/stub/git"
}

@test "cross memory: a child's record is fetched once for HEAD, live, main and the child scan" {
  cx_tier_setup single
  cx_memory_setup mapped
  cx_fixture_cross_tier "$RW_N2"
  # HEAD, live and main all sit on the old commit, which pins the tier.
  cx_position memory "$CX_M2" "$CX_M2" "$CX_M2"
  make_fetch_log_git
  PATH="$TMP_REPO/stub:$PATH" run --separate-stderr "$CROSS" memory
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse HEAD)" = "$CX_M2N" ]
  [ "$(git -C memory rev-parse main)" = "$CX_M2N" ]
  # The stub saw the store's own fetch, so a count of zero cannot be a blind stub.
  [ "$(grep -cx 'memory' "$TMP_REPO/fetch.log")" -eq 1 ]
  [ "$(grep -cx 'memory/ddaanet' "$TMP_REPO/fetch.log")" -eq 1 ]
}
