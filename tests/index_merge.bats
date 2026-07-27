#!/usr/bin/env bats
# The entry-wise three-way merge for index files.
#
# An index is a list of records keyed by pointer path, so these tests state the
# presence rule per path and the one shape that motivates the whole function:
# two sides adding the SAME path at DIFFERENT offsets, which a line-wise merge
# resolves cleanly into a duplicate pointer.

bats_require_minimum_version 1.5.0

load helpers/setup

# shellcheck disable=SC1090
setup() {
  setup_tmp_repo
  . "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
  . "$PLUGIN_ROOT/scripts/lib/index-merge.sh"
}
teardown() { teardown_tmp_repo; }

# Write an index file: $1 = name, rest = bullet lines. A fixed preamble, so the
# merged output always has a stable head to assert around.
idx() {
  local f="$1"; shift
  printf '# Memory Index\n\n' > "$f"
  local line
  for line in "$@"; do printf '%s\n' "$line" >> "$f"; done
}

merge() { gitlore_index_merge base ours theirs "MINE" "BASE" "THEIRS"; }

# --- presence: a path that existed at base ---

@test "a path both sides keep survives" {
  idx base '- [A](a.md) — hook'
  idx ours '- [A](a.md) — hook'
  idx theirs '- [A](a.md) — hook'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'- [A](a.md) — hook'* ]]
}

@test "a path deleted on one side is dropped, though the other still carries it" {
  idx base '- [A](a.md) — hook' '- [B](b.md) — hook'
  idx ours '- [A](a.md) — hook'
  idx theirs '- [A](a.md) — hook' '- [B](b.md) — hook'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" != *'b.md'* ]]
  [[ "$output" == *'a.md'* ]]
}

# --- presence: a path new since base ---

@test "a path either side added survives" {
  idx base '- [A](a.md) — hook'
  idx ours '- [A](a.md) — hook' '- [N](n.md) — mine'
  idx theirs '- [A](a.md) — hook'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'- [N](n.md) — mine'* ]]
}

@test "each side's own addition survives alongside the other's" {
  idx base '- [A](a.md) — hook'
  idx ours '- [A](a.md) — hook' '- [M](m.md) — mine'
  idx theirs '- [A](a.md) — hook' '- [T](t.md) — theirs'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'- [M](m.md) — mine'* ]]
  [[ "$output" == *'- [T](t.md) — theirs'* ]]
}

# --- the case a line-wise merge gets wrong ---

@test "both sides adding the SAME path at different offsets yields ONE bullet" {
  idx base '- [A](a.md) — hook' '- [Z](z.md) — hook'
  idx ours '- [A](a.md) — hook' '- [S](s.md) — same fact' '- [Z](z.md) — hook'
  idx theirs '- [A](a.md) — hook' '- [Z](z.md) — hook' '- [S](s.md) — same fact'
  run merge
  [ "$status" -eq 0 ]
  run -0 grep -c -- '](s.md)' <(merge)
  [ "$output" = "1" ]
}

# --- ordering ---
#
# Order is merged, not imposed. Each side states where its entries go, and the
# merge honours both statements; only a genuine disagreement about ONE offset
# falls back to a rule (MINE first), because two sides inserting different facts
# at one point disagree about placement, not about content.

@test "an insertion by theirs lands at its own offset, not at the end" {
  idx base '- [A](a.md) — h' '- [B](b.md) — h' '- [C](c.md) — h'
  idx ours '- [A](a.md) — h' '- [B](b.md) — h' '- [C](c.md) — h'
  idx theirs '- [A](a.md) — h' '- [N](n.md) — new' '- [B](b.md) — h' '- [C](c.md) — h'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'- [A](a.md) — h'$'\n''- [N](n.md) — new'$'\n''- [B](b.md) — h'* ]]
}

@test "insertions by both sides at one offset order MINE first" {
  idx base '- [A](a.md) — h' '- [Z](z.md) — h'
  idx ours '- [A](a.md) — h' '- [M](m.md) — mine' '- [Z](z.md) — h'
  idx theirs '- [A](a.md) — h' '- [T](t.md) — theirs' '- [Z](z.md) — h'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'- [M](m.md) — mine'$'\n''- [T](t.md) — theirs'$'\n''- [Z](z.md) — h'* ]]
}

