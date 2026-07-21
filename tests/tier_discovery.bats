#!/usr/bin/env bats
# Each @test is its own subshell; the per-test `export GITLORE_LAUNCHED` is
# consumed within that same test, so SC2030/SC2031 are false positives here.
# shellcheck disable=SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() { teardown_tmp_repo; }

# --- Characterization: how git actually mounts a submodule inside a submodule ---

@test "make_tier_in_memory places the nested gitdir under the memory module store" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  [ -e memory/ddaanet/.git ]
  [ -d .git/modules/gitlore-memory/modules/ddaanet ]
  grep -q '^description:' memory/ddaanet/MEMORY.md
  # The tier is registered in the memory store's OWN .gitmodules, not the parent's.
  [ "$(git config --file memory/.gitmodules --get submodule.ddaanet.path)" = "ddaanet" ]
  run git config --file .gitmodules --get submodule.ddaanet.path
  [ "$status" -ne 0 ]
}

@test "a freshly mounted tier has no local live ref; fetch live:live creates it" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  run git -C memory/ddaanet show-ref --verify --quiet refs/heads/live
  [ "$status" -ne 0 ]
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet show-ref --verify --quiet refs/heads/live
}

@test "fetch live:live is fast-forward-only (rejects a divergent local live)" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  git -C memory/ddaanet fetch -q origin "live:live"
  # Diverge locally.
  git -C memory/ddaanet checkout -q -B live
  echo "local only" >> memory/ddaanet/MEMORY.md
  git -C memory/ddaanet commit -aqm "local divergent"
  git -C memory/ddaanet checkout -q --detach live
  push_tier_fact ddaanet >/dev/null
  run git -C memory/ddaanet fetch origin "live:live"
  [ "$status" -ne 0 ]
  echo "$output" | grep -q 'non-fast-forward'
}

@test "a D11 linked memory worktree gets its own independent tier clone" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  memsha="$(git -C memory rev-parse HEAD)"
  wt="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-wt.XXXXXX")"
  rm -rf "$wt"
  git -C .git/modules/gitlore-memory worktree add --detach "$wt" "$memsha" >/dev/null 2>&1
  git -C "$wt" -c protocol.file.allow=always submodule update --init -- ddaanet >/dev/null 2>&1
  [ -e "$wt/ddaanet/.git" ]
  # Separate gitdir from the primary checkout's tier — not a shared store.
  primary="$(git -C memory/ddaanet rev-parse --absolute-git-dir)"
  linked="$(git -C "$wt/ddaanet" rev-parse --absolute-git-dir)"
  [ "$primary" != "$linked" ]
  case "$linked" in
    */modules/gitlore-memory/worktrees/*/modules/ddaanet) ;;
    *) echo "unexpected linked tier gitdir: $linked"; return 1 ;;
  esac
  rm -rf "$wt"
  git -C .git/modules/gitlore-memory worktree prune
}

# --- gitlore_tier_paths: discovery by enclosure ---

@test "gitlore_tier_paths lists tiers from the memory store's own .gitmodules" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  run gitlore_tier_paths memory
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet" ]
}

# Regression: enumeration must not split on whitespace. A field split of `git
# config --get-regexp` output loses a path containing spaces, and for a submodule
# NAMED with a space it emits a fragment of the KEY (`b.path`) as if it were a
# path. Both the name and the path here contain spaces, so either fault fails.
@test "gitlore_tier_paths survives whitespace in the submodule name and path" {
  make_parent_with_memory
  git config --file memory/.gitmodules "submodule.org tier.path" "dir with spaces/tier"
  git config --file memory/.gitmodules "submodule.org tier.url" "https://example.invalid/x.git"
  run gitlore_tier_paths memory
  [ "$status" -eq 0 ]
  [ "$output" = "dir with spaces/tier" ]
}

@test "gitlore_tier_paths is empty when the memory store has no tiers" {
  make_parent_with_memory
  run gitlore_tier_paths memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- SessionStart propagation-in ---

@test "SessionStart ff's a mounted tier and leaves it detached at live (propagation)" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  remote_sha="$(push_tier_fact ddaanet)"
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse live)" = "$remote_sha" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  run git -C memory/ddaanet symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
}

@test "SessionStart reports a diverged tier with git's own reason" {
  # Regression: the tier fetch ran with `-q`, and a quiet fetch prints NOTHING
  # on a non-fast-forward — it only exits 1. The divergence arm could never
  # match, so a tier that had stopped propagating was reported as merely
  # "stale", with "git said:" trailing into empty space. Asserted through the
  # hook, not against a hand-rolled `git fetch`: the invocation is the bug.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q -B live
  echo "local only" >> memory/ddaanet/MEMORY.md
  git -C memory/ddaanet commit -aqm "local divergent"
  git -C memory/ddaanet checkout -q --detach live
  push_tier_fact ddaanet >/dev/null
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("has diverged")'
  echo "$output" | jq -e '.systemMessage | test("could not fetch") | not'
}

@test "SessionStart materializes a tier that was never checked out (propagation)" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  git -C memory submodule deinit -f -- ddaanet >/dev/null 2>&1
  [ ! -e memory/ddaanet/.git ]
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  export GIT_ALLOW_PROTOCOL=file
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ -e memory/ddaanet/.git ]
}

@test "SessionStart survives a memory store with no tiers at all (propagation)" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("memory ready")'
}

# --- gitlore_active_tiers: the activation manifest ---

@test "gitlore_active_tiers reads the manifest in order, skipping blanks" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  printf '  ddaanet  \n\n' > memory/.gitlore-tiers
  run gitlore_active_tiers memory
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet" ]
}

@test "gitlore_active_tiers is empty when no manifest exists" {
  make_parent_with_memory
  run gitlore_active_tiers memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# --- SessionStart routing guidance ---

@test "SessionStart advertises an active tier's description as routing guidance" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  printf 'ddaanet\n' > memory/.gitlore-tiers
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("memory/ddaanet")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("org-wide facts for ddaanet")'
}

@test "SessionStart does not advertise a mounted-but-unlisted (dormant) tier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  run -1 jq -e '.hookSpecificOutput.additionalContext | test("ddaanet")' <<< "$output"
}
