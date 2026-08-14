#!/usr/bin/env bats
# The pre/post expectation pair that contains Claude Code's `Edit` weld defect
# (D23). Deleting a match that starts with a newline drops the separator on both
# sides, so one deleted line costs two newlines and its neighbours join.
#
# Every assertion here compares whole files, never `$(...)` captures: the defect
# IS a missing newline, and command substitution strips exactly the byte in
# question.

bats_require_minimum_version 1.5.0

load helpers/setup

setup() {
  setup_tmp_repo
  export TMPDIR="$TMP_REPO/tmp"
  mkdir -p "$TMPDIR"
}
teardown() { teardown_tmp_repo; }

# Write a plan field to a file so it can be compared byte-for-byte.
field() {   # $1 = plan JSON, $2 = field, $3 = output path
  printf '%s' "$1" | jq -j ".$2" > "$3"
}

# --- gitlore_weld_plan: what the edit asked for, and what the defect makes ---

@test "plan splits a weldable deletion into the intended and welded results" {
  printf 'A\nX\nB\n' > f
  plan=$(gitlore_weld_plan f $'\nX')
  field "$plan" orig got_orig; printf 'A\nX\nB\n' > want_orig
  field "$plan" exp  got_exp;  printf 'A\nB\n'    > want_exp
  field "$plan" weld got_weld; printf 'AB\n'      > want_weld
  cmp got_orig want_orig
  cmp got_exp  want_exp
  cmp got_weld want_weld
}

@test "plan refuses a match that does not begin with a newline" {
  # `"X"` -> `""` is the correct row of the table: Edit removes the emptied
  # line and its own trailing newline, and nothing welds.
  printf 'A\nX\nB\n' > f
  run ! gitlore_weld_plan f 'X'
  [ -z "$output" ]
}

@test "plan refuses a match that no newline follows" {
  # The tail of the file. There is no trailing separator left to lose, so Edit
  # is correct here — arming would invite a repair where nothing broke. Two of
  # the three leading-newline deletions in the local corpus are this shape.
  printf 'A\nX\nB\n' > f
  run ! gitlore_weld_plan f $'\nB\n'
  [ -z "$output" ]
}

@test "plan refuses a match the file does not contain" {
  printf 'A\nX\nB\n' > f
  run ! gitlore_weld_plan f $'\nZ'
  [ -z "$output" ]
}

@test "plan handles a deletion whose own text ends with a newline" {
  # `old_string` covering the separator on both sides. The match still has a
  # newline after it, so the weld is live and the arithmetic must not assume
  # the match ends mid-line.
  printf 'A\nX\n\nB\n' > f
  plan=$(gitlore_weld_plan f $'\nX\n')
  field "$plan" exp  got_exp;  printf 'A\nB\n' > want_exp
  field "$plan" weld got_weld; printf 'AB\n'   > want_weld
  cmp got_exp  want_exp
  cmp got_weld want_weld
}

@test "plan counts multi-byte text by the same measure as it slices" {
  # jq indexes strings by codepoint. A byte-oriented offset would cut inside
  # the em dash and produce a plan that can never match the file.
  printf '— é A\n— X\n— B\n' > f
  plan=$(gitlore_weld_plan f $'\n— X')
  field "$plan" exp  got_exp;  printf '— é A\n— B\n' > want_exp
  field "$plan" weld got_weld; printf '— é A— B\n'   > want_weld
  cmp got_exp  want_exp
  cmp got_weld want_weld
}

@test "plan preserves a file whose final line is unterminated" {
  printf 'A\nX\nB' > f
  plan=$(gitlore_weld_plan f $'\nX')
  field "$plan" exp  got_exp;  printf 'A\nB' > want_exp
  field "$plan" weld got_weld; printf 'AB'   > want_weld
  cmp got_exp  want_exp
  cmp got_weld want_weld
}

@test "plan matches the FIRST occurrence, as Edit does" {
  printf 'A\nX\nB\nX\nC\n' > f
  plan=$(gitlore_weld_plan f $'\nX')
  field "$plan" weld got_weld; printf 'AB\nX\nC\n' > want_weld
  cmp got_weld want_weld
}

# --- gitlore_weld_verdict: the four outcomes, told apart by bytes -------------

verdict_for() {   # $1 = bytes the file holds afterwards
  printf 'A\nX\nB\n' > f
  gitlore_weld_plan f $'\nX' > state
  printf '%s' "$1" > f
  gitlore_weld_verdict state f
}

@test "verdict reads the welded bytes as a repair" {
  run verdict_for 'AB
'
  [ "$output" = repair ]
}

@test "verdict reads the intended bytes as clean" {
  # The retirement signal: Edit did the right thing on a shape that can weld.
  run verdict_for 'A
B
'
  [ "$output" = clean ]
}

@test "verdict reads an untouched file as unchanged" {
  # A refused, denied or non-matching Edit leaves the file alone. Writing the
  # expectation over it would apply a deletion the tool declined to make.
  run verdict_for 'A
X
B
'
  [ "$output" = unchanged ]
}

@test "verdict reads anything else as unknown" {
  run verdict_for 'something else entirely'
  [ "$output" = unknown ]
}

# --- gitlore_weld_repair -----------------------------------------------------

@test "repair writes the intended result over the welded file" {
  printf 'A\nX\nB\n' > f
  gitlore_weld_plan f $'\nX' > state
  printf 'AB\n' > f
  gitlore_weld_repair state f
  printf 'A\nB\n' > want
  cmp f want
}

@test "repair keeps the target's mode and leaves no scratch file behind" {
  # The target may sit in the memory worktree, where an untracked leftover is
  # swept into the FR11 gate's `git add -A`.
  printf 'A\nX\nB\n' > f
  chmod 640 f
  gitlore_weld_plan f $'\nX' > state
  printf 'AB\n' > f
  gitlore_weld_repair state f
  run stat -c '%a' f
  [ "$output" = 640 ]
  run find . -name '*gitlore-weld*'
  [ -z "$output" ]
}

# --- state file --------------------------------------------------------------

@test "state file is per session and per target, under TMPDIR" {
  a=$(gitlore_weld_state_file sess-1 /some/file.md)
  b=$(gitlore_weld_state_file sess-2 /some/file.md)
  c=$(gitlore_weld_state_file sess-1 /other/file.md)
  [ "$a" != "$b" ]
  [ "$a" != "$c" ]
  [[ "$a" == "$TMPDIR"/* ]]
  # Recomputed identically by the post hook, which is the only reason it works.
  [ "$a" = "$(gitlore_weld_state_file sess-1 /some/file.md)" ]
}

@test "state file name survives a session id and a path carrying spaces" {
  a=$(gitlore_weld_state_file 'a b' '/some dir/file.md')
  [ -n "$a" ]
  [[ "$a" != *' '* ]]
}
