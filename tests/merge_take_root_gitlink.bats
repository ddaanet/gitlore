#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order

# The root merge of a take meets each tier gitlink after the tier already moved.
# The answer is the tier's HEAD, which the prepare stages into the pending merge
# after an ancestry check and before the merger is briefed, so the merger sees
# index and fact text only.

@test "both sides moved the pin: the tier merge is prepared before the root merge" {
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet local.md
  upstream_moves_pin ddaanet up.md >/dev/null

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ]
  [ "${#TAKE_YIELDS[@]}" -eq 2 ] || { printf '%s\n' "${TAKE_YIELDS[@]}" >&2; return 1; }
  [ "${TAKE_YIELDS[0]%% *}" = "memory/ddaanet" ] || { printf 'first yield: %s\n' "${TAKE_YIELDS[0]}" >&2; return 1; }
  [ "${TAKE_YIELDS[1]%% *}" = "memory" ] || { printf 'second yield: %s\n' "${TAKE_YIELDS[1]}" >&2; return 1; }
}

@test "both sides moved the pin: no tier is unmerged or listed as conflicted when the take yields" {
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet local.md
  upstream_moves_pin ddaanet up.md >/dev/null

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ]
  [ "${#TAKE_YIELDS[@]}" -ge 1 ]
  local y unmerged conflicted
  for y in "${TAKE_YIELDS[@]}"; do
    unmerged="${y#*unmerged=}"
    unmerged="${unmerged%% conflicted=*}"
    conflicted="${y#*conflicted=}"
    conflicted="${conflicted%% gitlink=*}"
    # Neither the index nor the state file the merger is handed names the tier.
    [[ "$unmerged" != *ddaanet* ]] || { printf 'unmerged tier entry at yield: %s\n' "$y" >&2; return 1; }
    [[ "$conflicted" != *ddaanet* ]] || { printf 'tier listed as conflicted in the state file: %s\n' "$y" >&2; return 1; }
  done
}

@test "both sides moved the pin: the root merge records the tier's HEAD, and both facts' lines reach root" {
  take_base_store ddaanet
  local_tier_commit_recorded ddaanet local.md
  upstream_moves_pin ddaanet up.md >/dev/null

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ]
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  # The tier merged: its HEAD has the local commit and the upstream one as parents.
  [ "$(git -C memory/ddaanet rev-list --parents -n 1 HEAD | wc -w | tr -d ' ')" -eq 3 ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$tier_head" ]
  [ -z "$(git -C memory ls-files -u)" ]
  [ -z "$(git -C memory status --porcelain)" ]
  grep -qF -- '- [local](ddaanet/local.md) — committed here' memory/MEMORY.md
  grep -qF -- '- [up](ddaanet/up.md) — from upstream' memory/MEMORY.md
}

@test "the root merge records the tier's HEAD when the tier is past the commit upstream root names" {
  # Upstream root records U; the tier's remote has moved on to U2. Git takes the
  # gitlink U silently, which leaves the tier ahead of its pin; the prepare stages
  # the tier's HEAD instead.
  take_base_store ddaanet
  printf 'local only\n' > memory/local-only.md
  git -C memory add -A
  git -C memory commit -qm "a root-only fact"
  git -C memory push -q . HEAD:refs/heads/live
  upstream_moves_pin ddaanet up.md >/dev/null
  tier_sha=$(push_tier_fact ddaanet '- [later](later.md) — published after the pin')

  drive_take_to_rest memory/ddaanet
  [ "$TAKE_STATUS" -eq 0 ]
  [ "${#TAKE_YIELDS[@]}" -eq 1 ]
  # When the take yields, the index holds the tier's HEAD.
  yield="${TAKE_YIELDS[0]}"
  [[ "$yield" == "memory unmerged= conflicted= gitlink=$tier_sha:$tier_sha" ]] || { printf 'yield: %s\nwant the index gitlink and the tier HEAD both %s\n' "$yield" "$tier_sha" >&2; return 1; }
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$tier_sha" ]
}

