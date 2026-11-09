#!/usr/bin/env bats
# Two halves of the three-way compose outside a take. gitlore_compose_check_index
# refuses an index holding conflict markers, so the pending check, the
# gitlore-compose pass and the commit stop at a root index a compose-up left
# with markers, until they are gone. And the pass composes no tier up: a tier
# another checkout moved ahead of its pin is refused naming the take, which is
# the one path that composes it three-way and records it.
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

# The refusal on stderr, from bin/gitlore-compose: the verbatim pin-check line
# for tier $1 checked out at $2 over the pin $3, and the take as the remedy.
assert_refused_ahead() {
  [[ "$stderr" == *"tier composition refused"* ]] \
    || { printf 'no refusal header; stderr:\n%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"tier '$1' is checked out at ${2:0:12}, ahead of the commit the memory store records at ${3:0:12}"* ]] \
    || { printf 'the refusal does not name the tier ahead; stderr:\n%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"Run /gitlore:merge"* ]]
}

@test "gitlore-compose refuses a tier another checkout moved, naming the take, and leaves root's own new line unwritten" {
  # Fails under a pass that composes the tier up: root would gain the tier's
  # line and its gitlink would be staged with no commit approving the move.
  take_base_store
  # The tier gains a carrier line and its local `live` follows; root has not
  # recorded the move. Root alone adds a line for the tier besides.
  move_tier_off_pin_into_live ddaanet
  seed_root_bullet "ddaanet/rootonly.md" "added in root alone"
  pin=$(git -C memory rev-parse :ddaanet)
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  memory_before=$(git -C memory rev-parse HEAD)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"

  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 1 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; return 1; }
  assert_refused_ahead ddaanet "$moved" "$pin"
  # Nothing written, moved, staged or recorded: root keeps its own new line
  # unprojected, the carrier keeps its arrival, and the tier stays where the
  # other checkout left it.
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$pin" ]
  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
}

@test "gitlore-compose refuses a tier another checkout moved and leaves root's reword out of the carrier" {
  # The down projection would write root's reword into a carrier no compose has
  # read; the refusal stops ahead of it. Fails under a pass that composes up
  # and projects down in one go.
  take_base_store
  move_tier_off_pin_into_live ddaanet
  content=$(cat memory/MEMORY.md)
  printf '%s\n' "${content//"a portable fact"/"reworded in root"}" > memory/MEMORY.md
  pin=$(git -C memory rev-parse :ddaanet)
  moved=$(git -C memory/ddaanet rev-parse HEAD)
  cp memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cp memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"

  run --separate-stderr bash "$PLUGIN_ROOT/bin/gitlore-compose"
  [ "$status" -eq 1 ] || { printf 'status %s, stderr:\n%s\n' "$status" "$stderr" >&2; return 1; }
  assert_refused_ahead ddaanet "$moved" "$pin"
  cmp -s memory/MEMORY.md "$BATS_TEST_TMPDIR/root.before"
  cmp -s memory/ddaanet/MEMORY.md "$BATS_TEST_TMPDIR/tier.before"
  grep -qxF -- '- [shared](shared.md) — a portable fact' memory/ddaanet/MEMORY.md
  [ "$(git -C memory/ddaanet rev-parse HEAD)" = "$moved" ]
  [ "$(git -C memory rev-parse :ddaanet)" = "$pin" ]
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
