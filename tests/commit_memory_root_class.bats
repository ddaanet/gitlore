#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/commit-memory

# D70: which root changes are tier-only and need no `== memory ==` section, and
# which are root content needing one. A tier-only root change is a gitlink
# moving or MEMORY.md lines that are all tier-prefixed links; anything else in
# MEMORY.md is root content. Refusals and section handling are in
# commit_memory_summary.bats.

@test "a tier change alone takes no section for root and gets the canned index commit" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  seed_tier_bullet ddaanet shared.md "fresh hook"

  gitlore_compose memory >/dev/null
  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet log -1 --pretty=%s)" = "memory: record the shared fact" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "Index lines from ddaanet" ]
  [ "$(git -C memory rev-parse HEAD:ddaanet)" = "$(git -C memory/ddaanet rev-parse HEAD)" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a root MEMORY.md line with a bare path is root content and needs a memory section" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  printf -- '---\nname: local\ndescription: ""\n---\n\nbody\n' > memory/local.md
  commit_memory_state   # local.md tracked, so only the index line is a root change
  seed_tier_bullet ddaanet shared.md "fresh hook"
  seed_root_bullet "local.md" "a local fact"
  gitlore_compose memory >/dev/null
  root_head=$(git -C memory rev-parse HEAD)
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ -n "$(git -C memory/ddaanet status --porcelain)" ]
  [ -z "$(claude_files)" ]
}

@test "a root MEMORY.md change with no link line is root content and needs a memory section" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  seed_tier_bullet ddaanet shared.md "fresh hook"
  printf 'Hand-edited note, no link.\n' >> memory/MEMORY.md
  gitlore_compose memory >/dev/null
  root_head=$(git -C memory rev-parse HEAD)
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"/gitlore:commit"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ -z "$(claude_files)" ]

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact
== memory ==
memory: record the note"
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: record the note" ]
}

@test "a tier whose mount name has a space is a tier-only root change, not root content" {
  make_parent_with_memory
  make_tier_in_memory "my tier"
  set_tier_manifest "my tier"
  commit_memory_state
  seed_tier_bullet "my tier" shared.md "fresh hook"

  gitlore_compose memory >/dev/null
  run --separate-stderr commit_with "== my tier ==
memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C "memory/my tier" log -1 --pretty=%s)" = "memory: record the shared fact" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "Index lines from my tier" ]
  [ "$(git -C memory rev-parse "HEAD:my tier")" = "$(git -C "memory/my tier" rev-parse HEAD)" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "the canned index commit names every tier whose index lines it captures, not only a moved gitlink" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  make_tier_in_memory other
  set_tier_manifest ddaanet other
  seed_tier_bullet other fact.md "a fact"
  git -C memory/other add -A
  git -C memory/other commit -q -m "other: fact"
  commit_memory_state
  seed_tier_bullet ddaanet shared.md "fresh hook"
  seed_root_bullet "other/fact.md" "a fact"

  gitlore_compose memory >/dev/null
  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 0 ]
  [ "$(git -C memory log -1 --pretty=%s)" = "Index lines from ddaanet, other" ]
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a root tier-line edit that a compose writes into a tier aborts the commit, then needs that tier's section" {
  # The tier is clean when the summary is drafted; a compose rewrites its carrier.
  # The commit path no longer composes: with the compose pending it aborts and
  # leaves the store as found. Once gitlore_compose has run, the carrier is
  # dirty and the same summary, now naming the tier's section, commits.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale hook"
  seed_root_bullet "ddaanet/shared.md" "stale hook"
  git -C memory/ddaanet add -A
  git -C memory/ddaanet commit -q -m "tier: seed"
  commit_memory_state
  sed -i.bak 's/stale hook/fresh hook/' memory/MEMORY.md
  rm memory/MEMORY.md.bak
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]

  root_head=$(git -C memory rev-parse HEAD)
  tier_head=$(git -C memory/ddaanet rev-parse HEAD)
  carrier_before=$(cksum < memory/ddaanet/MEMORY.md)
  run --separate-stderr commit_with "== ddaanet ==
memory: take the fresh hook"
  [ "$status" -ne 0 ]
  [[ "$stderr" == *"memory/ddaanet/MEMORY.md"* ]] || false
  [[ "$stderr" == *"gitlore-compose"* ]] || false
  [ "$(git -C memory rev-parse HEAD)" = "$root_head" ]
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$tier_head" ]
  [ "$(cksum < memory/ddaanet/MEMORY.md)" = "$carrier_before" ]
  [ -z "$(git -C memory/ddaanet status --porcelain)" ]

  gitlore_compose memory >/dev/null
  run --separate-stderr commit_with "== ddaanet ==
memory: take the fresh hook"
  [ "$status" -eq 0 ]
  [ "$(git -C memory/ddaanet log -1 --pretty=%s)" = "memory: take the fresh hook" ]
  grep -qF "fresh hook" memory/ddaanet/MEMORY.md
  [ -z "$(git -C memory status --porcelain)" ]
}

@test "a MEMORY.md change mixing a tier link with a linkless root line needs a memory section" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  commit_memory_state
  seed_tier_bullet ddaanet shared.md "fresh hook"
  seed_root_bullet "ddaanet/shared.md" "fresh hook"
  printf '## A root heading\n' >> memory/MEMORY.md
  root_before=$(git -C memory rev-parse HEAD)

  run --separate-stderr commit_with "== ddaanet ==
memory: record the shared fact"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"no 'memory' section"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$root_before" ]
  [ -n "$(git -C memory status --porcelain)" ]
}
