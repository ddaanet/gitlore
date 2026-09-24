#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/commit-memory

# What counts as an approval at commit-memory.sh's entry point: the summary a
# caller passes, and the one already on disk that a bare invocation is judged
# on. The rest of the entry point's behaviour is in commit_memory.bats.

@test "refuses dirty memory with no summary, leaving it uncommitted" {
  make_parent_with_memory
  echo dirty > memory/notes.md
  CLAUDECODE=1 run --separate-stderr bash "$CMD"
  [ "$status" -eq 1 ]
  [[ "${output}${stderr}" == *"approved summary"* ]] || \
    [[ "${output}${stderr}" == *"-m"* ]]
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

