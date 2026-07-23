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

@test "problems from two indexes stay on separate lines" {
  # Each index's problems are captured separately, and a capture drops its
  # trailing newline: without one added back, the root's last problem and the
  # carrier's first share a line — and that string is the refusal banner the
  # user reads.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "ddaanet/dup.md" "first"
  seed_root_bullet "ddaanet/dup.md" "second"
  seed_tier_bullet ddaanet other.md "first"
  seed_tier_bullet ddaanet other.md "second"
  run gitlore_compose_check memory
  [ "$status" -eq 1 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "memory/MEMORY.md: duplicate pointer path ddaanet/dup.md" ]
  [ "${lines[1]}" = "memory/ddaanet/MEMORY.md: duplicate pointer path other.md" ]
}

@test "a mounted but unlisted tier is dormant, not an error" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest
  run gitlore_compose_check memory
  [ "$status" -eq 0 ]
}

@test "splice up: an active tier's carrier bullets appear prefixed in the root" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "project_overview.md" "the project"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [shared](ddaanet/shared.md) — a portable fact' memory/MEMORY.md
  # Tier block precedes project lines.
  tierline=$(grep -n 'ddaanet/shared.md' memory/MEMORY.md | cut -d: -f1)
  projline=$(grep -n 'project_overview.md' memory/MEMORY.md | cut -d: -f1)
  [ "$tierline" -lt "$projline" ]
}

@test "mirror down: a root-authored tier line lands in the carrier, unprefixed" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "ddaanet/new_fact.md" "authored in the root"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [new_fact](new_fact.md) — authored in the root' memory/ddaanet/MEMORY.md
  run ! grep -qF 'ddaanet/new_fact.md' memory/ddaanet/MEMORY.md
}

@test "compose is byte-idempotent" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "ddaanet/other.md" "root authored"
  seed_root_bullet "project_overview.md" "the project"
  gitlore_compose memory
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.1"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.1"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]                       # nothing changed → nothing reported
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.1"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.1"
}

@test "the root's hook text wins over a divergent carrier hook" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "stale carrier text"
  seed_root_bullet "ddaanet/shared.md" "fresh curated text"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '— fresh curated text' memory/ddaanet/MEMORY.md
  run ! grep -qF 'stale carrier text' memory/ddaanet/MEMORY.md
  [ "$(grep -c 'shared.md' memory/MEMORY.md)" -eq 1 ]
}

@test "manifest order is tier block order" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  make_tier_in_memory lore
  set_tier_manifest lore ddaanet
  seed_tier_bullet ddaanet d.md "dd fact"
  seed_tier_bullet lore l.md "lore fact"
  gitlore_compose memory
  l=$(grep -n 'lore/l.md' memory/MEMORY.md | cut -d: -f1)
  d=$(grep -n 'ddaanet/d.md' memory/MEMORY.md | cut -d: -f1)
  [ "$l" -lt "$d" ]
}

@test "a dormant mounted tier is dropped from the root but keeps its carrier lines" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_compose memory
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  set_tier_manifest                       # deactivate
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  run ! grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  grep -qF -- '- [shared](shared.md) — a portable fact' memory/ddaanet/MEMORY.md
}

@test "a dormant tier still receives mirror-down, so no root line is lost" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest                       # mounted, never active
  seed_root_bullet "ddaanet/rescued.md" "would be dropped"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF -- '- [rescued](rescued.md) — would be dropped' memory/ddaanet/MEMORY.md
  run ! grep -qF 'ddaanet/rescued.md' memory/MEMORY.md
}

@test "preamble and trailer are preserved verbatim" {
  make_parent_with_memory
  printf '# Memory Index\n\n- [A](a.md) — x\n\n<!-- footer -->\n' > memory/MEMORY.md
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  head -1 memory/MEMORY.md | grep -qF '# Memory Index'
  tail -1 memory/MEMORY.md | grep -qF '<!-- footer -->'
}

@test "project bullets keep their order and are never rewritten" {
  make_parent_with_memory
  printf '# Memory Index\n\n- [C](c.md) — three\n- [A](a.md) — one\n- [B](b.md) — two\n' > memory/MEMORY.md
  gitlore_compose memory
  run gitlore_index_part memory/MEMORY.md bullets
  [ "$output" = "$(printf -- '- [C](c.md) — three\n- [A](a.md) — one\n- [B](b.md) — two')" ]
}

@test "dangling reports a root bullet whose file is absent" {
  make_parent_with_memory
  seed_root_bullet "gone.md" "the fact that got away"
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"gone.md"* ]]
  [[ "$output" == *"memory/MEMORY.md"* ]]
}

@test "dangling is silent when every pointer resolves" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "here.md" "present"
  printf 'body\n' > memory/here.md
  gitlore_compose memory
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dangling resolves a tier-prefixed root path inside the tier" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  gitlore_compose memory                    # splices ddaanet/shared.md into the root
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "dangling reports each missing target once, not once per index" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "ddaanet/vanished.md" "authored in the root"
  gitlore_compose memory                    # mirrors the line down into the carrier
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c 'vanished.md')" -eq 1 ]
}

@test "dangling inspects a dormant tier's carrier, which the root never shows" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest                         # mounted, never active
  printf -- '- [orphan](orphan.md) — no such file\n' >> memory/ddaanet/MEMORY.md
  run gitlore_compose_dangling memory
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphan.md"* ]]
  [[ "$output" == *"memory/ddaanet/MEMORY.md"* ]]
}

@test "a dangling pointer reports but never refuses: compose still writes" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_bullet "gone.md" "stale line"
  run gitlore_compose memory
  [ "$status" -eq 0 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  # The stale line survives: an index edit is the agent's, never the hook's.
  grep -qF -- '- [gone](gone.md) — stale line' memory/MEMORY.md
  # And compose's own report stays a list of what it WROTE.
  [[ "$output" != *"names no file"* ]]
}

@test "a failed index write is reported, not reported as success" {
  # The writes run inside a command substitution feeding a string append, and
  # every caller invokes gitlore_compose as an `if` condition — which disables
  # errexit for the whole call. Without an explicit status check a failed write
  # left the index unchanged and the hook said "recomposed".
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  seed_root_bullet "ddaanet/shared.md" "a portable fact"
  # No write permission on the carrier's directory: the temp file cannot be
  # created there, so gitlore_compose_write fails.
  chmod a-w memory/ddaanet
  run gitlore_compose memory
  chmod u+w memory/ddaanet
  [ "$status" -eq 2 ]
  [[ "$output" == *"could not write memory/ddaanet/MEMORY.md"* ]]
}

@test "a failing check writes nothing at all" {
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ghost
  seed_tier_bullet ddaanet shared.md "a portable fact"
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
  run gitlore_compose memory
  [ "$status" -eq 1 ]
  [[ "$output" == *"ghost"* ]]
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
}
