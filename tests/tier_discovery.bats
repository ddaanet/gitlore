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

@test "SessionStart does not put a tier that had outrun its gitlink back on it, and reports it in sync with its remote" {
  # A tier ahead of the commit memory records is not a fault: the three-way
  # compose answers any disagreement between root's lines and the carrier, and
  # the commit records the tier's HEAD. SessionStart therefore leaves it there.
  # The report compares HEAD and local `live` with the remote's `live`, not with
  # the pin: this tier is past the pin and equal to its remote, so it is in sync.
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
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; contains("ddaanet") and contains("in sync."))'
  # No paragraph naming the tier reads the pin as the authority: no merge hint
  # and no upstream facts waiting.
  echo "$output" | jq -e '.systemMessage | split("\n\n") | all(.[]; (contains("ddaanet") and (contains("/gitlore:merge") or contains("waiting"))) | not)'
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
  # Behind the remote is a take: /gitlore:merge, which needs no push, and no
  # offer of /gitlore:push.
  echo "$output" | jq -e '.systemMessage | test("/gitlore:merge")'
  echo "$output" | jq -e '.systemMessage | test("no push"; "i")'
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
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; contains("ddaanet") and contains("/gitlore:push"))'
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
  echo "$output" | jq -e '.systemMessage | test("tier .ddaanet. has diverged")'
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
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; contains("in sync."))'
  echo "$output" | jq -e '.systemMessage | (contains("memory ready") or contains("detached at live")) | not'
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
  # Committed, so the store is clean and the position report is "in sync.".
  commit_memory_state
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  export GITLORE_LAUNCHED=1
  before=$(cat memory/MEMORY.md memory/ddaanet/MEMORY.md; git -C memory status --porcelain)
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | split("\n\n") | any(.[]; contains("in sync.") and (contains("ghost") | not))'
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
