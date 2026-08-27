#!/usr/bin/env bats
# Tier commit/push lockstep (D17 slice 3): a fact authored into a nested tier is
# committed with the tier, recorded by the memory store, and pushed alongside it.
#
# Two decisions this slice settles, asserted here rather than left to prose:
#   1. ONE approval summary per memory episode, reused verbatim as the commit
#      message in every store the episode touches. The user approves a set of
#      writes, not a set of repositories.
#   2. The memory submodule gets NO recursing pre-commit/pre-push. Recursion is
#      driver-side (gitlore_sync_memory_to_live / the parent pre-push), exactly
#      as the parent already drives memory. `memory-pre-commit` stays a pure FR11
#      gate — and is emitted into each tier too, so a naked tier commit is
#      blocked the same way a naked memory commit is.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"
PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"
EMIT_GATE="$PLUGIN_ROOT/scripts/emit-memory-gate.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

# Mount a tier and bring it to the state SessionStart leaves it in: local `live`
# created from the remote, worktree detached at `live`.
mount_tier_at_live() {
  local tier="${1:-ddaanet}"
  make_tier_in_memory "$tier"
  git -C "memory/$tier" fetch -q origin "live:live"
  git -C "memory/$tier" checkout -q --detach live
}

approve() { printf '%s\n' "$1" > "$(gitlore_commit_msg_file memory)"; }

# --- commit lockstep ---

@test "a fact authored in a tier is committed with the tier" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"

  run bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
  [[ "$(git -C memory/ddaanet show HEAD:MEMORY.md)" == *'org fact'* ]]
}

@test "the tier commit advances the tier's local live" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  before=$(git -C memory/ddaanet rev-parse HEAD)
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"

  bash "$PRE_COMMIT"
  head=$(git -C memory/ddaanet rev-parse HEAD)
  live=$(git -C memory/ddaanet rev-parse live)
  [ "$head" != "$before" ]
  [ "$head" = "$live" ]
}

@test "memory records the moved tier gitlink in the same episode" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"

  bash "$PRE_COMMIT"
  [ -z "$(git -C memory status --porcelain)" ]
  recorded=$(git -C memory rev-parse HEAD:ddaanet)
  actual=$(git -C memory/ddaanet rev-parse HEAD)
  [ "$recorded" = "$actual" ]
}

@test "one approved summary is the commit message in BOTH stores" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"

  bash "$PRE_COMMIT"
  [ "$(git -C memory/ddaanet log -1 --pretty=%s)" = "memory: record the org fact" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the org fact" ]
  # Consumed exactly once, at the end of the episode.
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
}

@test "a dirty tier alone (memory's own files clean) still needs an approved summary" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md

  CLAUDECODE=1 run --separate-stderr bash "$PRE_COMMIT"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"approved commit summary"* ]]
  # Nothing committed anywhere.
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]
}

@test "a mounted but unlisted tier is still committed (dormant governs routing, not persistence)" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  [ ! -f memory/.gitlore-tiers ]   # no manifest at all → tier is dormant
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"

  run bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
}

@test "a clean tier is a no-op (no empty commit, no live churn)" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  before=$(git -C memory/ddaanet rev-parse HEAD)

  run bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$before" ]
}

@test "an unchecked-out tier is skipped, not escaped into" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  # Deregister the worktree the way a fresh clone leaves it.
  rm -rf memory/ddaanet
  mkdir memory/ddaanet
  echo dirty > memory/notes.md
  approve "memory: add notes"

  run bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  [[ "$(git -C memory show HEAD:notes.md)" == *dirty* ]]
}

# --- push lockstep ---

@test "pre-push pushes each tier's live to its own remote" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"

  run bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  local_sha=$(git -C memory/ddaanet rev-parse live)
  remote_sha=$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" rev-parse live)
  [ "$local_sha" = "$remote_sha" ]
  [[ "$(git --git-dir="$TMP_REPO/.bare-ddaanet.git" show live:MEMORY.md)" == *'org fact'* ]]
}

# Resolution itself is tier_divergence.bats' subject; what this pins is that the
# tier is named, so a merge directive in a multi-tier repo says which store.
@test "pre-push names the tier when its remote diverged" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  # Someone else advanced the tier remote in the meantime.
  push_tier_fact ddaanet "- [their fact](t.md) — theirs" >/dev/null

  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *ddaanet* ]]
  [[ "${output}${stderr}" == *"merge prepared"* ]]
}

@test "pre-push still pushes memory when a repo has no tiers" {
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  echo dirty > memory/notes.md
  approve "memory: add notes"
  bash "$PRE_COMMIT"

  run bash "$PRE_PUSH"
  [ "$status" -eq 0 ]
  local_sha=$(git -C memory rev-parse live)
  remote_sha=$(git --git-dir="$TMP_REPO/.bare-memory.git" rev-parse live)
  [ "$local_sha" = "$remote_sha" ]
}

# --- FR11 gate reaches tiers ---

@test "emit-memory-gate writes the FR11 gate into each tier's hooks dir" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  run bash "$EMIT_GATE"
  [ "$status" -eq 0 ]
  hookfile="$(git -C memory/ddaanet rev-parse --git-path hooks)/pre-commit"
  [ -x "$hookfile" ]
}

@test "a naked commit inside a tier is blocked by the FR11 gate" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  bash "$EMIT_GATE"
  echo "- [sneaky](s.md) — x" >> memory/ddaanet/MEMORY.md

  run git -C memory/ddaanet commit -aqm "naked"
  [ "$status" -ne 0 ]
  [[ "$output" == *"approval gate"* ]]
}

@test "the blessed driver passes the tier's FR11 gate" {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  bash "$EMIT_GATE"
  echo "- [org fact](f.md) — hook" >> memory/ddaanet/MEMORY.md
  approve "memory: record the org fact"

  run bash "$PRE_COMMIT"
  [ "$status" -eq 0 ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]
}
