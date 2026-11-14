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
  # Only the session line names it
  jq -e '.hookSpecificOutput.additionalContext | split("\n\n") | (any(.[]; . == "gitlore: memory in sync; ddaanet in sync")) and (map(select(startswith("gitlore: memory in sync") | not)) | any(.[]; test("ddaanet")) | not)' <<< "$output"
}

@test "SessionStart does not compose: a root-authored tier line stays out of the carrier" {
  # A root-authored tier line written outside a session leaves a pending compose.
  # SessionStart reports position and writes no index; the carrier waits for a
  # batch or gitlore-compose.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "ddaanet/authored.md" "written in the root index"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  root_before=$(cat memory/MEMORY.md)
  carrier_before=$(cat memory/ddaanet/MEMORY.md)
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(cat memory/MEMORY.md)" = "$root_before" ]
  [ "$(cat memory/ddaanet/MEMORY.md)" = "$carrier_before" ]
  run grep -qF -- '- [authored](authored.md)' memory/ddaanet/MEMORY.md
  [ "$status" -ne 0 ]
  # The fixture holds a real pending compose: composing it is what writes the
  # line, so the untouched carrier above is the hook's doing.
  gitlore_compose memory
  grep -qF -- '- [authored](authored.md) — written in the root index' memory/ddaanet/MEMORY.md
}

@test "SessionStart leaves a pending compose byte-identical and still reports the dangling pointer" {
  # A carrier-only deletion (root and root at HEAD carry the line, the carrier
  # lost it) and a root line added since HEAD: two pending composes at once.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet kept.md "carried by both"
  seed_root_bullet "ddaanet/kept.md" "carried by both"
  gitlore_compose memory
  commit_memory_state
  grep -qF -- '(ddaanet/kept.md)' memory/MEMORY.md
  sed -i.bak '/kept\.md/d' memory/ddaanet/MEMORY.md && rm memory/ddaanet/MEMORY.md.bak
  seed_root_bullet "ddaanet/gone.md" "root line for an absent file"
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  before=$(cat memory/MEMORY.md memory/ddaanet/MEMORY.md; git -C memory status --porcelain; git -C memory/ddaanet status --porcelain)
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  hook_json="$output"
  after=$(cat memory/MEMORY.md memory/ddaanet/MEMORY.md; git -C memory status --porcelain; git -C memory/ddaanet status --porcelain)
  [ "$after" = "$before" ]
  run grep -qF 'kept.md' memory/ddaanet/MEMORY.md
  [ "$status" -ne 0 ]
  # The dangling report runs whatever compose would do, and names the file.
  echo "$hook_json" | jq -e '.systemMessage | test("gone\\.md")'
}

@test "SessionStart on a store whose manifest names an unmounted tier starts, reports the tier and leaves the store alone" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ghost
  # Committed: a clean store.
  commit_memory_state
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  before=$(cat memory/MEMORY.md memory/ddaanet/MEMORY.md; git -C memory status --porcelain)
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; . == "gitlore: Run /gitlore:push (memory 1 ahead; ddaanet in sync)")'
  echo "$output" | jq -e '.systemMessage | (contains("memory ready") or contains("detached at live")) | not'
  # The report names the unmounted tier.
  echo "$output" | jq -e '.systemMessage | test("ghost")'
  [ "$(cat memory/MEMORY.md memory/ddaanet/MEMORY.md; git -C memory status --porcelain)" = "$before" ]
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
  # The whole sentence, verbatim. An absence check on a superseded wording no
  # producer emits cannot fail — nothing that drops the routing rule brings it
  # back. This equality does: naming the tier's own index instead of the root's,
  # dropping the prefix from the example, and losing the sentence altogether
  # each fail it. The tiers themselves are enumerated separately, below.
  [[ "$output" == *"add its index line to the ROOT memory/MEMORY.md with the tier prefix — '- [Title](<tier>/<file>.md) — hook'. gitlore mirrors that line down into the tier's own index for you."* ]]
}
