#!/usr/bin/env bats
# What a module reports at SessionStart (no-pin-loop plan, "What a module
# reports"). A module is the root memory store or a tier. After a fetch, it
# compares what it holds, HEAD and local `live`, with the authority's `live`:
# the remote's when the fetch brought it, local `live` otherwise (no remote, a
# failed fetch, a remote with no `live`). Strictly behind hints /gitlore:merge,
# strictly ahead /gitlore:push, diverged /gitlore:push (and so a HEAD forked from
# local `live`, whatever the authority, with a remote or without), and in sync
# reads `in sync.` and nothing else. A failed fetch keeps its could-not-fetch line, ahead of the
# table's line; a tier that fails its fetch reports its position like memory
# does; no remote adds no line.
#
# The plan fixes the hints and the token `in sync.`, not the sentences, so the
# assertions match paragraphs of the systemMessage (the notices are joined by a
# blank line) by command name, module name and that token.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start
load helpers/merge-memory

# --- assertions over the hook's two channels -----------------------------------

# Run SessionStart over the store as it stands; $output keeps the hook JSON.
session_start() {
  enable_gitlore
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
}

# Succeed when ONE paragraph of channel $1 (.systemMessage or
# .hookSpecificOutput.additionalContext) matches every ERE after it; an ERE
# starting with `!` must not match. Reads the hook JSON from $output.
para() {
  local channel="$1" res
  shift
  res=$(jq -nc '$ARGS.positional' --args "$@") || return 1
  jq -e --argjson res "$res" "($channel // \"\") | split(\"\\n\\n\") | any(.[]; . as \$p | all(\$res[]; . as \$r | if (\$r | startswith(\"!\")) then (\$p | test(\$r[1:]) | not) else (\$p | test(\$r)) end))" <<<"$output" >/dev/null
}

sys_para()  { para .systemMessage "$@"; }
ctx_para()  { para .hookSpecificOutput.additionalContext "$@"; }

# Fail, printing the channel, unless sys_para / ctx_para holds.
want_sys() { sys_para "$@" || { printf 'no systemMessage paragraph matches [%s]; systemMessage:\n%s\n' "$*" "$(jq -r '.systemMessage // ""' <<<"$output")" >&2; return 1; }; }
want_ctx() { ctx_para "$@" || { printf 'no additionalContext paragraph matches [%s]\n' "$*" >&2; return 1; }; }

# Succeed when NO paragraph of the systemMessage matches the ERE.
no_sys() { ! jq -e --arg re "$1" '(.systemMessage // "") | split("\n\n") | any(.[]; test($re))' <<<"$output" >/dev/null; }
no_ctx() { ! jq -e --arg re "$1" '(.hookSpecificOutput.additionalContext // "") | test($re)' <<<"$output" >/dev/null; }

# The index of the first byte of ERE-free literal $2 in the systemMessage, -1 if
# absent; used to put one notice before another.
sys_offset() {
  jq -r --arg s "$1" '(.systemMessage // "") | (index($s) // -1)' <<<"$output"
}

# A memory store whose remote carries `live` at HEAD, with no tier.
published_memory() { wire_memory_remote; }

# A memory store with the placeholder remote a local-only install has.
local_only_memory() {
  make_parent_with_memory
  git -C memory remote set-url origin "./.git/gitlore-placeholder"
}

# One commit on HEAD, with `live` following (what the commit path leaves).
commit_on_head_and_live() {
  git -C memory -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local fact"
  git -C memory push -q . HEAD:refs/heads/live
}

# --- memory: in sync -----------------------------------------------------------

@test "memory level with its remote's live reports in sync. and nothing else" {
  published_memory
  session_start
  want_sys 'in sync\.' '!tier'
  no_sys '/gitlore:(merge|push|resolve)'
  no_sys 'upstream|diverged|could not fetch'
}

@test "memory with a local-only remote reports in sync. against its own live, with no fetch line" {
  local_only_memory
  session_start
  want_sys 'in sync\.'
  no_sys '(?i)fetch'
  no_sys '/gitlore:(merge|push|resolve)'
}

