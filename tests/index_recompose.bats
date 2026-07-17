#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031

bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

SYNC="$PLUGIN_ROOT/scripts/lib/index-sync.sh"
SRC="$PLUGIN_ROOT/scripts/lib/index-recompose.sh"

# shellcheck disable=SC1090
setup() { setup_tmp_repo; . "$SYNC"; . "$SRC"; }
teardown() { teardown_tmp_repo; }

# A memory file with frontmatter, so coverage and prune have real files.
mkmem() { # $1 = filename, $2 = name, $3 = description
  printf -- '---\nname: %s\ndescription: %s\nmetadata:\n  type: reference\n---\n\nbody\n' \
    "$2" "$3" > "$1"
}

@test "recompose: dedup drops a duplicate-path line, keeps the first" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n- [a again](a.md) — stale dup\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run grep -c '](a.md)' MEMORY.md
  [ "$output" = "1" ]
  run grep -c 'hook a' MEMORY.md   # the FIRST line survived
  [ "$output" = "1" ]
}

@test "recompose: prune drops a line whose file is gone" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n- [ghost](ghost.md) — no file\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run grep -c 'ghost.md' MEMORY.md
  [ "$output" = "0" ]
  run grep -c '](a.md)' MEMORY.md
  [ "$output" = "1" ]
}

@test "recompose: no-op on an already-canonical index returns 0 and does not write" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  before=$(cat MEMORY.md)
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(cat MEMORY.md)" = "$before" ]
}

@test "recompose: preserves header and non-bullet lines verbatim" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\nSome prose line.\n\n- [a](a.md) — hook a\n' > MEMORY.md
  before=$(cat MEMORY.md)
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(cat MEMORY.md)" = "$before" ]
}

@test "recompose: keeps a malformed bullet (no separator) verbatim" {
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [x](a.md) no separator here\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  run grep -c 'no separator here' MEMORY.md
  [ "$output" = "1" ]
}

@test "recompose: empty store (no memory files) is a no-op, never wipes the index" {
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  before=$(cat MEMORY.md)
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(cat MEMORY.md)" = "$before" ]
}

@test "recompose: coverage seeds a line for an uncovered file, from frontmatter" {
  mkmem a.md a "hook a"
  mkmem newfact.md new-fact "a fresh durable fact"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run grep -F -- '- [new-fact](newfact.md) — a fresh durable fact' MEMORY.md
  [ "$status" -eq 0 ]
}

@test "recompose: coverage title falls back to basename when name is missing" {
  printf -- '---\ndescription: only a description\nmetadata:\n  type: reference\n---\nbody\n' > nonm.md
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  run grep -F -- '- [nonm](nonm.md) — only a description' MEMORY.md
  [ "$status" -eq 0 ]
}

@test "recompose: coverage hook falls back to title when description is empty" {
  printf -- '---\nname: no-desc\nmetadata:\n  type: reference\n---\nbody\n' > nd.md
  mkmem a.md a "hook a"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  run grep -F -- '- [no-desc](nd.md) — no-desc' MEMORY.md
  [ "$status" -eq 0 ]
}

@test "recompose: coverage line is inserted after the last existing bullet, before trailing prose" {
  mkmem a.md a "hook a"
  mkmem newfact.md new-fact "fresh fact"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n\nTrailing note.\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  line_a=$(grep -n '](a.md)' MEMORY.md | cut -d: -f1)
  line_new=$(grep -n '](newfact.md)' MEMORY.md | cut -d: -f1)
  line_note=$(grep -n 'Trailing note' MEMORY.md | cut -d: -f1)
  [ "$line_a" -lt "$line_new" ]
  [ "$line_new" -lt "$line_note" ]
}

@test "recompose is idempotent: a second run after coverage is a no-op" {
  mkmem a.md a "hook a"
  mkmem newfact.md new-fact "fresh fact"
  printf '# Memory Index\n\n- [a](a.md) — hook a\n' > MEMORY.md
  run gitlore_recompose_index .
  [ "$output" = "1" ]
  after=$(cat MEMORY.md)
  run gitlore_recompose_index .
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  [ "$(cat MEMORY.md)" = "$after" ]
}
