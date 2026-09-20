#!/usr/bin/env bats
# Relay markers (D51): a subagent's report is a write-once file keyed by
# session AND agent, never merged, and drained by session. Continues in
# tests/index_sync_relay_refusals.bats.

load helpers/setup
load helpers/fixtures
load helpers/index-sync

# shellcheck disable=SC1090
setup() { setup_tmp_repo; . "$SRC"; }
teardown() { teardown_tmp_repo; }

# --- relay markers (D51) -------------------------------------------------------
#
# A subagent's report is a write-once file keyed by session AND agent, never
# merged, and drained by session. Two channels — sysmsg is the user's, ctx is
# the model's — must not cross-contaminate on drain. Cases 1-3 catch the
# three defects of a relay keyed on the agent alone: a second write merged
# into the first, lost reports under concurrent writers, and a drain blind to
# its session. No case predicts a relay filename from outside the writing
# process; they locate files with `find`.

# 1: two writes under one agent in one session yield two files; the drain
# frames both, in write order, and removes both.
@test "relay_write: two writes under one agent in one session yield two files, drained together in write order" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  run gitlore_relay_write memory s1 a-1 sync "S1" "C1"
  [ "$status" -eq 0 ]
  # A whole second between the two writes, not a stylistic pause. The design
  # fixes the filename as `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>`, so two
  # writes that agree on session, agent, tag AND wall-clock second collide on
  # one name, and D51 refuses an install onto an occupied path. Production
  # cannot produce that collision — the two writers are separate hook
  # processes carrying different pids and different tags — but this case
  # drives both writes from one shell, so it has to separate them on the one
  # field it controls. That same field is what the order assertion below
  # rests on: filename order is write order only because the epochs differ.
  sleep 1
  run gitlore_relay_write memory s1 a-1 sync "S2" "C2"
  [ "$status" -eq 0 ]

  # Two files on disk before the drain removes them — red on a relay keyed on
  # the agent id alone, which merges a second write into the first.
  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print0)
  [ "$count" -eq 2 ]

  rc=0
  gitlore_relay_drain memory s1 || rc=$?
  [ "$rc" -eq 0 ]
  # Two separate framing lines for a-1, not one — a merge into a single file
  # frames only once no matter how many bodies land in it. `-x`: the frame is
  # the whole line `--- gitlore-relay agent a-1 ---`, and a substring match
  # would also accept a frame carrying the session, epoch or tag alongside
  # the agent id, which is not the format D51 states. The agent id carries a
  # dash on purpose: D51 recovers `A` from the filename by stripping the
  # known `gitlore-relay-<S>-` prefix and the three trailing `-<epoch>-<pid>-<H>`
  # fields, and calls that unambiguous for a dashed id. Nothing else in the
  # slice exercises that claim, and the plausible wrong recovery — cutting at
  # the first dash — frames `a` here instead.
  run grep -c -x -- '--- gitlore-relay agent a-1 ---' <<<"$GITLORE_RELAY_SYSMSG"
  [ "$output" -eq 2 ]
  # Order, not mere presence.
  [[ "$GITLORE_RELAY_SYSMSG" == *"S1"*"S2"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"C1"*"C2"* ]]

  # ...and both files are gone.
  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' -print0)
  [ "$count" -eq 0 ]
}

