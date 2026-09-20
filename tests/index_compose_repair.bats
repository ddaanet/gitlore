#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures

# Header as in tests/index_compose.bats. Covers gitlore_repair_index: welds,
# interleaved lines, and duplicates.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

# --- gitlore_repair_index: welds, then interleaved lines, then duplicates ---
#
# A plain scratch file stands in for the arrival's carrier, and a plain
# directory for the tier a weld's second path must resolve under — the
# function takes three paths and has no opinion about what else lives beside
# them, so the fixture is pure files rather than a full tier mount.

@test "repairing a clean index changes nothing" {
  mkdir -p tier
  printf -- '# Memory Index\n\n- [A](a.md) — x\n\n- [B](b.md) — y\n\nTrailing prose\n' > clean.md
  cp clean.md clean.before
  # A second name for the same inode: a rewrite of identical bytes renamed over
  # the file leaves the two names pointing at different files.
  ln clean.md clean.link
  run gitlore_repair_index clean.md pin.md tier
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp -s clean.md clean.before
  [ clean.md -ef clean.link ]

  cp clean.before unterm.md
  unterminate_index unterm.md
  cp unterm.md unterm.before
  ln unterm.md unterm.link
  run gitlore_repair_index unterm.md pin.md tier
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp -s unterm.md unterm.before
  [ unterm.md -ef unterm.link ]
}

@test "an identical duplicate is dropped" {
  mkdir -p tier
  printf -- '- [A](a.md) — x\n- [A](a.md) — x\n' > file.md
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "dropped a duplicate pointer line: - [A](a.md) — x" ]
  printf -- '- [A](a.md) — x\n' > expected.md
  cmp -s file.md expected.md
  run gitlore_compose_check_index file.md
  [ -z "$output" ]
}

# Only the SECOND path exists in the tier, so a guard keyed on the first link
# does not split; the tier directory's name holds a space.
@test "a welded line is split before the second bullet" {
  mkdir -p 'the tier'
  touch 'the tier/welded_b.md'
  printf -- '- [K](kept.md) — hook\n- [A](welded_a.md) — a- [B](welded_b.md) — b\n- [Z](zeta.md) — z\n' > file.md
  run gitlore_repair_index file.md pin.md 'the tier'
  [ "$status" -eq 0 ]
  [ "$output" = "split a welded line before welded_b.md" ]
  assert_bullets file.md \
    '- [K](kept.md) — hook' \
    '- [A](welded_a.md) — a' \
    '- [B](welded_b.md) — b' \
    '- [Z](zeta.md) — z'
  run gitlore_compose_check_index file.md
  [ -z "$output" ]
}

@test "a three-bullet weld splits twice" {
  mkdir -p tier
  touch tier/welded_b.md tier/welded_c.md
  printf -- '- [A](welded_a.md) — a- [B](welded_b.md) — b- [C](welded_c.md) — c\n' > file.md
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'split a welded line before welded_b.md\nsplit a welded line before welded_c.md')" ]
  assert_bullets file.md \
    '- [A](welded_a.md) — a' \
    '- [B](welded_b.md) — b' \
    '- [C](welded_c.md) — c'
  run gitlore_compose_check_index file.md
  [ -z "$output" ]
}

# The first path exists in the tier, so a guard keyed on the first link splits.
@test "a weld naming no file in the tier is left unchanged" {
  mkdir -p tier
  touch tier/kept.md
  printf -- '- [A](kept.md) — hook- [x](z.md)\n' > file.md
  run gitlore_compose_check_index file.md
  [[ "$output" == "file.md: line 1 welds two pointer bullets onto one line — z.md is invisible"* ]]
  cp file.md file.before
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp -s file.md file.before
}

# The escaping path exists beside the tier, so only the guard's containment
# keeps the line whole.
@test "a weld whose path climbs out of the tier is left unchanged" {
  mkdir -p tier
  touch outside.md
  printf -- '- [A](kept.md) — hook- [x](../outside.md)\n' > file.md
  run gitlore_compose_check_index file.md
  [[ "$output" == "file.md: line 1 welds two pointer bullets onto one line — ../outside.md is invisible"* ]]
  cp file.md file.before
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp -s file.md file.before
}

@test "a link the check does not report as a weld is left unchanged" {
  mkdir -p tier
  touch tier/y.md
  printf -- '- [A](kept.md) — hook with a bare [x](y.md) link\n' > file.md
  run gitlore_compose_check_index file.md
  [ -z "$output" ]
  cp file.md file.before
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  cmp -s file.md file.before
}

