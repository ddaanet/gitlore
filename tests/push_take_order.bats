#!/usr/bin/env bats
# A tier with uncommitted work is refused only when it has something to take,
# and the same state gets the same answer through the pre-push hook and through
# /gitlore:push. A dirty tier with nothing to take blocks no other tier.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/stub-synth
load helpers/merge-memory
load helpers/take-order
load helpers/push-fixtures

# Tier alpha is behind its remote; tier beta holds an uncommitted fact and its
# remote has nothing for it. Sets $up, the commit alpha has to take.
dirty_tier_with_nothing_to_take() {
  take_base_store alpha beta
  up=$(push_tier_fact alpha '- [a-up](a-up.md) — published upstream')
  seed_tier_bullet beta mine.md "an uncommitted fact"
}

@test "the pre-push hook takes a tier that is behind past a dirty tier with nothing to take" {
  dirty_tier_with_nothing_to_take
  b=$(git -C memory/beta rev-parse HEAD)

  run --separate-stderr bash "$PLUGIN_ROOT/scripts/git-hooks/pre-push"
  [ "$status" -eq 0 ] || { printf '%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" != *"tier 'beta' has uncommitted changes"* ]]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$up" ]
  [ "$(git -C memory/beta rev-parse HEAD)" = "$b" ]
  [ -f memory/beta/mine.md ]
}

@test "push-memory takes a tier that is behind past a dirty tier with nothing to take" {
  dirty_tier_with_nothing_to_take
  b=$(git -C memory/beta rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [[ "$stderr" != *"tier 'beta' has uncommitted changes"* ]]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$up" ]
  [ "$(git -C memory/beta rev-parse HEAD)" = "$b" ]
  [ -f memory/beta/mine.md ]
}

@test "push-memory refuses a dirty tier with something to take before another tier moves" {
  take_base_store alpha beta
  push_tier_fact alpha '- [a-up](a-up.md) — published upstream' >/dev/null
  push_tier_fact beta '- [b-up](b-up.md) — published upstream' >/dev/null
  seed_tier_bullet beta mine.md "an uncommitted fact"
  a=$(git -C memory/alpha rev-parse HEAD)
  b=$(git -C memory/beta rev-parse HEAD)
  root=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"tier 'beta' has uncommitted changes"* ]]
  [[ "$stderr" == *[Cc]ommit\ * ]]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$a" ]
  [ "$(git -C memory/beta rev-parse HEAD)" = "$b" ]
  [ "$(git -C memory rev-parse HEAD)" = "$root" ]
}

# Tier alpha is behind its remote; tier beta holds an uncommitted fact and a
# commit on HEAD only, while its local `live` sits on a sibling commit — HEAD
# lacks `live` without `live` being ahead of it. Sets $a, alpha's HEAD.
dirty_tier_forked_from_live() {
  local side
  take_base_store alpha beta
  push_tier_fact alpha '- [a-up](a-up.md) — published upstream' >/dev/null
  a=$(git -C memory/alpha rev-parse HEAD)
  printf 'y\n' > memory/beta/head-only.md
  git -C memory/beta add head-only.md
  git -C memory/beta commit -qm "on HEAD only"
  side=$(side_branch_tier_commit beta)
  git -C memory/beta branch -f live "$side"
  seed_tier_bullet beta mine.md "an uncommitted fact"
}

@test "merge-memory refuses a dirty tier whose HEAD lacks its live before another tier moves" {
  dirty_tier_forked_from_live
  root=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$PLUGIN_ROOT/scripts/merge-memory.sh"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$a" ]
  [[ "$stderr" == *"tier 'beta' has uncommitted changes, so nothing was taken"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$root" ]
}

@test "push-memory refuses a dirty tier whose HEAD lacks its live before another tier moves" {
  dirty_tier_forked_from_live
  root=$(git -C memory rev-parse HEAD)

  run --separate-stderr bash "$CMD"
  [ "$status" -ne 0 ]
  [ "$(git -C memory/alpha rev-parse HEAD)" = "$a" ]
  [[ "$stderr" == *"tier 'beta' has uncommitted changes, so nothing was taken"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$root" ]
}

@test "a dirty tier diverged from its remote gets the same refusal from push-memory and the pre-push hook, and no merge" {
  take_base_store alpha beta
  advance_tier_past_remote beta
  push_tier_fact beta '- [b-up](b-up.md) — published upstream' >/dev/null
  # Untracked only, so a merge preparation would not be stopped by git itself.
  printf 'draft\n' > memory/beta/draft.md
  state=$(git -C memory/beta rev-parse --git-path gitlore-merge-state)

  run --separate-stderr bash "$CMD"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"tier 'beta' has uncommitted changes, so nothing was taken"* ]]

  run --separate-stderr bash "$PLUGIN_ROOT/scripts/git-hooks/pre-push"
  [ "$status" -ne 0 ]
  hook_err=$stderr
  run git -C memory/beta rev-parse -q --verify MERGE_HEAD
  [ "$status" -ne 0 ]
  [ ! -e "$state" ]
  [[ "$hook_err" == *"tier 'beta' has uncommitted changes, so nothing was taken"* ]]
  [ -f memory/beta/draft.md ]
}

@test "push-memory records a taken tier when root is behind its remote and dirty" {
  # The take inside the push moves ddaanet; the end compose first takes root,
  # which is behind its remote but holds an uncommitted file, so root's take is
  # refused. The compose still runs: the moved gitlink and the recomposed root
  # index are staged (D43) for the commit the refusal asks for, and the push
  # fails on the refusal. Fails under an end compose that returns at root's
  # refusal, leaving `:ddaanet` at the pin for the commit's pin guard to refuse.
  wire_memory_remote
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  gitlore_compose memory
  commit_memory_state
  git -C memory push -q origin HEAD:live
  pin=$(git -C memory rev-parse HEAD:ddaanet)
  remote_sha=$(push_tier_fact ddaanet '- [upstream](upstream.md) — published by another repo')
  printf 'unapproved\n' > memory/pending-fact.md
  push_memory_fact

  run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"memory has uncommitted changes, so its remote was left untouched"* ]]
  [[ "$output" == *"staged rather than committed"* ]]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$remote_sha" ]
  [ "$(git -C memory rev-parse ":ddaanet")" = "$remote_sha" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$pin" ]
  git -C memory diff --cached --name-only | grep -Fqx -- MEMORY.md
  [ -f memory/pending-fact.md ]
  run gitlore_compose_pending memory
  [ "$status" -eq 0 ]
}
