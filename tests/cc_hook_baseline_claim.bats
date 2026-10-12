#!/usr/bin/env bats
# index-sync-post.sh and index-compose.sh each consume one baseline file — the
# pre-hook's stash and its stamp. They claim it by renaming it to `<name>.$$`
# before reading, so that a second copy of the hook, or index-sync-pre.sh, sees
# no baseline while the first is mid-read, and so a death leaves nothing behind
# under either name. The cases below are the same five postconditions for both.
# feed() and sync_feed() take an optional agent id, which SC2119/SC2120 flag at
# the bare call sites.
# `status` is set by `run` in each test and read by the shared assert helpers.
# shellcheck disable=SC2119,SC2120,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/cc-hook-index-compose
load helpers/hook-guard

# A stale frontmatter, the stash holding the old index line and MEMORY.md the
# new one: the post hook has exactly one description to propagate.
sync_fixture() {
  printf -- '---\ndescription: stale\n---\n' > memory/a.md
  STASH=$(gitlore_index_preimage_file memory)
  printf -- '- [A](a.md) — old\n' > "$STASH"
  printf -- '- [A](a.md) — new\n' > memory/MEMORY.md
}

# A tier bullet awaiting composition, a stamp taken before the root index moved,
# then the move.
compose_fixture() {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  pre "$PWD/memory/MEMORY.md"
  STAMP=$(gitlore_compose_stamp_file memory)
  [ -f "$STAMP" ]
  seed_root_fact p.md "a project fact"
}

# Every file at baseline path $1 or claimed copy of it, one per line. The pattern
# is `<name>` or `<name>.*` as a find -name, so it is whitespace-safe and a keyed
# baseline of another agent (`<name>-<agent>`, joined by `-`) is not matched.
# Only call it after $1 existed, which is what proves its directory is there.
baseline_leftovers() {
  find "$(dirname "$1")" -maxdepth 1 \
    \( -name "$(basename "$1")" -o -name "$(basename "$1").*" \) -print
}

# A baseline of another agent, which a main-thread hook must neither consume nor
# count as its own claimed copy.
keyed_baseline() {
  KEYED="$1-a1"
  printf 'subagent baseline\n' > "$KEYED"
}

# Runs the command given with $STUBS first on PATH, for that command alone.
with_stubs() { PATH="$STUBS:$PATH" "$@"; }

# Writes $STUBS/$1 with body $2. A stub that wraps the real tool has its absolute
# path baked into the body by the caller, through $(command -v …).
make_stub() {
  STUBS="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUBS"
  printf '#!/usr/bin/env bash\n%s\n' "$2" > "$STUBS/$1"
  chmod 755 "$STUBS/$1"
}

# --- (a) no baseline: quiet success -------------------------------------------

@test "sync: no stash is a silent exit 0" {
  sync_fixture
  rm -f "$STASH"
  run --separate-stderr sync_feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: stale' ]
}

@test "compose: no stamp is a silent exit 0" {
  seed_tier_bullet ddaanet shared.md "a portable fact"
  seed_root_fact p.md "a project fact"   # changed, but no watched call ran
  run --separate-stderr feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  run -1 grep -qF 'ddaanet/shared.md' memory/MEMORY.md
}

# --- (b) a baseline is consumed once and leaves no claimed copy -----------------

@test "sync: one propagation, and neither the stash nor a claimed copy is left" {
  sync_fixture
  keyed_baseline "$STASH"
  run --separate-stderr sync_feed
  [ "$status" -eq 0 ]
  [ "$(jq -s 'length' <<<"$output")" = 1 ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: "new"' ]
  [ -z "$(baseline_leftovers "$STASH")" ]
  [ -f "$KEYED" ]
}

@test "compose: one compose, and neither the stamp nor a claimed copy is left" {
  compose_fixture
  keyed_baseline "$STAMP"
  run --separate-stderr feed
  [ "$status" -eq 0 ]
  [ "$(jq -s 'length' <<<"$output")" = 1 ]
  grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  [ -z "$(baseline_leftovers "$STAMP")" ]
  [ -f "$KEYED" ]
}

# --- (c) a death after the claim leaves nothing under either name ---------------

@test "sync: a death reading the stash leaves neither the stash nor a claimed copy" {
  [ "$(id -u)" -ne 0 ] || skip "root reads a mode-000 file"
  sync_fixture
  chmod 000 "$STASH"
  run --separate-stderr sync_feed
  assert_hook_died index-sync-post 2 "not synced"
  [ -z "$(baseline_leftovers "$STASH")" ]
}

@test "compose: a death reading the stamp leaves neither the stamp nor a claimed copy" {
  [ "$(id -u)" -ne 0 ] || skip "root reads a mode-000 file"
  compose_fixture
  chmod 000 "$STAMP"
  run --separate-stderr feed
  assert_hook_died index-compose 1 "not recomposed"
  [ -z "$(baseline_leftovers "$STAMP")" ]
}

# --- (d) the baseline vanishing before the claim --------------------------------

# The stub stands in for the race: another copy of the hook renamed the baseline
# between this copy's `[ -f ]` test and its own claim, so its `mv` finds nothing.
# It removes its source operand, says what a real `mv` says about a vanished
# source and fails: the state that race leaves, and the diagnostic a claim must
# not let through. It logs its arguments, so a hook that never claims through
# `mv` on PATH cannot pass.
make_vanishing_mv() {
  MVLOG="$BATS_TEST_TMPDIR/mv.log"
  make_stub mv "printf '%s\n' \"\$*\" >> '$MVLOG'
for a in \"\$@\"; do
  case \$a in -*) ;; *)
    rm -f -- \"\$a\"
    printf 'mv: %s: No such file or directory\\n' \"\$a\" >&2
    exit 1 ;;
  esac
