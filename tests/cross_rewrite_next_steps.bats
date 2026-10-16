#!/usr/bin/env bats
# scripts/cross-rewrite.sh (D62): a refusal the user must act on names the
# command or action that resolves it, and a child store's record is fetched
# once per run however many refs and gitlinks consult it. Fixtures:
# helpers/rewrite-fixtures.bash and helpers/cross-fixtures.bash.
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

# --- the next step ---

@test "cross: a store that is not checked out is refused, naming the checkout command" {
  run --separate-stderr "$CROSS" memory/nowhere
  refused
  [[ "$stderr" == *'git submodule update --init -- "memory/nowhere"'* ]]
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

@test "cross tier: a record with no version file is refused, naming who repairs it" {
  cx_tier_setup single
  tier_record_with_only map
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"version"* ]]
  [[ "$stderr" == *"Ask the owner of the rewrite to repair gitlore/rewrites"* ]]
  [[ "$stderr" == *"run this again"* ]]
}

@test "cross tier: a record with no map file is refused, naming who repairs it" {
  cx_tier_setup single
  tier_record_with_only version
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"map"* ]]
  [[ "$stderr" == *"Ask the owner of the rewrite to repair gitlore/rewrites"* ]]
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

@test "cross tier: a remote that cannot be fetched from is refused, saying to run it again" {
  cx_tier_setup single
  git -C "$TIER" remote set-url origin "$TMP_REPO/no-such-remote.git"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"could not fetch"* ]]
  [[ "$stderr" == *"run this again"* ]]
}

@test "cross tier: a remote with no record is refused, saying who publishes it" {
  cx_tier_setup single
  git --git-dir="$BARE_TIER" update-ref -d refs/heads/gitlore/rewrites
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"no rewrite record"* ]]
  [[ "$stderr" == *"record-rewrite.sh"* ]]
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
