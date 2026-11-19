#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/gh-mock
load helpers/tier-fixtures
load helpers/tier-divergence

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
}
teardown() { teardown_tmp_repo; }

@test "resolve: errors when no memory submodule registered" {
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"not installed"* ]] || [[ "$output$stderr" == *"/gitlore:install"* ]]
}

@test "resolve: derives plugin root from \$0 when CLAUDE_PLUGIN_ROOT is unset" {
  # Dogfood-driven: continuation commands run from sub-agents whose shell may
  # not inherit CLAUDE_PLUGIN_ROOT. The script must derive its root from $0.
  unset CLAUDE_PLUGIN_ROOT
  run --separate-stderr bash "$RESOLVE"
  # The positive is what proves the run got past root derivation: with the
  # variable unset the script still reaches its own logic and says gitlore's
  # own thing. On its own the refutation below cannot tell that apart from a
  # script that died earlier for some other reason.
  [[ "$output$stderr" == *"not installed"* ]] || [[ "$output$stderr" == *"/gitlore:install"* ]]
  [[ "$output$stderr" != *"$GITLORE_T_PLUGIN_ROOT_UNSET"* ]]
}

# The default run on a memory store with no usable remote: the local gate still
# runs, the store is reported as staying local with no command named, and
# nothing is created. $1 is the shell snippet that leaves memory in that state.
assert_memory_stays_local() {
  local log="$TMP_REPO/gh-calls.log" head
  printf 'local only\n' > memory/local-only.md
  git -C memory add local-only.md
  git -C memory commit -qm "a root-only fact"
  head=$(git -C memory rev-parse HEAD)
  [ "$(git -C memory rev-parse live)" != "$head" ]
  GH_MOCK_LOG="$log" run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [ "$(git -C memory rev-parse live)" = "$head" ]
  [[ "$stderr" == *"stays local"* ]]
  [[ "$stderr" != *"/gitlore:resolve"* ]]
  [[ "$stderr" != *"Run "* ]]
  [[ "$(printf '%s\n' "$stderr" | grep -F 'stays local')" != *"/gitlore:"* ]]
  [[ "$stderr" != *"healthy"* ]]
  [[ "$stderr" != *"unreachable"* ]]
  [ ! -e "$log" ]
}

@test "resolve: memory with no origin stays local: local gate runs, nothing is created" {
  make_parent_with_memory
  git -C memory remote remove origin
  assert_memory_stays_local
  [ -z "$(git -C memory config --get remote.origin.url || true)" ]
}

@test "resolve: memory with a placeholder origin stays local the same way" {
  make_parent_with_memory
  git -C memory remote set-url origin "$TMP_REPO/.git/gitlore-placeholder"
  assert_memory_stays_local
  [ "$(git -C memory config --get remote.origin.url)" = "$TMP_REPO/.git/gitlore-placeholder" ]
}

@test "resolve: a mounted tier with no remote is skipped without a line of its own" {
  # Pin: the tier loop already skips a tier with no remote silently.
  make_parent_with_memory
  git -C memory remote remove origin
  git -C memory remote add origin "$GH_MOCK_REMOTE_URL"
  git -C memory push -q origin live
  mount_tier_at_live ddaanet
  git -C memory/ddaanet remote remove origin
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  # Positive over the same fixture: memory, which has a remote, is still judged.
  [[ "$stderr" == *"memory is ahead of its remote"* ]]
  [[ "$stderr" != *"stays local"* ]]
  [[ "$stderr" != *"ddaanet"* ]]
}

@test "resolve: reports unreachable remote without calling gh repo create" {
  make_parent_with_memory
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin /does/not/exist.git
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"unreachable"* ]] || [[ "$output$stderr" == *"network"* ]] || [[ "$output$stderr" == *"auth"* ]]
  run grep -q 'repo create' "$log"
  [ "$status" -ne 0 ]
}

@test "resolve: a remote with no live branch gets none, and memory is reported ahead" {
  make_parent_with_memory
  bare="$TMP_REPO/.recover-remote.git"
  git init -q --bare "$bare"
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin "$bare"
  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 0 ]
  # `git rev-parse live` on a ref-less repository prints its argument, so the
  # remote is read through ls-remote, which lists nothing for it.
  [ -z "$(git ls-remote "$bare")" ]
  [[ "$stderr" == *"gitlore: memory is ahead of its remote. Run /gitlore:push to publish it."* ]]
  # A first publish has no remote `live` to fetch, and git's complaint about
  # that is not the user's to read. `case`, not `[[ ]]`: non-final here.
  case "$output$stderr" in *"couldn't find remote ref"*) false ;; esac
}

