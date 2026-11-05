#!/usr/bin/env bats
# Two halves of the three-way compose outside a take. gitlore_compose_check_index
# refuses an index holding conflict markers, so the pending check, the
# gitlore-compose pass and the commit stop at a root index a compose-up left
# with markers, until they are gone. And the pass itself runs the three-way for
# each tier off its pin, so a tier another checkout moved composes like an
# arrival.
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

# --- fixtures -----------------------------------------------------------------

# A committed store whose root index then gains a project line and, after its
# last pointer, a conflict chunk in the trailer — markers no pointer rule sees.
# The project line gives `gitlore-commit` a root change to summarize.
root_with_trailer_markers() {
  take_base_store
  printf -- '---\nname: proj\ndescription: ""\n---\n\nbody\n' > memory/proj.md
  seed_root_bullet "proj.md" "a project fact"
  printf '<<<<<<< HEAD\nours text\n||||||| 1234567\nbase text\n=======\ntheirs text\n>>>>>>> 89abcde\n' >> memory/MEMORY.md
}

# The chunk as a compose-up writes it: three versions of one pointer line inside
# the pointer block.
root_with_block_chunk() {
  take_base_store
  printf '# memory\n<<<<<<< HEAD\n- [shared](ddaanet/shared.md) — ours\n||||||| 1234567\n- [shared](ddaanet/shared.md) — a portable fact\n=======\n- [shared](ddaanet/shared.md) — theirs\n>>>>>>> 89abcde\n' > memory/MEMORY.md
}

# Remove the marker lines and the chunk's text, the way a person settles it.
settle_markers() {
  grep -vE '^(<<<<<<< |\|\|\|\|\|\|\| |=======$|>>>>>>> |ours text$|base text$|theirs text$)' memory/MEMORY.md > "$BATS_TEST_TMPDIR/settled"
  cp "$BATS_TEST_TMPDIR/settled" memory/MEMORY.md
}

via_commit_bin() {
  local summary
  summary=$(sectioned_summary "memory: record the edits")
  # shellcheck disable=SC2016 # $1 and $2 expand in the inner shell
  run --separate-stderr bash -c \
    'printf "%s\n" "$1" | "$2/bin/gitlore-commit"' _ "$summary" "$PLUGIN_ROOT"
}

# --- the marker rule ----------------------------------------------------------

@test "gitlore-compose refuses a root index holding conflict markers until they are gone" {
  root_with_trailer_markers
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root-before"

  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 1 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; return 1; }
  grep -qi marker <<<"$stderr"
  cmp -- "$BATS_TEST_TMPDIR/root-before" memory/MEMORY.md

  settle_markers
  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ]
}

@test "gitlore-compose names conflict markers for a chunk inside the pointer block" {
  # Refused today as a duplicate pointer; the marker rule names the cause.
  root_with_block_chunk

  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 1 ]
  grep -qi marker <<<"$stderr" || { printf 'stderr never mentions markers:\n%s\n' "$stderr" >&2; return 1; }
}

@test "the pending check refuses a root index holding conflict markers" {
  root_with_trailer_markers

  run gitlore_compose_pending memory
  [ "$status" -eq 1 ] || { printf 'status %s, output:\n%s\n' "$status" "$output" >&2; return 1; }
  grep -qi marker <<<"$output"
}

@test "gitlore-commit refuses a root index holding conflict markers and commits nothing" {
  root_with_trailer_markers
  head=$(git -C memory rev-parse HEAD)

  via_commit_bin
  [ "$status" -ne 0 ] || { echo "the commit went through with markers in root" >&2; return 1; }
  grep -qi marker <<<"$stderr"
  [ "$(git -C memory rev-parse HEAD)" = "$head" ]
}

# --- the pass on a tier off its pin -------------------------------------------

@test "gitlore-compose adopts a tier another checkout moved and keeps a line root alone added for it" {
  take_base_store
  # The tier gains a carrier line and its local `live` follows; root has not
  # recorded the move. Root alone adds a line for the tier besides.
  move_tier_off_pin_into_live ddaanet
  seed_root_bullet "ddaanet/rootonly.md" "added in root alone"
  pin=$(git -C memory rev-parse :ddaanet)

  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; return 1; }
  grep -qxF -- '- [upstream](ddaanet/upstream.md) — arrived in another repo' memory/MEMORY.md
  grep -qxF -- '- [rootonly](ddaanet/rootonly.md) — added in root alone' memory/MEMORY.md
  # The pass moves the tier nowhere: it is where the other checkout left it.
  [ "$(git -C memory/ddaanet rev-parse HEAD)" != "$pin" ]
}

@test "gitlore-compose keeps root's reword of a line the tier did not touch while it adopts the tier's new line" {
  take_base_store
  move_tier_off_pin_into_live ddaanet
  content=$(cat memory/MEMORY.md)
  printf '%s\n' "${content//"a portable fact"/"reworded in root"}" > memory/MEMORY.md

  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; return 1; }
  grep -qxF -- '- [upstream](ddaanet/upstream.md) — arrived in another repo' memory/MEMORY.md
  grep -qxF -- '- [shared](ddaanet/shared.md) — reworded in root' memory/MEMORY.md
}

@test "passing pin: the pass on a tier at its pin leaves root's reword in root and projects it into the carrier" {
  take_base_store
  content=$(cat memory/MEMORY.md)
  printf '%s\n' "${content//"a portable fact"/"reworded in root"}" > memory/MEMORY.md

  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 0 ]
  grep -qxF -- '- [shared](ddaanet/shared.md) — reworded in root' memory/MEMORY.md
  grep -qxF -- '- [shared](shared.md) — reworded in root' memory/ddaanet/MEMORY.md
}
