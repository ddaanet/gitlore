#!/usr/bin/env bats
# SessionStart's fetch of memory's `live` fetches memory alone. git's default
# `fetch.recurseSubmodules=on-demand` would otherwise run a fetch inside every
# tier whose gitlink the fetched commits move, inside memory's bound and with
# the tier remote's full refspec, bringing refs the hook never asks for.
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start
load helpers/merge-memory
load helpers/session-line

@test "memory's fetch, bringing a commit that moves a tier's gitlink, fetches nothing into the tier" {
  synced_store
  # A ref the tier's remote holds and the tier's own `origin live` fetch never
  # brings: present in the tier checkout until deleted, so a fetch with the
  # tier's full refspec is what would bring it back.
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" branch archive/old live
  git -C memory/ddaanet fetch -q origin
  git -C memory/ddaanet rev-parse -q --verify refs/remotes/origin/archive/old >/dev/null
  git -C memory/ddaanet update-ref -d refs/remotes/origin/archive/old

  # Upstream memory records a tier commit the tier checkout does not hold.
  tier_sha=$(push_tier_fact ddaanet)
  run ! git -C memory/ddaanet cat-file -e "$tier_sha^{commit}"
  work="$(mktemp -d "$TMP_REPO/clone.XXXXXX")"
  git clone -q -b live "$MEMORY_REMOTE" "$work"
  git -C "$work" update-index --cacheinfo "160000,$tier_sha,ddaanet"
  git -C "$work" -c user.email=t@t -c user.name=t commit -q -m "record the tier fact"
  git -C "$work" push -q origin live
  rm -rf "$work"

  session_start
  # Memory's fetch brought the commit: the line reads memory behind.
  assert_present sys '^gitlore: Run /gitlore:merge \(memory 1 behind'
  run ! git -C memory/ddaanet rev-parse -q --verify refs/remotes/origin/archive/old
}
