#!/usr/bin/env bats
# Every script that reads git's English `couldn't find remote ref` as "the remote
# has no such branch" must run that fetch under the C locale, or a localized git
# translates the message, the match misses and the miss is reported as a failed
# fetch.
#
# The suite does not depend on installed translations. A `git` shim first on
# PATH logs, for each `fetch`, the values of LC_ALL, LANGUAGE and LANG it was
# called with, then execs the real git. The environment starts non-C
# (a non-C locale and LANGUAGE=fr), so an inherited C locale cannot satisfy an assertion.
#
# What is asserted: LC_ALL=C on the fetch. gettext ignores LANGUAGE when the
# locale is C, and LC_ALL outranks LANG, so LC_ALL=C alone guarantees English;
# LANGUAGE and LANG are logged for the failure message only.
#
# Every fixture lives in a temp directory (setup_tmp_repo); the checkout's own
# memory/ is never touched.
#
# shellcheck disable=SC2154,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/merge-memory
load helpers/cc-hook-session-start
load helpers/add-tier
load helpers/divergence-fixtures
load helpers/tier-divergence
load helpers/rewrite-fixtures
load helpers/cross-fixtures
load helpers/take-order
load helpers/unresolvable-pin

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  # Submodule adds from a local path need this (as in helpers/add-tier.bash).
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
  pick_non_c_locale
  export LC_ALL="$NON_C_LOCALE" LANGUAGE=fr LANG="$NON_C_LOCALE"
  FETCH_LOG="$BATS_TEST_TMPDIR/fetch.log"
  : > "$FETCH_LOG"
  install_git_shim
}
teardown() { teardown_tmp_repo; }

# fr_FR.UTF-8 where the machine has it. Elsewhere any installed non-C locale
# (a missing one makes every bash in the run warn on stderr), else fr_FR anyway.
pick_non_c_locale() {
  local cand have
  have=$(locale -a || true)
  NON_C_LOCALE=fr_FR.UTF-8
  for cand in fr_FR.UTF-8 fr_FR.utf8 en_US.UTF-8 en_US.utf8 C.UTF-8 C.utf8; do
    case "
$have
" in
      *"
$cand
"*) NON_C_LOCALE="$cand"; return 0 ;;
    esac
  done
}

# A `git` first on PATH that logs each fetch's locale variables, then execs the
# real git by absolute path (resolved before the shim is on PATH).
install_git_shim() {
  local real dir="$BATS_TEST_TMPDIR/shim"
  real=$(command -v git)
  mkdir -p "$dir"
  {
    printf '#!/bin/sh\nREAL_GIT=%q\nFETCH_LOG=%q\n' "$real" "$FETCH_LOG"
    cat <<'BODY'
sub="" skip=0
for a in "$@"; do
  if [ "$skip" -eq 1 ]; then skip=0; continue; fi
  case "$a" in
    -C|-c|--git-dir|--work-tree|--namespace) skip=1 ;;
    -*) ;;
    *) sub="$a"; break ;;
  esac
done
if [ "$sub" = fetch ]; then
  printf 'LC_ALL=%s LANGUAGE=%s LANG=%s :: %s\n' \
    "${LC_ALL-<unset>}" "${LANGUAGE-<unset>}" "${LANG-<unset>}" "$*" >> "$FETCH_LOG"
fi
exec "$REAL_GIT" "$@"
BODY
  } > "$dir/git"
  chmod +x "$dir/git"
  PATH="$dir:$PATH"
  export PATH
}

# Succeed when at least one logged fetch contains literal $1 and every such
# fetch ran with LC_ALL=C. Args: $1 = a fragment of the fetch's arguments.
assert_fetch_in_c() {
  local line n=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      *"$1"*)
        n=$((n + 1))
        case "$line" in
          "LC_ALL=C "*) ;;
          *) printf 'fetch not run under LC_ALL=C: %s\n' "$line" >&2; return 1 ;;
        esac ;;
    esac
  done < "$FETCH_LOG"
  if [ "$n" -eq 0 ]; then
    printf 'no fetch matching [%s] was logged; log:\n%s\n' "$1" "$(cat "$FETCH_LOG")" >&2
    return 1
  fi
}

# --- resolve-merge-stores.sh, through /gitlore:merge ---

@test "locale: the merge's fetch of a memory remote with no live runs under LC_ALL=C" {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  [ -z "$(git -C memory ls-remote origin live)" ]
  run --separate-stderr bash "$CMD"
  [ "$status" -eq 0 ]
  assert_fetch_in_c "memory fetch -q --no-recurse-submodules origin live"
}

# --- session-memory.sh and session-tiers.sh, through SessionStart ---

@test "locale: SessionStart's fetch of a memory remote with no live runs under LC_ALL=C" {
  make_parent_with_memory
  run git -C memory ls-remote --exit-code origin refs/heads/live
  [ "$status" -ne 0 ]
  enable_gitlore
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_fetch_in_c "memory fetch -q origin live"
}

@test "locale: SessionStart's bounded fetch of a memory remote with no live runs under LC_ALL=C" {
  # GITLORE_FETCH_TIMEOUT routes the fetch through gitlore_fetch_bounded's
  # background job under `set -m`, which inherits the caller's environment.
  make_parent_with_memory
  run git -C memory ls-remote --exit-code origin refs/heads/live
  [ "$status" -ne 0 ]
  enable_gitlore
  GITLORE_FETCH_TIMEOUT=30 GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_fetch_in_c "memory fetch -q origin live"
}

