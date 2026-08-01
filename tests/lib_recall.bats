#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

SESSION="s-1"

setup() {
  setup_tmp_repo
  make_parent_with_memory
  printf 'body of A\n' > memory/feedback_a.md
  printf 'body of B\n' > memory/feedback_b.md
  mkdir -p memory/tier
  printf 'body of T\n' > memory/tier/reference_t.md
}
teardown() { teardown_tmp_repo; }

req() { printf '%s' "$1" > "$(gitlore_recall_file memory)"; }

@test "resolve returns the bodies and names their paths" {
  req 'feedback_a.md
feedback_b.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"body of A"* ]]
  [[ "$output" == *"body of B"* ]]
  [[ "$output" == *"memory/feedback_a.md"* ]]
  [[ "$output" == *"Do NOT Read these files"* ]]
}

@test "the memory/ spelling resolves too" {
  req 'memory/feedback_a.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"body of A"* ]]
}

@test "a tier path resolves" {
  req 'tier/reference_t.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"body of T"* ]]
}

@test "no match is a valid answer and fetches nothing" {
  req 'no match'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 0 ]
  [ "$output" = "no match" ]
}

@test "over the cap is a hard failure that reads nothing" {
  req 'feedback_a.md
feedback_a.md
feedback_a.md
feedback_a.md
feedback_a.md
feedback_a.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"6 entries"* ]]
  [[ "$output" == *"limit of 5"* ]]
  [[ "$output" == *"more specific"* ]]
  [[ "$output" != *"body of A"* ]]
}

@test "a problem report never claims nothing was read — that is the banner's clause" {
  # Each refusal path, so a new message cannot reintroduce the doubling.
  req 'feedback_nope.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "${output,,}" != *"${GITLORE_T_NOTHING_READ,,}"* ]]
  [[ "$output" == "The request names"* ]]

  req 'feedback_a.md
feedback_a.md
feedback_a.md
feedback_a.md
feedback_a.md
feedback_a.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "${output,,}" != *"${GITLORE_T_NOTHING_READ,,}"* ]]
  [[ "$output" == "The request lists"* ]]

  req '
   '
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "${output,,}" != *"${GITLORE_T_NOTHING_READ,,}"* ]]
  [[ "$output" == "The request is empty"* ]]

  req 'no match
feedback_a.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "${output,,}" != *"${GITLORE_T_NOTHING_READ,,}"* ]]
  [[ "$output" == "The request mixes"* ]]
}

@test "exactly the cap is accepted" {
  req 'feedback_a.md
feedback_b.md
tier/reference_t.md
feedback_a.md
feedback_b.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 0 ]
}

@test "an unknown name is rejected by name and nothing is read" {
  req 'feedback_a.md
feedback_nope.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such memory file: feedback_nope.md"* ]]
  [[ "$output" != *"body of A"* ]]
}

@test "path escape and absolute paths are refused" {
  req '../../etc/passwd'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"escapes the memory store"* ]]

  req '/etc/passwd'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"absolute path not allowed"* ]]
}

@test "mixing no match with paths is refused" {
  req 'no match
feedback_a.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"one or the other"* ]]
}

@test "an empty request is refused" {
  req '
   '
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 1 ]
  [[ "$output" == *"empty"* ]]
}

@test "a body already fetched this session is skipped, not re-sent" {
  req 'feedback_a.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"body of A"* ]]

  req 'feedback_a.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already in this context"* ]]
  [[ "$output" != *"body of A"* ]]
}

@test "an edited memory is re-sent even though its path was read" {
  req 'feedback_a.md'
  run gitlore_recall_resolve memory "$SESSION"
  [[ "$output" == *"body of A"* ]]

  printf 'body of A, revised\n' > memory/feedback_a.md
  req 'feedback_a.md'
  run gitlore_recall_resolve memory "$SESSION"
  [ "$status" -eq 0 ]
  [[ "$output" == *"body of A, revised"* ]]
}

@test "the ledger is per session" {
  gitlore_recall_record memory "$SESSION" feedback_a.md
  run gitlore_recall_known memory "$SESSION" feedback_a.md
  [ "$status" -eq 0 ]
  run gitlore_recall_known memory "other-session" feedback_a.md
  [ "$status" -eq 1 ]
}

@test "reset clears the ledger so a compaction re-fetches" {
  gitlore_recall_record memory "$SESSION" feedback_a.md
  run gitlore_recall_known memory "$SESSION" feedback_a.md
  [ "$status" -eq 0 ]

  gitlore_recall_reset memory "$SESSION"
  run gitlore_recall_known memory "$SESSION" feedback_a.md
  [ "$status" -eq 1 ]
}

@test "the ledger lives in the gitdir, so it never dirties memory" {
  gitlore_recall_record memory "$SESSION" feedback_a.md
  # There IS a ledger, and it is in the gitdir: without this the absence check
  # below passes just as well when the record was never written anywhere.
  run gitlore_recall_known memory "$SESSION" feedback_a.md
  [ "$status" -eq 0 ]
  run git -C memory status --porcelain
  [[ "$output" != *"gitlore-recall"* ]]
}

@test "a path containing spaces survives the ledger round trip" {
  printf 'spaced body\n' > "memory/a file.md"
  gitlore_recall_record memory "$SESSION" "a file.md"
  run gitlore_recall_known memory "$SESSION" "a file.md"
  [ "$status" -eq 0 ]
}

@test "the recall file sits in the parent .claude, not the submodule" {
  run gitlore_recall_file memory
  [ "$status" -eq 0 ]
  [ "$output" = "$TMP_REPO/.claude/gitlore-recall" ]
}