# 2 (C2): 20 gitlore_relay_write calls for one agent in parallel, one drain —
# every body must survive. Red on the merge-write stub regardless of the
# renumbering above: a shared, read-modify-written file loses most of 20
# racing installs, the same shape the deliverable review measured at 86 lost
# reports in 200 runs of two concurrent writers.
#
# The writers are separate `bash -c` PROCESSES, not `foo &` subshells of this
# test's shell. D51 discriminates two same-second writes by the writer's pid,
# and `$$` is fixed at shell startup: every `&` subshell of one shell reports
# the same `$$`, and `$BASHPID` — the only per-subshell alternative — does not
# exist on bash 3.2, which is a target. Backgrounded subshells would therefore
# make this case fail on GREEN for a reason production never has, since in
# production each writer is its own hook process. Spawning processes
# reproduces the guarantee the design actually rests on.
@test "relay_write: 20 concurrent writes for one agent are not lost by the drain" {
  make_parent_with_memory

  for i in $(seq 1 20); do
    bash -c '
      set -euo pipefail
      # shellcheck disable=SC1090
      . "$1"
      gitlore_relay_write "$2" s1 a1 sync "SYS-$3" "CTX-$3"
    ' _ "$SRC" "$PWD/memory" "$i" &
  done
  # Bare `wait` returns 0 whatever the children returned, so a writer that
  # failed is not reported here. That is deliberate: the contract under test
  # is what the drain recovers, and a per-writer status check would red this
  # case on the writers' own exits before the recovery assertion below ever
  # ran. A lost write shows up as a missing body either way.
  wait

  rc=0
  gitlore_relay_drain memory s1 || rc=$?
  [ "$rc" -eq 0 ]

  # `-x`, the whole framing line — see case 1.
  run grep -c -x -- '--- gitlore-relay agent a1 ---' <<<"$GITLORE_RELAY_SYSMSG"
  [ "$output" -eq 20 ]
  for i in $(seq 1 20); do
    # `-x`, exact full-line match: a substring check on "SYS-$i" alone would
    # count "SYS-1" as present whenever "SYS-10".."SYS-19" survived instead.
    run grep -c -x -- "SYS-$i" <<<"$GITLORE_RELAY_SYSMSG"
    [ "$output" -eq 1 ]
    run grep -c -x -- "CTX-$i" <<<"$GITLORE_RELAY_CTX"
    [ "$output" -eq 1 ]
  done
}

# 3: a write for session S2 is not drained by S1 and survives it. Different
# agent ids for the two sessions, so even an agent-keyed write creates two
# distinct files (no cross-write merge muddying this case) — the only defect
# this case can catch is the drain's blindness to its own session argument.
@test "relay_drain: a write for session S2 is not drained by S1 and survives it" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  run gitlore_relay_write memory s1 a1 sync "S1-BODY" "C1-BODY"
  [ "$status" -eq 0 ]
  run gitlore_relay_write memory s2 a2 sync "S2-BODY" "C2-BODY"
  [ "$status" -eq 0 ]

  rc=0
  gitlore_relay_drain memory s1 || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"S1-BODY"* ]]
  [[ "$GITLORE_RELAY_SYSMSG" != *"S2-BODY"* ]]

  # The S2 write is untouched by S1's drain — red on a drain that ignores the
  # session argument and drains every relay file it finds, whichever session
  # it was written for.
  count=0
  while IFS= read -r -d '' _; do
    count=$((count + 1))
  done < <(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print0)
  [ "$count" -eq 1 ]

  rc=0
  gitlore_relay_drain memory s2 || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"S2-BODY"* ]]
}

# 4: a .tmp beside the markers is neither folded nor removed by the drain
# (the unlink-between-read-and-rm half is settled by construction — unique
# names — and has no test). Over a gitdir path holding a space, per the
# whitespace-safety rule: this is the only case in the new section that
# builds a fixture out of line, so it is the one that reuses the shape.
@test "relay_drain: a .tmp beside the markers is neither folded nor removed, over a gitdir path holding a space" {
  root="$TMP_REPO/has space"
  _gitlore_build_parent_with_memory "$root" memory
  mem="$root/memory"
  gitdir=$(git -C "$mem" rev-parse --absolute-git-dir)
  case "$gitdir" in
    *\ *) : ;;                             # the fixture really is spaced
    *) echo "fixture gitdir path has no space" >&2; return 1 ;;
  esac

  run gitlore_relay_write "$mem" s1 a1 sync "S1" "C1"
  [ "$status" -eq 0 ]
  tmp="$gitdir/gitlore-relay-s1-orphan-9999999999-99999-sync.tmp"
  {
    printf -- '--- gitlore-relay-sysmsg ---\n'
    printf 'TORN-BODY\n'
  } > "$tmp"

  rc=0
  gitlore_relay_drain "$mem" s1 || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"S1"* ]]
  [[ "$GITLORE_RELAY_SYSMSG" != *"TORN-BODY"* ]]
  [[ "$GITLORE_RELAY_SYSMSG" != *"orphan"* ]]
  [ -e "$tmp" ]
  # Each half is shown to discriminate by mutation. Dropping `'!' -name
  # '*.tmp'` from the drain's `find` reds the TORN-BODY assertion; adding
  # `rm -f "$gitdir"/gitlore-relay-*.tmp` to the drain — the plausible "clean
  # up strays" form — reds `[ -e "$tmp" ]`. One mutation per half, so neither
  # is decoration.
}