done
exit 1"
}

@test "sync: a stash that vanishes before the claim is a silent exit 0" {
  sync_fixture
  make_vanishing_mv
  run --separate-stderr with_stubs sync_feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  run grep '^description:' memory/a.md
  [ "$output" = 'description: stale' ]
  grep -qF -- "$STASH" "$MVLOG"
}

@test "compose: a stamp that vanishes before the claim is a silent exit 0" {
  compose_fixture
  make_vanishing_mv
  run --separate-stderr with_stubs feed
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  run -1 grep -qF 'ddaanet/shared.md' memory/MEMORY.md
  grep -qF -- "$STAMP" "$MVLOG"
}

# --- (e) the claim is observable: the unclaimed name is gone while reading ------

# A stub for a tool the hook runs after the claim: it logs whether the unclaimed
# baseline exists at that moment, then runs the real tool on the same arguments.
# What index-sync-pre.sh and a second copy of the hook would see is exactly that.

@test "sync: the stash name does not exist while the hook compares it" {
  sync_fixture
  make_stub cmp "if [ -e '$STASH' ]; then s=present; else s=absent; fi
printf '%s\n' \"\$s\" >> '$BATS_TEST_TMPDIR/seen.log'
exec '$(command -v cmp)' \"\$@\""
  run --separate-stderr with_stubs sync_feed
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/seen.log" ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/seen.log")" = absent ]
}

# The stamp is read by awk with the stamp itself on stdin, so the stub tells
# that call by its first stdin line (`index<TAB>…`), not by the program text.
@test "compose: the stamp name does not exist while the hook reads it" {
  compose_fixture
  make_stub awk "in=\$(mktemp \"\${TMPDIR:-/tmp}/awk-in.XXXXXX\")
cat > \"\$in\"
IFS= read -r first < \"\$in\" || true
case \$first in
  index*)
    if [ -e '$STAMP' ]; then s=present; else s=absent; fi
    printf '%s\\n' \"\$s\" >> '$BATS_TEST_TMPDIR/seen.log' ;;
esac
'$(command -v awk)' \"\$@\" < \"\$in\"
rc=\$?
rm -f \"\$in\"
exit \$rc"
  run --separate-stderr with_stubs feed
  [ "$status" -eq 0 ]
  [ -s "$BATS_TEST_TMPDIR/seen.log" ]
  [ "$(sort -u "$BATS_TEST_TMPDIR/seen.log")" = absent ]
}

# --- a failed claim with the baseline still there is a death --------------------

# Only a baseline that is no longer there is a quiet exit 0. A `mv` that fails
# on a file that is still there (here: permission denied, source untouched) is
# a death the guard reports; what stays under the unclaimed name is not asserted.
make_denying_mv() {
  make_stub mv "printf 'mv: %s: Permission denied\\n' \"\$1\" >&2
exit 1"
}

# Exit 0, one object, and on both channels the hook's name and the stub's
# stderr; the status number is the hook's choice.
assert_claim_died() {
  local channel
  [ "$status" -eq 0 ]
  assert_one_object
  for channel in sys_msg ctx_msg; do
    [[ "$("$channel")" == *"hook $1 died"* ]]
    [[ "$("$channel")" == *"Permission denied"* ]]
  done
}

@test "sync: a claim failing on a stash that is still there is reported" {
  sync_fixture
  make_denying_mv
  run --separate-stderr with_stubs sync_feed
  assert_claim_died index-sync-post
}

@test "compose: a claim failing on a stamp that is still there is reported" {
  compose_fixture
  make_denying_mv
  run --separate-stderr with_stubs feed
  assert_claim_died index-compose
}

# --- the claimed name is unique to each run -------------------------------------

# A `mv` that logs "<source> <destination>" and runs the real one. A fixed
# claimed name would let a later copy's rename land on the file an earlier copy
# is still reading; the form of the name (`.$$`) is not pinned, only that it
# differs between runs.
make_logging_mv() {
  MVLOG="$BATS_TEST_TMPDIR/mv.log"
  make_stub mv "for a in \"\$@\"; do src=\${dst:-}; dst=\$a; done
printf '%s %s\\n' \"\$src\" \"\$dst\" >> '$MVLOG'
exec '$(command -v mv)' \"\$@\""
}

# The destinations the log shows for source $1, one per line.
claim_destinations() {
  grep -F -- "$1 " "$MVLOG" | sed "s|^$1 ||" || true
}

@test "sync: two runs claim the stash under different names" {
  sync_fixture
  make_logging_mv
  run --separate-stderr with_stubs sync_feed
  [ "$(claim_destinations "$STASH" | wc -l)" -eq 1 ]
  sync_fixture
  run --separate-stderr with_stubs sync_feed
  [ "$(claim_destinations "$STASH" | wc -l)" -eq 2 ]
  [ "$(claim_destinations "$STASH" | sort -u | wc -l)" -eq 2 ]
}

@test "compose: two runs claim the stamp under different names" {
  compose_fixture
  make_logging_mv
  run --separate-stderr with_stubs feed
  [ "$(claim_destinations "$STAMP" | wc -l)" -eq 1 ]
  compose_fixture
  run --separate-stderr with_stubs feed
  [ "$(claim_destinations "$STAMP" | wc -l)" -eq 2 ]
  [ "$(claim_destinations "$STAMP" | sort -u | wc -l)" -eq 2 ]
}
