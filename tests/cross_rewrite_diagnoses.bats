#!/usr/bin/env bats
# scripts/cross-rewrite.sh (D62): the refusals that diagnose rather than point
# at a missing step. A dropped commit, a commit on unrelated history, a mapped
# commit not yet published, trees or gitlinks that disagree with the record:
# each names what to run or who decides. Also that a child store's record is
# fetched once per run. Fixtures: helpers/rewrite-fixtures.bash and
# helpers/cross-fixtures.bash.
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

# --- refusals that diagnose, and what to do about each ---

@test "cross tier: a mapped commit the remote has not published yet says to run it again after the force-push, not to rebuild" {
  cx_tier_setup single
  absent=$(printf '%040d' 7)
  cx_record_commit "$BARE_TIER" "$RW_O1 $RW_N1
$RW_O2 $absent"
  # A remote with no main: the refusal must print nothing that needs one.
  git --git-dir="$BARE_TIER" update-ref -d refs/heads/main
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"a commit this clone does not have"* ]]
  [[ "$stderr" == *"force-push"* ]]
  [[ "$stderr" == *"run this again"* ]]
  # The tier's remote has no main: a printed fetch of main would fail whole.
  [[ "$stderr" != *"fetch origin"* ]]
  [[ "$stderr" != *"cat-file"* ]]
  [[ "$stderr" != *"--rebuild"* ]]
  [[ "$stderr" != *"--delete"* ]]
}

@test "cross tier: running again after the force-push lands completes a crossing the remote's missing main refused" {
  cx_tier_setup single
  # The remote's live is behind and it has no main: N2 has not been published.
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$RW_N1"
  git --git-dir="$BARE_TIER" update-ref -d refs/heads/main
  run git --git-dir="$BARE_TIER" rev-parse -q --verify refs/heads/main
  [ "$status" -ne 0 ]
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"run this again"* ]]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_O2" ]
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$RW_N2"
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N2" ]
}

@test "cross tier: a mapped commit that only the remote's main holds is fetched and the crossing completes" {
  cx_tier_setup single
  # The remote's live is behind: N2 is published on main only.
  git --git-dir="$BARE_TIER" update-ref refs/heads/main "$RW_N2"
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$RW_N1"
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  # Premise: the clone does not hold N2 until the script fetches main.
  run git -C "$TIER" cat-file -e "$RW_N2^{commit}"
  [ "$status" -ne 0 ]
  run --separate-stderr "$CROSS" "$TIER"
  [ "$status" -eq 0 ]
  [ "$(git -C "$TIER" rev-parse live)" = "$RW_N2" ]
  [ "$(git -C "$TIER" rev-parse HEAD)" = "$RW_N1" ]
}

@test "cross tier: trees that differ outside gitlinks name the inspection and who decides" {
  cx_tier_setup single
  CX_Z=$(cx_commit "$BARE_TIER" "$(cx_tree "$BARE_TIER" "$RW_N2^{tree}" "$RW_P" rw-extra.md extra)" "$RW_N1" rewritten "old two")
  git --git-dir="$BARE_TIER" update-ref refs/heads/live "$CX_Z"
  cx_record_commit "$BARE_TIER" "$RW_O1 $RW_N1
$RW_O2 $CX_Z"
  cx_position "$TIER" "$RW_O1" "$RW_O2"
  run --separate-stderr "$CROSS" "$TIER"
  refused
  [[ "$stderr" == *"trees differ outside gitlinks"* ]]
  [[ "$stderr" == *"git -C \"$TIER\" diff --stat $RW_O2 $CX_Z"* ]]
  [[ "$stderr" == *"A person must decide"* ]]
  [[ "$stderr" != *"--rebuild"* ]]
  [[ "$stderr" != *"--delete"* ]]
}

@test "cross memory: a gitlink the child's record maps elsewhere names the inspection and who decides" {
  cx_tier_setup single
  cx_memory_setup wrong
  cx_fixture_cross_tier "$RW_N2"
  run --separate-stderr "$CROSS" memory
  refused
  [[ "$stderr" == *"in the record of"* ]]
  [[ "$stderr" == *"git -C \"memory\" diff-tree -r --no-renames $CX_M2 $CX_M2N"* ]]
  [[ "$stderr" == *"A person must decide"* ]]
  [[ "$stderr" != *"--rebuild"* ]]
  [[ "$stderr" != *"--delete"* ]]
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
