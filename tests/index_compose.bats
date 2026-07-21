#!/usr/bin/env bats
bats_require_minimum_version 1.5.0

load helpers/setup

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
