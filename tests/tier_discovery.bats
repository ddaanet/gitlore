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

@test "SessionStart leaves a tier pinned at its gitlink when the remote is ahead" {
  # The tier is checked out at the commit the memory tree records and NOTHING
  # advances it silently: root's index and the carrier are written by one commit
  # and stay consistent by construction. Taking an upstream commit is a merge,
  # which composition is no longer in a position to paper over.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  gitlink="$(git -C memory rev-parse HEAD:ddaanet)"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  remote_sha="$(push_tier_fact ddaanet)"
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$gitlink" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$remote_sha" ]
  # Still detached — `submodule update` checks the gitlink out, it does not
  # attach a branch — and the local `live` did not move either.
  run git -C memory/ddaanet symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  run git -C memory/ddaanet rev-parse -q --verify live
  [ "$output" != "$remote_sha" ]
}

@test "SessionStart pins a tier that had outrun its gitlink" {
  # Removing the fetch and the checkout pins nothing on its own: a clone from
  # before the change already sits ahead of the gitlink, so the pass has to put
  # it back. `submodule update` therefore runs on every session, not only when
  # the tier was never checked out.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  gitlink="$(git -C memory rev-parse HEAD:ddaanet)"
  remote_sha="$(push_tier_fact ddaanet)"
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$gitlink" ]
}

@test "SessionStart names a tier whose remote is ahead, and how to take it" {
  # The fetch stays, read-only: it moves no local ref, and it is the only thing
  # that can tell the user upstream facts are waiting. A pinned tier that says
  # nothing is indistinguishable from one with nothing to take.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  push_tier_fact ddaanet >/dev/null
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("tier .ddaanet. has upstream facts waiting")'
  echo "$output" | jq -e '.systemMessage | test("/gitlore:merge")'
  echo "$output" | jq -e '.systemMessage | test("/gitlore:push")'
  echo "$output" | jq -e '.systemMessage | test("could not fetch") | not'
}

@test "SessionStart says nothing about a tier whose remote it already contains" {
  # The other direction of the same comparison: local commits not yet published
  # are the lockstep's business, not an upstream arrival. Reporting them as
  # "waiting" would send the user to a merge that has nothing to merge.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  git -C memory/ddaanet commit -q --allow-empty -m "local, unpublished"
  git -C memory add ddaanet
  GITLORE_MEMORY_COMMIT=1 git -C memory commit -q -m "record the tier commit"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("upstream facts waiting") | not'
  echo "$output" | jq -e '.systemMessage | test("has diverged") | not'
}

@test "SessionStart reports a tier that has diverged from its remote" {
  # Neither side contains the other. The read-only fetch cannot surface this the
  # way the old refspec fetch did — nothing is refused, because nothing is
  # attempted — so the comparison has to say it.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  git -C memory/ddaanet commit -q --allow-empty -m "local, unpublished"
  git -C memory add ddaanet
  GITLORE_MEMORY_COMMIT=1 git -C memory commit -q -m "record the tier commit"
  push_tier_fact ddaanet >/dev/null
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("tier .ddaanet. has diverged")'
  echo "$output" | jq -e '.systemMessage | test("/gitlore:merge")'
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

@test "SessionStart composes the memory store's indexes" {
  # A pinned tier takes nothing from its remote at SessionStart, so the pass
  # that still has to run here is composition itself: a root-authored tier line
  # written in a session that ended without one reaches the carrier at the start
  # of the next.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "ddaanet/authored.md" "written in the root index"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  grep -qF -- '- [authored](authored.md) — written in the root index' memory/ddaanet/MEMORY.md
}

@test "SessionStart survives a store that fails composition" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ghost
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ghost"* ]]
}

@test "SessionStart reports a dangling pointer without touching the index" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  seed_root_bullet "gone.md" "stale line"
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone.md"* ]]
  grep -qF -- '- [gone](gone.md) — stale line' memory/MEMORY.md
  [ ! -e memory/gone.md ]
}


# --- gitlore_active_tier_scopes: helper shared by SessionStart and the triage nudge ---

@test "gitlore_active_tier_scopes emits path and description for an active tier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  run gitlore_active_tier_scopes memory
  [ "$status" -eq 0 ]
  [ "$output" = "memory/ddaanet/ — org-wide facts for ddaanet projects" ]
}

@test "gitlore_active_tier_scopes skips a mounted but unlisted (dormant) tier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  run gitlore_active_tier_scopes memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "gitlore_active_tier_scopes skips a listed but unmounted tier" {
  make_parent_with_memory
  set_tier_manifest ddaanet
  run gitlore_active_tier_scopes memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "gitlore_active_tier_scopes emits one line per active tier, in manifest order" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  make_tier_in_memory otherteam
  set_tier_manifest otherteam ddaanet
  run gitlore_active_tier_scopes memory
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "memory/otherteam/ — org-wide facts for otherteam projects" ]
  [ "${lines[1]}" = "memory/ddaanet/ — org-wide facts for ddaanet projects" ]
}

# Regression: enumeration must not split on whitespace or lose a spaced path.
@test "gitlore_active_tier_scopes is whitespace-safe on a tier path containing a space" {
  make_parent_with_memory
  make_tier_in_memory "spaced tier"
  set_tier_manifest "spaced tier"
  run gitlore_active_tier_scopes memory
  [ "$status" -eq 0 ]
  [ "$output" = "memory/spaced tier/ — org-wide facts for spaced tier projects" ]
}

@test "routing guidance points the agent at the ROOT index, prefixed" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # The sentence is generic — the tiers themselves are enumerated below it.
  [[ "$output" == *'<tier>/<file>.md'* ]]
  [[ "$output" == *"ROOT"* ]]
  [[ "$output" != *"that tier's MEMORY.md"* ]]
}