@test "locale: SessionStart's fetch of a tier remote with no live runs under LC_ALL=C" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  commit_memory_state "memory: activate the tier"
  git -C memory push -q . HEAD:refs/heads/live
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" branch -D live >/dev/null
  run git -C memory/ddaanet ls-remote --exit-code origin refs/heads/live
  [ "$status" -ne 0 ]
  enable_gitlore
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_fetch_in_c "memory/ddaanet fetch origin live"
}

@test "locale: SessionStart's bounded fetch of a tier remote with no live runs under LC_ALL=C" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  commit_memory_state "memory: activate the tier"
  git -C memory push -q . HEAD:refs/heads/live
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" branch -D live >/dev/null
  enable_gitlore
  GITLORE_FETCH_TIMEOUT=30 GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_fetch_in_c "memory/ddaanet fetch origin live"
}

# --- rewrite-guard.sh, through the pre-push hook ---

@test "locale: the rewrite guard's fetch of an absent record runs under LC_ALL=C" {
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  rewrite_remote_history memory "$TMP_REPO/.bare-memory.git"
  rewrite_position_clone memory old
  git --git-dir="$TMP_REPO/.bare-memory.git" update-ref -d refs/heads/gitlore/rewrites
  [ -z "$(git -C memory ls-remote origin refs/heads/gitlore/rewrites)" ]
  run --separate-stderr bash "$PRE_PUSH"
  assert_fetch_in_c "refs/heads/gitlore/rewrites:refs/gitlore/rewrites"
}

# --- record-rewrite.sh ---

@test "locale: record-rewrite's fetch of an absent record runs under LC_ALL=C" {
  make_parent_with_memory
  ZEROS=0000000000000000000000000000000000000000
  rewrite_remote_history memory "$TMP_REPO/.bare-memory.git"
  rewrite_position_clone memory fresh
  git --git-dir="$TMP_REPO/.bare-memory.git" update-ref -d refs/heads/gitlore/rewrites
  rewrite_write_commit_map "$TMP_REPO/commit-map" "$RW_P $RW_P" "$RW_N1 $ZEROS"
  run --separate-stderr bash "$PLUGIN_ROOT/scripts/record-rewrite.sh" memory "$TMP_REPO/commit-map"
  assert_fetch_in_c "refs/heads/gitlore/rewrites:refs/gitlore/rewrites"
}

# --- add-tier.sh ---

@test "locale: add-tier's fetch of a tier remote with no live runs under LC_ALL=C" {
  make_parent_with_memory
  bare=$(make_tier_remote ddaanet nolive)
  write_intent "mode=mount" "name=ddaanet" "url=$bare"
  run bash "$ADD_TIER" < "$INTENT"
  [ "$status" -eq 0 ]
  assert_fetch_in_c "fetch origin live:live"
}

# --- cross-rewrite.sh ---

@test "locale: cross-rewrite's fetch of an absent record runs under LC_ALL=C" {
  cx_tier_setup single
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" update-ref -d refs/heads/gitlore/rewrites
  run --separate-stderr "$PLUGIN_ROOT/scripts/cross-rewrite.sh" memory/ddaanet
  assert_fetch_in_c "refs/heads/gitlore/rewrites:refs/gitlore/rewrites"
}

@test "locale: cross-rewrite's fetch of a remote's absent main runs under LC_ALL=C" {
  cx_tier_setup single
  absent=$(printf '%040d' 7)
  cx_record_commit "$TMP_REPO/.bare-ddaanet.git" "$RW_O1 $RW_N1
$RW_O2 $absent"
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" update-ref -d refs/heads/main
  cx_position memory/ddaanet "$RW_O1" "$RW_O2"
  run --separate-stderr "$PLUGIN_ROOT/scripts/cross-rewrite.sh" memory/ddaanet
  assert_fetch_in_c "refs/heads/main:refs/remotes/origin/main"
}

@test "locale: cross-rewrite's fetch of a child tier's absent record runs under LC_ALL=C" {
  # The memory store's crossing reads each changed gitlink against its child's
  # own record (load_child_record); here the tier's origin has none.
  cx_tier_setup single
  cx_memory_setup mapped
  cx_fixture_cross_tier "$RW_N2"
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" update-ref -d refs/heads/gitlore/rewrites
  run --separate-stderr "$PLUGIN_ROOT/scripts/cross-rewrite.sh" memory
  assert_fetch_in_c "memory/ddaanet fetch -q --no-write-fetch-head origin +refs/heads/gitlore/rewrites:refs/gitlore/rewrites"
}

# --- resolve-unresolvable.sh, through /gitlore:resolve ---

@test "locale: resolve's fetch of a tier remote with no live, over a pin nobody holds, runs under LC_ALL=C" {
  tier_gitlink_nobody_holds
  git -C memory/ddaanet push -q origin --delete live
  [ -z "$(git -C memory/ddaanet ls-remote origin refs/heads/live)" ]
  CLAUDECODE='' run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  assert_fetch_in_c "memory/ddaanet fetch -q --no-recurse-submodules origin live"
}
