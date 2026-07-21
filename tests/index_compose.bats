#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# `load helpers/setup` already sources every scripts/lib/*.sh, which is where
# gitlore_tier_paths / gitlore_active_tiers come from. Re-sourcing util.sh here
# would fail on its readonly constants, so only the file under test is named.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "bullet_path extracts the path from a well-formed bullet" {
  run gitlore_bullet_path '- [Some Title](foo_bar.md) — the hook text'
  [ "$status" -eq 0 ]
  [ "$output" = "foo_bar.md" ]
}

@test "bullet_path handles a prefixed path and a hook containing parens" {
  run gitlore_bullet_path '- [T](ddaanet/x.md) — hook (with parens) — and a dash'
  [ "$output" = "ddaanet/x.md" ]
}

@test "bullet_path rejects a non-bullet and a bullet with no link" {
  run gitlore_bullet_path '# Memory Index'
  [ "$status" -eq 1 ]
  run gitlore_bullet_path '- [just a bracketed phrase] and prose'
  [ "$status" -eq 1 ]
}

@test "bullet_path accepts a bullet with no hook separator" {
  run gitlore_bullet_path '- [T](foo.md)'
  [ "$status" -eq 0 ]
  [ "$output" = "foo.md" ]
}

@test "reprefix and deprefix round-trip, preserving title and hook" {
  line='- [Some Title](foo.md) — hook — with an em dash'
  run gitlore_bullet_reprefix "$line" ddaanet
  [ "$output" = '- [Some Title](ddaanet/foo.md) — hook — with an em dash' ]
  run gitlore_bullet_deprefix "$output" ddaanet
  [ "$output" = "$line" ]
}

@test "deprefix refuses a line that does not carry the prefix" {
  run gitlore_bullet_deprefix '- [T](foo.md) — h' ddaanet
  [ "$status" -eq 1 ]
}

@test "index_region reports the first and last bullet lines" {
  printf '# Head\n\n- [A](a.md) — x\n- [B](b.md) — y\n\nTrailing prose\n' > idx.md
  run gitlore_index_region idx.md
  [ "$output" = "3 4" ]
}

@test "index_region reports 0 0 for a bulletless index" {
  printf -- '---\ndescription: "d"\n---\n\n# Tier\n' > idx.md
  run gitlore_index_region idx.md
  [ "$output" = "0 0" ]
}

@test "index_part splits preamble, bullets and trailer" {
  printf '# Head\n\n- [A](a.md) — x\n- [B](b.md) — y\n\nTrailing prose\n' > idx.md
  run gitlore_index_part idx.md preamble
  [ "$output" = "$(printf '# Head\n')" ]
  run gitlore_index_part idx.md bullets
  [ "$output" = "$(printf -- '- [A](a.md) — x\n- [B](b.md) — y')" ]
  run gitlore_index_part idx.md trailer
  [ "$output" = "$(printf '\nTrailing prose')" ]
}

@test "index_part of a bulletless index is all preamble" {
  printf -- '---\ndescription: "d"\n---\n\n# Tier\n' > idx.md
  run gitlore_index_part idx.md bullets
  [ -z "$output" ]
  run gitlore_index_part idx.md trailer
  [ -z "$output" ]
  run gitlore_index_part idx.md preamble
  [[ "$output" == *"# Tier"* ]]
}

@test "tier_of attributes a prefixed path to a mounted tier" {
  tiers=$(printf 'ddaanet\nlore\n')
  run gitlore_tier_of "ddaanet/x.md" "$tiers"
  [ "$status" -eq 0 ]
  [ "$output" = "ddaanet" ]
}

@test "tier_of rejects a bare path and an unknown prefix" {
  tiers=$(printf 'ddaanet\n')
  run gitlore_tier_of "x.md" "$tiers"
  [ "$status" -eq 1 ]
  run gitlore_tier_of "gone/x.md" "$tiers"
  [ "$status" -eq 1 ]
}

@test "check passes on a well-formed store" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "project_overview.md" "the project"
  run gitlore_compose_check memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "check fails on a duplicate path in the root index" {
  make_parent_with_memory
  seed_root_bullet "dup.md" "first"
  seed_root_bullet "dup.md" "second"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate"* ]]
  [[ "$output" == *"dup.md"* ]]
}

@test "check fails when the manifest lists a tier that is not mounted" {
  make_parent_with_memory
  set_tier_manifest ghost
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost"* ]]
  [[ "$output" == *"not mounted"* ]]
}

@test "check fails on a root bullet whose prefix names no mounted tier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "removed_tier/orphan.md" "leftover"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"removed_tier/orphan.md"* ]]
}

@test "check fails on a non-bullet line inside the bullet region" {
  make_parent_with_memory
  seed_root_bullet "a.md" "x"
  printf '\nSome interleaved prose\n\n' >> memory/MEMORY.md
  seed_root_bullet "b.md" "y"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"interleaved"* ]]
}

@test "check inspects tier carriers too, not just the root" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet dup.md "first"
  seed_tier_bullet ddaanet dup.md "second"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"duplicate"* ]]
}

@test "a mounted but unlisted tier is dormant, not an error" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest
  run gitlore_compose_check memory
  [ "$status" -eq 0 ]
}