@test "memory whose remote has no live branch yet reports in sync. against local live, with no fetch line" {
  make_parent_with_memory
  # The stock fixture remote carries only `main`.
  run git -C memory ls-remote --exit-code origin refs/heads/live
  [ "$status" -ne 0 ]
  session_start
  want_sys 'in sync\.'
  no_sys '(?i)fetch|upstream'
}

# --- memory: strictly ahead ----------------------------------------------------

@test "memory ahead of its remote hints /gitlore:push on both channels, and is not in sync" {
  published_memory
  commit_on_head_and_live
  git -C memory merge-base --is-ancestor origin/live live
  [ "$(git -C memory rev-parse origin/live)" != "$(git -C memory rev-parse live)" ]
  session_start
  want_sys '/gitlore:push'
  want_ctx '/gitlore:push'
  no_sys 'in sync\.'
  no_sys '/gitlore:(merge|resolve)'
}

@test "memory with a local-only remote and HEAD ahead of its live hints /gitlore:push" {
  local_only_memory
  git -C memory -c user.email=t@t -c user.name=t commit -q --allow-empty -m "head only"
  git -C memory merge-base --is-ancestor live HEAD
  [ "$(git -C memory rev-parse live)" != "$(git -C memory rev-parse HEAD)" ]
  session_start
  want_sys '/gitlore:push'
  no_sys 'in sync\.'
  no_sys '/gitlore:(merge|resolve)'
}

# --- memory: a HEAD forked from local live -------------------------------------

@test "memory whose HEAD forked from local live hints /gitlore:push even when the remote is ahead of live" {
  published_memory
  make_diverged_head_vs_live
  git -C memory push -q origin live
  push_memory_fact
  # The remote now holds live and one more commit: behind it, and the HEAD fork
  # is still what a merge has to start from.
  head=$(git -C memory rev-parse HEAD)
  session_start
  want_sys '/gitlore:push'
  want_ctx '/gitlore:push'
  no_sys 'in sync\.'
  # One directive for the one state: the remote being ahead does not add a
  # second hint that would take the user round the fork, and a divergence never
  # hints /gitlore:resolve.
  no_sys '/gitlore:(merge|resolve)'
  no_ctx '/gitlore:(merge|resolve)'
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
}

@test "memory whose HEAD forked from local live hints /gitlore:push with no remote at all" {
  # Probed: /gitlore:push and /gitlore:merge both prepare this merge with no
  # remote, while /gitlore:resolve opens by creating one. The hint is
  # /gitlore:push whatever the authority, and this pins it for the no-remote one.
  local_only_memory
  make_diverged_head_vs_live
  session_start
  want_sys '/gitlore:push'
  want_ctx '/gitlore:push'
  no_sys 'in sync\.'
  no_sys '/gitlore:(merge|resolve)'
  no_ctx '/gitlore:(merge|resolve)'
}

# --- memory: a failed fetch ----------------------------------------------------

@test "a failed memory fetch keeps its could-not-fetch line with git's reason, before the table's line" {
  make_parent_with_memory
  git -C memory remote set-url origin "$TMP_REPO/no-such-remote.git"
  session_start
  want_sys 'could not fetch.*no-such-remote'
  want_sys 'in sync\.'
  [ "$(sys_offset 'could not fetch')" -ge 0 ]
  [ "$(sys_offset 'could not fetch')" -lt "$(sys_offset 'in sync.')" ] || {
    printf 'the table line comes before the fetch line; systemMessage:\n%s\n' "$(jq -r .systemMessage <<<"$output")" >&2
    return 1
  }
}

@test "a failed memory fetch does not hide a position: live ahead of HEAD hints /gitlore:merge after the fetch line" {
  make_parent_with_memory
  advance_branch_with_file memory live EXTRA.md extra "Advance live"
  git -C memory remote set-url origin "$TMP_REPO/no-such-remote.git"
  session_start
  want_sys 'could not fetch'
  want_sys '/gitlore:merge'
  [ "$(sys_offset 'could not fetch')" -lt "$(sys_offset '/gitlore:merge')" ] || {
    printf 'the merge hint comes before the fetch line; systemMessage:\n%s\n' "$(jq -r .systemMessage <<<"$output")" >&2
    return 1
  }
}

# --- tiers ---------------------------------------------------------------------