@test "resolve: a tier gate that refuses ends the run before memory's gate, and nothing reaches memory's remote" {
  # Memory's remote has no `live` yet, and a mounted tier's own gate is about to
  # refuse (its local `live` diverged from its remote's). The tiers are gated
  # before memory (D17: memory's commit records the tier's gitlink), so the
  # tier's yield is what ends the run, and the default run publishes nothing
  # (D86): memory's remote still has no `live` afterwards.
  make_parent_with_memory
  bare="$TMP_REPO/.recover-remote.git"
  git init -q --bare "$bare"
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin "$bare"
  mount_tier_at_live ddaanet
  diverge_tier_from_remote ddaanet

  # Premise: memory's remote truly has no `live` yet, and the tier's remote
  # truly does not carry the commit memory's gitlink now names.
  [ -z "$(git -C memory ls-remote origin live)" ]
  gitlink=$(git -C memory rev-parse HEAD:ddaanet)
  run git --git-dir="$TMP_REPO/.bare-ddaanet.git" cat-file -e "$gitlink"
  [ "$status" -ne 0 ]

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"flavor=head-vs-remote"* ]]
  [ -z "$(git -C memory ls-remote origin live)" ]
}

@test "resolve: the merge state file parses when the store path holds a quote" {
  # The state file records the store path, and its first reader is `jq -r
  # .flavor` in the stale-merge guard. A path containing a `"` or a `\` written
  # by string interpolation yields invalid JSON, and the guard's failure surfaces
  # as a blocked commit with a jq syntax error rather than as a merge.
  store="$TMP_REPO/we\"ird \\ store"
  mkdir -p "$store"
  git init -q "$store"
  git -C "$store" config user.email "test@example.com"
  git -C "$store" config user.name "Test"
  echo seed > "$store/SEED.md"
  git -C "$store" add SEED.md
  git -C "$store" commit -q -m seed
  sha=$(git -C "$store" rev-parse HEAD)

  gitlore_write_merge_state "$store" head-vs-live "$sha" "$sha" live continue-after-merge

  statefile=$(gitlore_merge_state_file "$store")
  [ -f "$statefile" ]
  run jq -r .flavor "$statefile"
  [ "$status" -eq 0 ]
  [ "$output" = "head-vs-live" ]
  [ "$(jq -r .store "$statefile")" = "$store" ]
  [ "$(jq -r '.changed_files | type' "$statefile")" = "array" ]
}

@test "resolve: memory behind its remote reports nothing to publish instead of a failed merge" {
  make_parent_with_memory
  git -C memory push -q origin live
  # Advance the remote from a throwaway clone, behind local memory's back: the
  # local store is then strictly BEHIND, with nothing of its own to publish.
  # check_store_gates must classify this by ancestry, not by git's refusal
  # wording alone, or it prepares a merge against a store that is clean.
  local other
  other="$(mktemp -d "$TMP_REPO/other.XXXXXX")"
  git clone -q "$TMP_REPO/.bare-memory.git" "$other"
  (
    cd "$other" || exit 1
    git checkout -q live
    printf 'remote-only\n' > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "remote-only"
    git push -q origin live
  )
  rm -rf "$other"

  run --separate-stderr bash "$RESOLVE"
  [ "$status" -eq 0 ]
  msg="$output$stderr"
  [[ "$msg" == *"/gitlore:merge"* ]]
  [[ "$msg" != *"memory merge prepared"* ]]
  [[ "$msg" != *"could not prepare"* ]]
}

@test "resolve: no-op when healthy" {
  make_parent_with_memory
  bare="$TMP_REPO/.healthy-remote.git"
  git init -q --bare "$bare"
  git -C memory remote remove origin 2>/dev/null || true
  git -C memory remote add origin "$bare"
  git -C memory push -q origin live
  log="$TMP_REPO/gh-calls.log"
  GH_MOCK_LOG="$log" run bash "$RESOLVE"
  [ "$status" -eq 0 ]
  run grep -q 'repo create' "$log"
  [ "$status" -ne 0 ]
}
