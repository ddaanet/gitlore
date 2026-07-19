#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

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