# The trailer opens with a blank line: the moved lines land directly after the
# last bullet, ahead of it, not after it and not at the end of the file.
@test "an interleaved non-bullet line moves to the start of the trailer" {
  mkdir -p tier
  printf -- '# Memory Index\n\n- [A](a.md) — x\nfirst stray line\nsecond stray line\n\n- [B](b.md) — y\n\nTrailing prose\n' > file.md
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'moved a non-bullet line out of the pointer block: first stray line\nmoved a non-bullet line out of the pointer block: second stray line')" ]
  printf -- '# Memory Index\n\n- [A](a.md) — x\n\n- [B](b.md) — y\nfirst stray line\nsecond stray line\n\nTrailing prose\n' > expected.md
  cmp -s file.md expected.md
  run gitlore_compose_check_index file.md
  [ -z "$output" ]
}

# The pin's only line is unterminated: a bare `read` loses it, reads the pin as
# empty, and keeps the first.
@test "a differing duplicate keeps the line the pin lacks" {
  mkdir -p tier
  printf -- '- [A](a.md) — first hook\n' > pin.md
  unterminate_index pin.md
  printf -- '- [K](k.md) — kept\n- [A](a.md) — first hook\n- [Z](z.md) — z\n- [A](a.md) — second hook\n' > file.md
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "dropped a duplicate pointer line: - [A](a.md) — first hook" ]
  assert_bullets file.md \
    '- [K](k.md) — kept' \
    '- [Z](z.md) — z' \
    '- [A](a.md) — second hook'
}

# Two lines the pin lacks: the rule picks the first of them, which a two-line
# fixture cannot tell apart from "the last" or "any".
@test "a differing duplicate: of several lines the pin lacks, the first survives" {
  mkdir -p tier
  printf -- '- [A](a.md) — first hook\n' > pin.md
  printf -- '- [A](a.md) — first hook\n- [K](k.md) — kept\n- [A](a.md) — second hook\n- [A](a.md) — third hook\n' > file.md
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'dropped a duplicate pointer line: - [A](a.md) — first hook\ndropped a duplicate pointer line: - [A](a.md) — third hook')" ]
  assert_bullets file.md \
    '- [K](k.md) — kept' \
    '- [A](a.md) — second hook'
}

@test "a differing duplicate: new to both keeps the first" {
  mkdir -p tier
  printf -- '- [B](b.md) — unrelated\n' > pin.md
  printf -- '- [A](a.md) — first hook\n- [A](a.md) — second hook\n' > file.md
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "dropped a duplicate pointer line: - [A](a.md) — second hook" ]
  assert_bullets file.md '- [A](a.md) — first hook'
}

@test "a differing duplicate: known to both keeps the first" {
  mkdir -p tier
  printf -- '- [A](a.md) — first hook\n- [A](a.md) — second hook\n' > pin.md
  printf -- '- [A](a.md) — first hook\n- [A](a.md) — second hook\n' > file.md
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "dropped a duplicate pointer line: - [A](a.md) — second hook" ]
  assert_bullets file.md '- [A](a.md) — first hook'
}

@test "a differing duplicate: a pin with no carrier keeps the first" {
  mkdir -p tier
  printf -- '- [A](a.md) — first hook\n- [A](a.md) — second hook\n' > file.md
  run gitlore_repair_index file.md missing-pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "dropped a duplicate pointer line: - [A](a.md) — second hook" ]
  assert_bullets file.md '- [A](a.md) — first hook'
}

@test "welds are split before duplicates are resolved" {
  mkdir -p tier
  touch tier/welded_a.md tier/welded_b.md
  printf -- '- [K](kept.md) — hook with trailing spaces   \n- [A](welded_a.md) — a- [B](welded_b.md) — b\n- [B](welded_b.md) — b\n- [N](enye.md) — héllo wörld\n' > file.md
  unterminate_index file.md
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'split a welded line before welded_b.md\ndropped a duplicate pointer line: - [B](welded_b.md) — b')" ]
  printf -- '- [K](kept.md) — hook with trailing spaces   \n- [A](welded_a.md) — a\n- [B](welded_b.md) — b\n- [N](enye.md) — héllo wörld' > expected.md
  cmp -s file.md expected.md
  run gitlore_compose_check_index file.md
  [ -z "$output" ]
}