# A clean memory store with its own live equal to HEAD and a tier mounted at its
# live, the manifest committed so memory reports no uncommitted change.
tier_store() {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  tier_manifest_committed
}

tier_manifest_committed() {
  commit_memory_state "memory: activate the tier"
  git -C memory push -q . HEAD:refs/heads/live
}

@test "a tier level with its remote's live reports in sync. under its own name" {
  tier_store
  session_start
  want_sys "ddaanet" 'in sync\.'
  no_sys "(?s)ddaanet.*/gitlore:(merge|push|resolve)"
  no_sys 'could not fetch'
}

@test "a tier ahead of its remote hints /gitlore:push" {
  tier_store
  git -C memory/ddaanet commit -q --allow-empty -m "local, unpublished"
  git -C memory/ddaanet push -q . HEAD:refs/heads/live
  git -C memory add ddaanet
  git -C memory commit -q -m "record the tier commit"
  git -C memory push -q . HEAD:refs/heads/live
  session_start
  want_sys "ddaanet" '/gitlore:push'
  no_sys "(?s)ddaanet.*in sync\."
  no_sys "(?s)ddaanet.*/gitlore:(merge|resolve)"
}

@test "a tier whose HEAD forked from its local live hints /gitlore:push" {
  tier_store
  advance_branch_with_file memory/ddaanet live other.md body "sideways" live
  git -C memory/ddaanet commit -q --allow-empty -m "head side"
  git -C memory add ddaanet
  git -C memory commit -q -m "record the tier commit"
  git -C memory push -q . HEAD:refs/heads/live
  run ! git -C memory/ddaanet merge-base --is-ancestor live HEAD
  run ! git -C memory/ddaanet merge-base --is-ancestor HEAD live
  session_start
  want_sys "ddaanet" '/gitlore:push'
  no_sys "(?s)ddaanet.*in sync\."
  no_sys "(?s)ddaanet.*/gitlore:(merge|resolve)"
}

@test "a tier that fails its fetch reports its position after the fetch line, as memory does" {
  tier_store
  # Local `live` one commit past HEAD: strictly behind the authority, which is
  # local `live` once the fetch has failed.
  advance_branch_with_file memory/ddaanet live other.md body "ahead of HEAD" live
  mv "$TMP_REPO/.bare-ddaanet.git" "$TMP_REPO/.bare-ddaanet.git.gone"
  session_start
  want_sys "ddaanet" 'could not fetch'
  want_sys "ddaanet" '/gitlore:merge'
  [ "$(sys_offset "could not fetch")" -lt "$(sys_offset '/gitlore:merge')" ] || {
    printf 'the tier hint comes before the fetch line; systemMessage:\n%s\n' "$(jq -r .systemMessage <<<"$output")" >&2
    return 1
  }
}

@test "a tier in sync that fails its fetch keeps the fetch line and still reports in sync." {
  tier_store
  mv "$TMP_REPO/.bare-ddaanet.git" "$TMP_REPO/.bare-ddaanet.git.gone"
  session_start
  want_sys "ddaanet" 'could not fetch'
  want_sys "ddaanet" 'in sync\.'
}

@test "a tier with no remote adds no fetch line and reports its position against local live" {
  tier_store
  git -C memory/ddaanet remote remove origin
  session_start
  no_sys "could not fetch"
  want_sys "ddaanet" 'in sync\.'
}

@test "a tier whose remote has no live branch adds no fetch line and reports its position against local live" {
  tier_store
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" branch -D live >/dev/null
  run git -C memory/ddaanet ls-remote --exit-code origin refs/heads/live
  [ "$status" -ne 0 ]
  session_start
  no_sys "could not fetch"
  want_sys "ddaanet" 'in sync\.'
}

@test "memory and a tier both in sync each report in sync., and no module reports anything else" {
  wire_memory_remote
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  tier_manifest_committed
  git -C memory push -q origin live
  session_start
  want_sys "ddaanet" 'in sync\.'
  want_sys '!ddaanet' '!tier' 'in sync\.'
  no_sys '/gitlore:(merge|push|resolve)'
  no_sys 'could not fetch|upstream|diverged|waiting'
}
