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
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

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
  [[ "$output" == *non-fast-forward* ]]
}

@test "a D11 linked memory worktree gets its own independent tier clone" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  memsha="$(git -C memory rev-parse HEAD)"
  WT="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-wt.XXXXXX")"
  rm -rf "$WT"
  git -C .git/modules/gitlore-memory worktree add --detach "$WT" "$memsha" >/dev/null
  git -C "$WT" -c protocol.file.allow=always submodule update --init -- ddaanet >/dev/null
  [ -e "$WT/ddaanet/.git" ]
  # Separate gitdir from the primary checkout's tier — not a shared store.
  primary="$(git -C memory/ddaanet rev-parse --absolute-git-dir)"
  linked="$(git -C "$WT/ddaanet" rev-parse --absolute-git-dir)"
  [ "$primary" != "$linked" ]
  case "$linked" in
    */modules/gitlore-memory/worktrees/*/modules/ddaanet) ;;
    *) echo "unexpected linked tier gitdir: $linked"; return 1 ;;
  esac
  rm -rf "$WT"
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

@test "SessionStart leaves a tier where it is when the remote is ahead" {
  # No module moves at SessionStart. The tier stays at the commit it is on, on
  # the branch it is on: the hook does not check the gitlink out and does not
  # detach, and nothing advances the tier silently. Taking an upstream commit is
  # a merge, which composition is no longer in a position to paper over.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  gitlink="$(git -C memory rev-parse HEAD:ddaanet)"
  branch="$(git -C memory/ddaanet symbolic-ref -q --short HEAD)"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  remote_sha="$(push_tier_fact ddaanet)"
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$gitlink" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$remote_sha" ]
  # Still on the mount's named branch: the hook does not detach it, and the
  # local `live` did not move either.
  [ "$(git -C memory/ddaanet symbolic-ref -q --short HEAD)" = "$branch" ]
  run git -C memory/ddaanet rev-parse -q --verify live
  [ "$output" != "$remote_sha" ]
}

@test "SessionStart does not put a tier that had outrun its gitlink back on it, reports it in sync with its remote, and refuses it naming the take" {
  # A tier ahead of the commit memory records holds lines the root index has
  # not taken, and the take is what composes them up and records it, so
  # SessionStart leaves the tier where the take needs it and reports the state
  # naming /gitlore:merge. The sync report compares HEAD and local `live` with
  # the remote's `live`, not with the pin: this tier is past the pin and equal
  # to its remote, so it is in sync. Fails under a hook that re-pins the tier,
  # or reads the tier ahead as no fault and reports nothing.
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
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$gitlink" ]
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; . == "gitlore: memory in sync; ddaanet in sync")'
  # The refusal, with both shas and the remedy, on both channels.
  tierline="tier 'ddaanet' is checked out at ${remote_sha:0:12}, ahead of the commit the memory store records at ${gitlink:0:12}"
  echo "$output" | jq -e --arg l "$tierline" '.systemMessage | split("\n\n") | any(.[]; contains("cannot be composed until these are fixed") and contains($l) and contains("Run /gitlore:merge"))'
  echo "$output" | jq -e --arg l "$tierline" '.hookSpecificOutput.additionalContext | contains($l)'
  # No paragraph reports upstream facts waiting: the remote holds nothing this
  # tier does not.
  echo "$output" | jq -e '.systemMessage | split("\n\n") | all(.[]; (contains("ddaanet") and contains("waiting")) | not)'
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
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; . == "gitlore: Run /gitlore:merge (memory in sync; ddaanet 1 behind)")'
  # Behind the remote is a take: no offer of /gitlore:push.
  echo "$output" | jq -e '.systemMessage | test("/gitlore:push") | not'
  echo "$output" | jq -e '.systemMessage | test("could not fetch") | not'
}

@test "SessionStart hints /gitlore:push for a tier that holds commits its remote lacks, and no upstream facts waiting" {
  # The other direction of the same comparison: local commits not yet published
  # are not an upstream arrival, so "waiting" would send the user to a merge
  # with nothing to merge. The tier is strictly ahead of its remote's `live`,
  # which is /gitlore:push's business and is said so.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  git -C memory/ddaanet commit -q --allow-empty -m "local, unpublished"
  git -C memory add ddaanet
  git -C memory commit -q -m "record the tier commit"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; . == "gitlore: Run /gitlore:push (memory 1 ahead; ddaanet 1 ahead)")'
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
  git -C memory commit -q -m "record the tier commit"
  push_tier_fact ddaanet >/dev/null
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # Diverged needs a publish: /gitlore:push, and no offer of /gitlore:merge.
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; . == "gitlore: Run /gitlore:push (memory 1 ahead; ddaanet diverged)")'
  echo "$output" | jq -e '.systemMessage | test("/gitlore:push")'
  echo "$output" | jq -e '.systemMessage | test("/gitlore:merge") | not'
  echo "$output" | jq -e '.systemMessage | test("could not fetch") | not'
}

@test "SessionStart materializes a tier that was never checked out (propagation)" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  git -C memory submodule deinit -f -- ddaanet >/dev/null
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
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; . == "gitlore: memory in sync")'
  echo "$output" | jq -e '.systemMessage | (contains("memory ready") or contains("detached at live")) | not'
}