# The dropped duplicate was the unterminated last line: the line before it
# becomes last and keeps the newline it had in the input.
@test "a duplicate dropped from the end terminates the new last line" {
  mkdir -p tier
  touch pin.md
  printf -- '- [K](kept.md) — kept\n- [A](a.md) — hook\n- [A](a.md) — hook\n' > file.md
  unterminate_index file.md
  [ "$(tail -c 1 file.md | wc -l)" -eq 0 ]
  [ "$(grep -c -F -- '- [A](a.md) — hook' file.md)" -eq 2 ]
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "dropped a duplicate pointer line: - [A](a.md) — hook" ]
  printf -- '- [K](kept.md) — kept\n- [A](a.md) — hook\n' > expected.md
  cmp -s file.md expected.md
}

# The last bullet was the unterminated last line and a stray moves after it:
# the stray becomes last and keeps its own newline, and the bullet — no longer
# last — gains the newline it lacked.
@test "a stray moved past an unterminated last bullet keeps its newline and terminates the bullet" {
  mkdir -p tier
  touch pin.md
  printf -- '- [A](a.md) — hook\nStray line\n- [B](b.md) — hook\n' > file.md
  unterminate_index file.md
  [ "$(tail -c 1 file.md | wc -l)" -eq 0 ]
  [ "$(wc -l < file.md)" -eq 2 ]
  [ "$(sed -n '1p' file.md)" = '- [A](a.md) — hook' ]
  [ "$(sed -n '2p' file.md)" = 'Stray line' ]
  [ "$(sed -n '3p' file.md)" = '- [B](b.md) — hook' ]
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "moved a non-bullet line out of the pointer block: Stray line" ]
  printf -- '- [A](a.md) — hook\n- [B](b.md) — hook\nStray line\n' > expected.md
  cmp -s file.md expected.md
}

# The unterminated last line is a trailer after the pointer block: the stray
# lands between the last bullet and the trailer, and the trailer stays last and
# unterminated.
@test "a stray moved ahead of an unterminated trailer leaves the trailer unterminated" {
  mkdir -p tier
  touch pin.md
  printf -- '- [A](a.md) — hook\nStray line\n- [B](b.md) — hook\n\nTrailing prose\n' > file.md
  unterminate_index file.md
  [ "$(tail -c 1 file.md | wc -l)" -eq 0 ]
  [ "$(wc -l < file.md)" -eq 4 ]
  [ "$(sed -n '5p' file.md)" = 'Trailing prose' ]
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "moved a non-bullet line out of the pointer block: Stray line" ]
  printf -- '- [A](a.md) — hook\n- [B](b.md) — hook\nStray line\n\nTrailing prose' > expected.md
  cmp -s file.md expected.md
}

# The same repair then succeeds with the directory writable and $TMPDIR not:
# the refusal came from <file>'s directory, and the scratch file lives there.
@test "a rewrite that cannot be written leaves the file unchanged" {
  [ "$(id -u)" -eq 0 ] && skip "root ignores permission bits"
  mkdir -p tier dir no-tmp
  printf -- '- [A](a.md) — x\n- [A](a.md) — x\n' > dir/file.md
  cp dir/file.md dir/file.before
  chmod a-w dir
  run gitlore_repair_index dir/file.md pin.md tier
  chmod u+w dir
  [ "$status" -eq 1 ]
  cmp -s dir/file.md dir/file.before

  chmod a-w no-tmp
  TMPDIR="$PWD/no-tmp" run gitlore_repair_index dir/file.md pin.md tier
  chmod u+w no-tmp
  [ "$status" -eq 0 ]
  [ "$output" = "dropped a duplicate pointer line: - [A](a.md) — x" ]
  printf -- '- [A](a.md) — x\n' > expected.md
  cmp -s dir/file.md expected.md
  [ "$(ls -A dir)" = "$(printf 'file.before\nfile.md')" ]
}

# The rewrite lands through a mktemp scratch, and mktemp creates 0600. The
# repaired index keeps its own mode only because the copy carries it across the
# rename — a memory index dropping to 0600 is unreadable to anything but its
# owner, and a commit records the change.
@test "a repaired index keeps the file's mode" {
  mkdir -p tier
  printf -- '- [A](a.md) — x\n- [A](a.md) — x\n' > file.md
  chmod 640 file.md
  [ "$(file_mode file.md)" = 640 ]
  run gitlore_repair_index file.md pin.md tier
  [ "$status" -eq 0 ]
  [ "$output" = "dropped a duplicate pointer line: - [A](a.md) — x" ]
  [ "$(file_mode file.md)" = 640 ]
}

# A file's permission bits in octal. The GNU form is tried first and its
# failure is the probe: BSD/macOS stat spells the same field `-f '%Lp'`.
file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}
