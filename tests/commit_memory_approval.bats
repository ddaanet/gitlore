#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/commit-memory
load helpers/tier-fixtures

# What counts as an approval at commit-memory.sh's entry point: the summary a
# caller passes, and the one already on disk that a bare invocation is judged
# on. The rest of the entry point's behaviour is in commit_memory.bats.

@test "refuses dirty memory with no summary, leaving it uncommitted" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  # The entry point's own directive, not the sync's refusal the bare path routes
  # a present file to — that one also names `gitlore-memory-message`.
  [[ "${output}${stderr}" == *"Pass it with -m"* ]]
  [[ "${output}${stderr}" != *"no approved commit summary"* ]]
  [ -n "$(git -C memory status --porcelain)" ]   # still dirty, nothing committed
}

@test "bare invocation commits on a fresh approval file and consumes it" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  mkdir -p "$(dirname "$msgfile")"
  printf 'memory: add notes\n' > "$msgfile"
  head_before=$(git -C memory rev-parse HEAD)

  run bash "$CMD"
  [ "$status" -eq 0 ]

  # A clean tree and HEAD = live are also what discarding the edit would leave,
  # so HEAD has to have moved; the subject is what ties the commit made to the
  # approval file on disk rather than to any summary the run composed itself.
  [ -z "$(git -C memory status --porcelain)" ]
  wt=$(git -C memory rev-parse HEAD)
  live=$(git -C memory rev-parse live)
  [ "$wt" != "$head_before" ]
  [ "$wt" = "$live" ]
  [ "$(git -C memory log -1 --pretty=%s)" = "memory: add notes" ]
  [ ! -f "$msgfile" ]
}

@test "bare invocation refuses a stale approval file and leaves it" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  mkdir -p "$(dirname "$msgfile")"
  printf 'memory: add notes\n' > "$msgfile"
  # BSD-portable backdate; mtime is second-granular and the freshness compare
  # is `>=`, so backdating is what makes the approval strictly older.
  touch -t 200001010000 "$msgfile"
  cp "$msgfile" "$BATS_TEST_TMPDIR/approval.before"
  head_before=$(git -C memory rev-parse HEAD)
  # Whole-second mtimes: the marker sits a second before the run, so a restamp
  # of the approval — the minting this bare mode must not do — leaves it newer.
  : > "$TMP_REPO/before-run"
  sleep 1

  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"no approved commit summary"* ]]
  # The usage-era refusal's own operand, and not a bare `-m`: the sync's refusal
  # names $msgfile, whose basename `gitlore-memory-message` contains `-m`.
  [[ "${output}${stderr}" != *"Pass it with -m"* ]]
  [ -n "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ -f "$msgfile" ]
  cmp -s "$msgfile" "$BATS_TEST_TMPDIR/approval.before"
  [ ! "$msgfile" -nt "$TMP_REPO/before-run" ]
}

@test "bare invocation refuses an empty approval file as no approval at all" {
  # An empty file is fresh by mtime, so only the entry point's own screen keeps
  # it from reaching `git commit -F` and git's own empty-message abort.
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  mkdir -p "$(dirname "$msgfile")"
  : > "$msgfile"
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"Pass it with -m"* ]]
  [[ "${output}${stderr}" != *"empty commit message"* ]]
  [ -n "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "bare invocation refuses a blank approval file, which -s alone admits" {
  # Whitespace makes the file non-empty, so `-s` passes it through to
  # `git commit -F`, which rejects it as an empty message on an arm that
  # restamps the approval — the refusal then repeats on every retry.
  make_parent_with_memory
  echo dirty > memory/notes.md
  msgfile=$(gitlore_commit_msg_file memory)
  mkdir -p "$(dirname "$msgfile")"
  printf '\n  \n\t\n' > "$msgfile"
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"Pass it with -m"* ]]
  [[ "${output}${stderr}" != *"empty commit message"* ]]
  [ -n "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "a store mid-merge is answered with the merge directive, not a summary request" {
  # A prepared merge makes the store dirty by construction and consumed whatever
  # approval preceded it, so the no-summary screen is what this shape reaches
  # first — and it would put a merge both of whose sides are already approved
  # (D49) in front of the user as a summary to draft. The dirty file added after
  # the preparation is what keeps the screen in play: without it the sync's own
  # guard would speak whether or not the screen is ordered behind one.
  make_parent_with_memory
  advance_branch_with_file memory live LIVE.md live-only "Diverging commit on live"
  echo dirty > memory/notes.md
  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: add notes"
  [ "$status" -eq 1 ]
  [ -f "$(gitlore_merge_state_file memory)" ]   # the store is mid-merge
  echo more > memory/notes2.md
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory merge prepared"* ]]
  [[ "${output}${stderr}" != *"Pass it with -m"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ ! -f "$(gitlore_commit_msg_file memory)" ]
}

@test "-m with a blank summary refuses instead of dying on git's empty message" {
  # The arg-driven path writes whatever it is handed, so the screen has to sit
  # after that write: `-m ""` becomes a one-byte file, and `-F -` over empty
  # stdin the same.
  make_parent_with_memory
  echo dirty > memory/notes.md
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "   "
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"approved summary"* ]]
  [[ "${output}${stderr}" != *"empty commit message"* ]]
  [ -n "$(git -C memory status --porcelain)" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "a tier mid-merge is answered with the merge directive, not a summary request" {
  # The sibling of the root-store case above, with a tier's own divergence in
  # place of root's: commit-memory.sh's own stale-merge guard only checks the
  # root store, so a tier holding a prepared merge with nothing on disk to
  # approve reaches the "Pass it with -m" screen instead of the merge
  # directive — asking for a summary that would not help, since the guard
  # refuses on the merge regardless.
  make_parent_with_memory
  make_tier_in_memory ddaanet
  set_tier_manifest ddaanet
  git -C memory/ddaanet fetch -q origin "live:live"
  git -C memory/ddaanet checkout -q --detach live
  advance_branch_with_file "memory/ddaanet" live other.md body "sideways" live
  echo "- [org fact](f.md) — ours" >> memory/ddaanet/MEMORY.md

  CLAUDECODE=1 run --separate-stderr bash "$CMD" -m "memory: add notes"
  [ "$status" -eq 1 ]
  [ -n "$(git -C memory/ddaanet rev-parse -q --verify MERGE_HEAD)" ]   # the tier is mid-merge
  # The `-m` above leaves its approval file on disk, unconsumed (the root
  # commit that would remove it never ran); dropped here so the run under test
  # meets a tier mid-merge with no approval file, the shape the defect names.
  rm -f "$(gitlore_commit_msg_file memory)"
  echo more > memory/notes2.md
  head_before=$(git -C memory rev-parse HEAD)

  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"memory merge prepared"* ]]
  [[ "${output}${stderr}" != *"Pass it with -m"* ]]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "the usage line names the bare invocation" {
  # Bare (no -m/-F) is a documented first-class mode — the shape the batch
  # hook always calls — and the usage string only ever lists the arg-driven
  # forms.
  CLAUDECODE=1 run --separate-stderr bash "$CMD" -x
  [ "$status" -eq 2 ]
  [[ "${output}${stderr}" == *bare* ]]
}