@test "the same path added at two offsets takes MINE's offset, once" {
  idx base '- [A](a.md) — h' '- [Z](z.md) — h'
  idx ours '- [A](a.md) — h' '- [S](s.md) — same' '- [Z](z.md) — h'
  idx theirs '- [A](a.md) — h' '- [Z](z.md) — h' '- [S](s.md) — same'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'- [A](a.md) — h'$'\n''- [S](s.md) — same'$'\n''- [Z](z.md) — h'* ]]
}

@test "a reordering by ours survives an unrelated addition by theirs" {
  idx base '- [A](a.md) — h' '- [B](b.md) — h' '- [C](c.md) — h'
  idx ours '- [C](c.md) — h' '- [B](b.md) — h' '- [A](a.md) — h'
  idx theirs '- [A](a.md) — h' '- [B](b.md) — h' '- [C](c.md) — h' '- [D](d.md) — new'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'- [C](c.md) — h'$'\n''- [B](b.md) — h'$'\n''- [A](a.md) — h'$'\n''- [D](d.md) — new'* ]]
}

@test "a description edit does not move its entry" {
  # The reason order is merged on PATHS alone: an edit to B's hook must not make
  # B's position a merge input, or every routine rewording relocates the entry.
  idx base '- [A](a.md) — h' '- [B](b.md) — old' '- [C](c.md) — h'
  idx ours '- [A](a.md) — h' '- [B](b.md) — revised' '- [C](c.md) — h'
  idx theirs '- [A](a.md) — h' '- [N](n.md) — new' '- [B](b.md) — old' '- [C](c.md) — h'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'- [A](a.md) — h'$'\n''- [N](n.md) — new'$'\n''- [B](b.md) — revised'$'\n''- [C](c.md) — h'* ]]
}

# --- text resolution ---

@test "one side editing a bullet's text takes that side's version" {
  idx base '- [A](a.md) — old'
  idx ours '- [A](a.md) — old'
  idx theirs '- [A](a.md) — new'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'- [A](a.md) — new'* ]]
}

@test "both sides editing one bullet apart is a diff3 chunk carrying the base" {
  idx base '- [A](a.md) — old'
  idx ours '- [A](a.md) — mine'
  idx theirs '- [A](a.md) — theirs'
  run merge
  [ "$status" -eq 1 ]
  [[ "$output" == *'<<<<<<< MINE'$'\n''- [A](a.md) — mine'$'\n''||||||| BASE'$'\n''- [A](a.md) — old'$'\n''======='$'\n''- [A](a.md) — theirs'$'\n''>>>>>>> THEIRS'* ]]
}

@test "both sides adding the same NEW path with different text conflicts on an empty base" {
  idx base '- [A](a.md) — hook'
  idx ours '- [A](a.md) — hook' '- [N](n.md) — mine'
  idx theirs '- [A](a.md) — hook' '- [N](n.md) — theirs'
  run merge
  [ "$status" -eq 1 ]
  # The base section is present and empty — the shape does not vary with the case.
  [[ "$output" == *'||||||| BASE'$'\n''======='* ]]
}

# --- prose halves ---

@test "the preamble merges as prose, not as entries" {
  printf '# Memory Index\n\nA note.\n\n- [A](a.md) — hook\n' > base
  printf '# Memory Index\n\nA note, revised by me.\n\n- [A](a.md) — hook\n' > ours
  printf '# Memory Index\n\nA note.\n\n- [A](a.md) — hook\n' > theirs
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'A note, revised by me.'* ]]
}

# --- degenerate sides ---

@test "a side that has no index at all is a union, not a deletion" {
  : > base
  idx ours '- [M](m.md) — mine'
  idx theirs '- [T](t.md) — theirs'
  run merge
  [ "$status" -eq 0 ]
  [[ "$output" == *'m.md'* ]]
  [[ "$output" == *'t.md'* ]]
}

@test "a missing file is a legitimate empty side" {
  idx base '- [A](a.md) — hook'
  idx theirs '- [A](a.md) — hook'
  run gitlore_index_merge base /nonexistent-ours theirs
  # ours deleted the index entirely; every path at base loses a side.
  [ "$status" -eq 0 ]
  [[ "$output" != *'a.md'* ]]
}

# --- refusal ---

@test "a side already naming one path twice is declined, not silently collapsed" {
  idx base '- [A](a.md) — hook'
  idx ours '- [A](a.md) — hook'
  idx theirs '- [A](a.md) — one' '- [A again](a.md) — two'
  run merge
  [ "$status" -eq 2 ]
  # Nothing was printed, so the caller has nothing to write over git's own result.
  [ -z "$output" ]
}