@test "a root merge whose gitlink the tier HEAD does not descend stops the prepare naming the tier" {
  # Upstream root records a commit on a side branch of the tier's remote; the
  # take moves the tier to the remote's `live`, which does not contain it.
  take_base_store ddaanet
  printf 'local only\n' > memory/local-only.md
  git -C memory add -A
  git -C memory commit -qm "a root-only fact"
  git -C memory push -q . HEAD:refs/heads/live
  side=$(side_branch_tier_commit ddaanet)
  memory_remote_records ddaanet "$side" "- [side](ddaanet/side.md) — on a branch live never took" >/dev/null
  up=$(push_tier_fact ddaanet '- [up](up.md) — published on live')
  head_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  err="$stderr"
  # The tier was taken first: the stop came from the root prepare, after it.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$up" ]
  # The merger was not briefed: no directive, no state file, no merge pending.
  [[ "$output$err" != *"dispatch sub-agent"* ]]
  [ ! -f "$(gitlore_merge_state_file memory)" ]
  run ! git -C memory rev-parse -q --verify MERGE_HEAD
  # Root is back where it was.
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  # And the reason names the tier.
  [[ "$err" == *"tier 'ddaanet'"* ]]
}

@test "a tier gitlink that resolves nowhere: the tiers are taken and the root fast-forward is refused" {
  take_base_store ddaanet
  lost=$(unpublished_tier_commit ddaanet)
  memory_remote_records ddaanet "$lost" "- [lost](ddaanet/lost.md) — recorded where the tier lacks it" >/dev/null
  tier_sha=$(push_tier_fact ddaanet '- [up](up.md) — published on live')
  root_before=$(git -C memory rev-parse HEAD)
  index_before=$(cat memory/MEMORY.md)

  # The user's run: the remote's url is on the user channel only.
  CLAUDECODE='' run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  # Root moved nothing and composed nothing.
  [ "$(git -C memory rev-parse HEAD)" = "$root_before" ]
  [ "$(git -C memory rev-parse live)" = "$root_before" ]
  [ "$(cat memory/MEMORY.md)" = "$index_before" ]
  # The tier moved on, so the worktree shows the tier ahead of its pin.
  [ -z "$(git -C memory status --porcelain --ignore-submodules=all)" ]
  # The tier was taken all the same.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_sha" ]
  # The report: the commit, the tier, the remote that lacks it, the remedy.
  [[ "$stderr" == *"${lost:0:7}"* ]]
  [[ "$stderr" == *"tier 'ddaanet'"* ]]
  [[ "$stderr" == *"$TMP_REPO/.bare-ddaanet.git"* ]]
  [[ "$stderr" == *"/gitlore:push"* ]]
}

@test "a tier gitlink that resolves nowhere: a diverged root is refused without a prepared merge" {
  take_base_store ddaanet
  printf 'local only\n' > memory/local-only.md
  git -C memory add -A
  git -C memory commit -qm "a root-only fact"
  git -C memory push -q . HEAD:refs/heads/live
  lost=$(unpublished_tier_commit ddaanet)
  memory_remote_records ddaanet "$lost" "- [lost](ddaanet/lost.md) — recorded where the tier lacks it" >/dev/null
  tier_sha=$(push_tier_fact ddaanet '- [up](up.md) — published on live')
  root_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE='' run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  err="$stderr"
  [[ "$output$err" != *"dispatch sub-agent"* ]]
  [ ! -f "$(gitlore_merge_state_file memory)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$root_before" ]
  run ! grep -qF 'ddaanet/lost.md' memory/MEMORY.md
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_sha" ]
  [[ "$err" == *"${lost:0:7}"* ]]
  [[ "$err" == *"tier 'ddaanet'"* ]]
  [[ "$err" == *"$TMP_REPO/.bare-ddaanet.git"* ]]
  [[ "$err" == *"/gitlore:push"* ]]
}

@test "root's own recorded gitlink that the tier HEAD does not descend stops the prepare naming the tier" {
  # The other side of the ancestry check: here root's HEAD records the commit on
  # the side branch, and upstream root moves on without it.
  take_base_store ddaanet
  side=$(side_branch_tier_commit ddaanet)
  git -C memory update-index --cacheinfo "160000,$side,ddaanet"
  git -C memory commit -qm "records a commit the tier's live lacks"
  git -C memory push -q . HEAD:refs/heads/live
  push_memory_fact
  head_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  err="$stderr"
  [[ "$output$err" != *"dispatch sub-agent"* ]]
  [ ! -f "$(gitlore_merge_state_file memory)" ]
  run ! git -C memory rev-parse -q --verify MERGE_HEAD
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [[ "$err" == *"tier 'ddaanet'"* ]]
}
