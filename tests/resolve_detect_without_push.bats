#!/usr/bin/env bats
# The default resolve run detects a remote's state and publishes nothing: a
# store ahead of its remote is reported with the command that publishes it, a
# diverged store gets its prepared merge, and no ref on any remote moves.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order

RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"
AHEAD_MEMORY="gitlore: memory is ahead of its remote. Run /gitlore:push to publish it."
AHEAD_TIER="gitlore: tier 'ddaanet' is ahead of its remote. Run /gitlore:push to publish it."

# Every ref of the memory remote and of each tier remote named in the arguments,
# as `git ls-remote` lists them, under a label per remote.
snapshot_remotes() {
  local tier
  printf 'memory\n%s\n' "$(git ls-remote "$MEMORY_REMOTE")"
  for tier in "$@"; do
    printf '%s\n%s\n' "$tier" "$(git ls-remote "$TMP_REPO/.bare-$tier.git")"
  done
}

# Run the default resolve run with stderr kept apart, and assert that no remote
# ref moved during it. Leaves $status and $stderr for the caller. Args: the tier
# names whose remotes are watched besides memory's.
resolve_leaving_remotes_alone() {
  local before after
  before=$(snapshot_remotes "$@")
  run --separate-stderr bash "$RESOLVE"
  after=$(snapshot_remotes "$@")
  [ "$before" = "$after" ] || { printf 'remotes moved:\n--- before\n%s\n--- after\n%s\n' "$before" "$after" >&2; return 1; }
}

# A root-only commit on memory's HEAD, with `live` following, unpublished.
memory_commit_unpublished() {
  printf 'local only\n' > memory/local-only.md
  git -C memory add local-only.md
  git -C memory commit -qm "a root-only fact"
  git -C memory push -q . HEAD:refs/heads/live
}

@test "default run: a memory store only ahead is reported, exit 0, and its remote does not move" {
  take_base_store
  memory_commit_unpublished
  # Strictly ahead: the remote's `live` is an ancestor of the local one.
  git -C memory merge-base --is-ancestor "$(git --git-dir="$MEMORY_REMOTE" rev-parse --verify live)" live
  [ "$(git -C memory rev-parse live)" != "$(git --git-dir="$MEMORY_REMOTE" rev-parse --verify live)" ]

  resolve_leaving_remotes_alone ddaanet
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"$AHEAD_MEMORY"* ]]
  [[ "$stderr" != *"$AHEAD_TIER"* ]]
}

@test "default run: a tier only ahead is reported by tier name, and neither remote moves" {
  take_base_store
  seed_tier_bullet ddaanet hand.md "committed by hand"
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -qm "tier fact by hand"
  git -C memory/ddaanet push -q . HEAD:refs/heads/live
  git -C memory/ddaanet merge-base --is-ancestor "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse --verify live)" live
  [ "$(git -C memory/ddaanet rev-parse live)" != "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse --verify live)" ]

  resolve_leaving_remotes_alone ddaanet
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"$AHEAD_TIER"* ]]
  [[ "$stderr" != *"$AHEAD_MEMORY"* ]]
}

@test "default run: a tier and memory both ahead are both reported, tier first" {
  take_base_store
  local_tier_commit_recorded ddaanet hand.md

  resolve_leaving_remotes_alone ddaanet
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"$AHEAD_TIER"* ]]
  [[ "$stderr" == *"$AHEAD_MEMORY"* ]]
  tier_at=$(printf '%s\n' "$stderr" | grep -nF "$AHEAD_TIER" | head -n 1 | cut -d: -f1)
  memory_at=$(printf '%s\n' "$stderr" | grep -nF "$AHEAD_MEMORY" | head -n 1 | cut -d: -f1)
  [ "$tier_at" -lt "$memory_at" ]
}

@test "default run: a memory remote with no live yet is reported ahead, and gets no live" {
  make_parent_with_memory
  bare="$TMP_REPO/.recover-remote.git"
  git init -q --bare "$bare"
  git -C memory remote remove origin
  git -C memory remote add origin "$bare"
  MEMORY_REMOTE="$bare"

  resolve_leaving_remotes_alone
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"$AHEAD_MEMORY"* ]]
  [ -z "$(git ls-remote "$bare")" ]
}

@test "default run: ahead reports suppress the healthy line" {
  take_base_store
  memory_commit_unpublished

  resolve_leaving_remotes_alone ddaanet
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"$AHEAD_MEMORY"* ]]
  [[ "$stderr" != *"state is healthy"* ]]
}

@test "default run: memory diverged from its remote prepares head-vs-remote, and the remote does not move" {
  make_parent_with_memory
  # The fixture's own bare remote, where make_diverged_head_vs_remote works.
  MEMORY_REMOTE="$TMP_REPO/.bare-memory.git"
  git -C memory push -q origin live
  make_diverged_head_vs_remote memory

  resolve_leaving_remotes_alone
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"memory merge prepared"* ]]
  [[ "$stderr" == *"flavor=head-vs-remote"* ]]
  [[ "$stderr" != *"is ahead of its remote"* ]]
  [ "$(jq -r .flavor "$(gitlore_merge_state_file memory)")" = "head-vs-remote" ]
}

@test "default run: a tier diverged from its remote prepares head-vs-remote in the tier, and no remote moves" {
  take_base_store
  local_tier_commit_recorded ddaanet local.md
  push_tier_fact ddaanet '- [up](up.md) — from upstream' >/dev/null

  resolve_leaving_remotes_alone ddaanet
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"merge prepared"* ]]
  [[ "$stderr" == *"flavor=head-vs-remote"* ]]
  [[ "$stderr" != *"is ahead of its remote"* ]]
  [ "$(jq -r .flavor "$(gitlore_merge_state_file memory/ddaanet)")" = "head-vs-remote" ]
}

@test "default run: a healthy tree prints the healthy line and no ahead line" {
  take_base_store

  resolve_leaving_remotes_alone ddaanet
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"gitlore: state is healthy. Nothing to do."* ]]
  [[ "$stderr" != *"is ahead of its remote"* ]]
}

@test "default run: a memory store only behind keeps its nothing-to-publish report" {
  take_base_store
  push_memory_fact

  resolve_leaving_remotes_alone ddaanet
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"has nothing to publish"* ]]
  [[ "$stderr" == *"Run /gitlore:merge"* ]]
  [[ "$stderr" != *"is ahead of its remote"* ]]
  [[ "$stderr" != *"memory merge prepared"* ]]
}
