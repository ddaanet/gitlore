#!/usr/bin/env bash
set -euo pipefail

# Run one named mutation against a tracked file and report whether a bats suite
# kills it.
#
#   mutate-and-run.sh <file> <sed-script> <bats-file> [<filter>]
#
#   <file>        the subject: tracked, with no staged or unstaged changes
#   <sed-script>  the mutation, as a sed script — `s/exit 1/exit 0/`
#   <bats-file>   the suite to run against the mutant
#   <filter>      optional `bats --filter` regexp, narrowing that suite
#
# Exit codes:
#   0  KILLED   — the suite went red against the mutant
#   1  SURVIVED — the suite stayed green, so it does not discriminate the
#                 mutation and the behaviour it targets is unpinned
#   2  refused, or the run broke — the subject is untracked or dirty, the
#      mutation changed nothing, the suite selected no test, or the restore did
#      not put the subject back byte for byte
#
# The mutation is a sed script rather than a diff because a diff pins line
# numbers and context, and a report quotes the substitution as the mutation's
# name. A script that matches nothing is refused as an empty mutation: an
# unmutated run read as a mutant result is the failure this exists to prevent.
#
# The subject is restored on every exit path, signals included, and the restore
# is verified against the index. The backup lives under the gitdir — never
# under $TMPDIR, which is unset when the sandbox is off, and never beside the
# subject, where a suite's own discovery would reach it.

unset CDPATH

# The runner ships beside this script, so a subject in another repository still
# gets gitlore's failure-only bats output rather than that repo's tooling.
here=$(cd "$(dirname "$0")" && pwd)

if [ $# -lt 3 ] || [ $# -gt 4 ]; then
  echo "usage: mutate-and-run.sh <file> <sed-script> <bats-file> [<filter>]" >&2
  exit 2
fi
mutation="$2"
filter="${4-}"

# Both paths are resolved before the `cd` below, so a caller may name them
# relative to wherever it was standing.
abspath() {
  local dir
  dir=$(cd "$(dirname "$1")" && pwd) || return 1
  printf '%s/%s\n' "$dir" "$(basename "$1")"
}

[ -f "$1" ] || { echo "mutate-and-run: no such file: $1" >&2; exit 2; }
[ -f "$3" ] || { echo "mutate-and-run: no such suite: $3" >&2; exit 2; }
subject=$(abspath "$1") || exit 2
suite=$(abspath "$3") || exit 2

root=$(git -C "$(dirname "$subject")" rev-parse --show-toplevel) || exit 2
cd "$root"

work=$(git rev-parse --git-path gitlore/mutate)
mkdir -p "$work"
backup="$work/subject.bak"
subject_record="$work/subject.path"
mutant="$work/mutant"
suite_log="$work/suite.log"

# Ahead of the dirtiness check, because a crashed run leaves the subject
# holding its mutant: the backup is what explains that dirtiness, and telling
# the caller to revert it would discard the only copy of the original.
if [ -e "$backup" ]; then
  # NUL-terminated, so a subject path holding a newline survives the round trip.
  stale=""
  if [ -f "$subject_record" ]; then
    IFS= read -r -d '' stale < "$subject_record" || stale=""
  fi
  echo "mutate-and-run: a previous run left a backup; restore it before mutating again:" >&2
  printf "  cat '%s' > '%s' && rm -f '%s' '%s'\n" \
    "$root/$backup" "${stale:-<unrecorded subject>}" \
    "$root/$backup" "$root/$subject_record" >&2
  exit 2
fi

# An untracked subject is refused with the dirty ones: `git diff` says nothing
# about it, so the restore check at the end would be vacuous.
git ls-files --error-unmatch -- "$subject" > /dev/null || {
  echo "mutate-and-run: $subject is not tracked; a restore could not be verified" >&2
  exit 2
}
if ! git diff --quiet -- "$subject" || ! git diff --quiet --cached -- "$subject"; then
  echo "mutate-and-run: $subject has uncommitted changes; commit or revert them first" >&2
  exit 2
fi

# Idempotent: the signal traps exit, which runs the EXIT trap after them.
# `cat >` rather than `mv`: it rewrites the subject's own bytes, so the file
# keeps its mode and its inode.
restore_subject() {
  if [ -f "$backup" ]; then
    cat "$backup" > "$subject"
    rm -f "$backup" "$subject_record"
  fi
  rm -f "$mutant" "$backup.part"
}
trap 'restore_subject' EXIT
trap 'restore_subject; exit 2' HUP INT TERM

sed "$mutation" "$subject" > "$mutant" || {
  echo "mutate-and-run: the sed script failed against $subject" >&2
  exit 2
}
cmp -s "$mutant" "$subject" && {
  echo "mutate-and-run: the mutation left $subject unchanged — an empty mutation proves nothing" >&2
  exit 2
}

# Written aside and moved into place, so the backup exists only once it is
# complete and a signal mid-write cannot leave a half copy for the trap.
cat "$subject" > "$backup.part"
mv "$backup.part" "$backup"
printf '%s\0' "$subject" > "$subject_record"
cat "$mutant" > "$subject"

bats_args=("$suite")
[ -z "$filter" ] || bats_args=(--filter "$filter" "$suite")
set +e
"$here/run-bats.sh" "${bats_args[@]}" > "$suite_log" 2>&1
suite_status=$?
set -e
cat "$suite_log"

restore_subject
if ! git diff --quiet -- "$subject" || ! git diff --quiet --cached -- "$subject"; then
  echo "mutate-and-run: $subject did not come back byte for byte — restore it by hand from HEAD" >&2
  exit 2
fi

# A filter that selects nothing leaves bats green over zero tests, which would
# read as a survival.
counts=$(sed -n 's/^bats: \([0-9][0-9]*\) passed, \([0-9][0-9]*\) failed.*/\1 \2/p' "$suite_log" | tail -n 1)
rm -f "$suite_log"
[ -n "$counts" ] || {
  echo "mutate-and-run: the suite printed no count; the run is not a verdict" >&2
  exit 2
}
passed="${counts% *}"
failed="${counts#* }"
[ "$((passed + failed))" -gt 0 ] || {
  echo "mutate-and-run: the suite selected no test${filter:+ (filter: $filter)}" >&2
  exit 2
}

printf 'mutate-and-run: subject clean before the run, mutation changed it, %d test(s) ran, subject restored and verified.\n' \
  "$((passed + failed))"
if [ "$suite_status" -ne 0 ]; then
  printf 'mutate-and-run: KILLED — %s went red against "%s" (%d of %d failing).\n' \
    "$suite" "$mutation" "$failed" "$((passed + failed))"
  exit 0
fi
printf 'mutate-and-run: SURVIVED — %s stayed green against "%s" (%d test(s)); nothing pins it.\n' \
  "$suite" "$mutation" "$passed"
exit 1