# The write and the drain must agree on the gitdir whatever shape it has. A
# store whose `.git` is a directory — a plain clone, never an absorbed
# submodule — makes `rev-parse --git-path` print a path relative to the
# store, which the write would then open relative to the caller's cwd: the
# report lands in some other gitdir and the drain, looking in the store's
# absolute one, never sees it. Driven from the root of another repository,
# as a hook runs from the project root.
@test "relay_write lands where the drain looks for a store whose .git is a directory" {
  git init -q plain
  [ -d plain/.git ]

  run gitlore_relay_write plain s1 a1 sync "PLAIN-BODY" "PLAIN-CTX"
  [ "$status" -eq 0 ]

  rc=0
  gitlore_relay_drain plain s1 || rc=$?
  [ "$rc" -eq 0 ]
  [[ "$GITLORE_RELAY_SYSMSG" == *"PLAIN-BODY"* ]]
  [[ "$GITLORE_RELAY_CTX" == *"PLAIN-CTX"* ]]
  run find .git -maxdepth 1 -name 'gitlore-relay-*'
  [ -z "$output" ]
}

# 5: the sweep removes relay files older than 7 days, temps included, and
# leaves fresh ones alone. Red on a sweep that does nothing: the aged marker
# is never removed.
@test "relay_sweep: removes relay files older than 7 days, temps included, and leaves fresh ones alone" {
  make_parent_with_memory
  gitdir=$(git -C memory rev-parse --absolute-git-dir)

  run gitlore_relay_write memory s1 a1 sync "OLD" "OLD-C"
  [ "$status" -eq 0 ]
  old=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' -print)
  [ -n "$old" ]
  # BSD `date -v` first; GNU has no `-v` and errors on it, so the `||` falls
  # back to `-d` — provoking the platform mismatch is the detection
  # mechanism, not a routine failure suppression.
  old_ts=$(date -v-10d +%Y%m%d%H%M 2>/dev/null || date -d '10 days ago' +%Y%m%d%H%M)
  touch -t "$old_ts" "$old"
  old_tmp="$old.tmp"
  printf 'STALE-TMP\n' > "$old_tmp"
  touch -t "$old_ts" "$old_tmp"

  run gitlore_relay_write memory s1 a2 sync "FRESH" "FRESH-C"
  [ "$status" -eq 0 ]
  fresh=$(find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' '!' -name '*.tmp' '!' -path "$old" -print)
  [ -n "$fresh" ]

  fresh_tmp="$fresh.tmp"
  printf 'LIVE-TMP\n' > "$fresh_tmp"

  run gitlore_relay_sweep memory
  [ "$status" -eq 0 ]
  [ ! -e "$old" ]
  # Fails on a sweep that ignores age and clears the directory.
  [ -e "$fresh" ]
  # The `.tmp` exclusion is a DRAIN rule — a temp must never be folded as a
  # report — not a sweep rule: a temp stranded by a killed writer is collected
  # by age like any other relay file, or it would never be collected at all.
  # Fails on a sweep that carries the drain's `'!' -name '*.tmp'` over.
  [ ! -e "$old_tmp" ]
  # Fails on a sweep that removes every `.tmp` regardless of age — one a
  # writer is still filling.
  [ -e "$fresh_tmp" ]
}
