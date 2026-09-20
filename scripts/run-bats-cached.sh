#!/usr/bin/env bash
set -euo pipefail

# A finer cache beneath `test-unit`/`test-integration`'s whole-tree sentinel:
# one key per suite, so an edit under `tests/` reruns the suites it touched
# rather than the whole ~100. What a recorded pass vouches for is argued in
# docs/references/testing.md.
#
# Usage: run-bats-cached.sh <keys-file> <shared-hash> [--reads-all <suite>]... \
#     -- <bats args and suites, as scripts/run-bats.sh takes them>
#
# A suite's key covers the shared hash (the gate's own inputs, minus the
# suites themselves), the names of every suite in this invocation (so adding,
# renaming or deleting one moves every key), the suite's own path and
# contents, and — for a `--reads-all` suite — the contents of every suite in
# this invocation. A key is recorded only for a suite that ran, passed, and
# whose key is unchanged after the run.

keys_file="$1"; shift
shared_hash="$1"; shift

reads_all=()
while [ "${1:-}" = "--reads-all" ]; do
  reads_all+=("$2")
  shift 2
done

[ "${1:-}" = "--" ] || { echo "run-bats-cached: expected -- before bats args" >&2; exit 1; }
shift

# A suite is an operand ending in `.bats`; everything else (`--jobs 4`, and
# the like) passes through to bats untouched, in its given order.
bats_opts=()
suites=()
for arg in "$@"; do
  case "$arg" in
    *.bats) suites+=("$arg") ;;
    *) bats_opts+=("$arg") ;;
  esac
done
[ "${#suites[@]}" -gt 0 ] || { echo "run-bats-cached: no suites given" >&2; exit 1; }

is_reads_all() {
  local suite="$1" i
  [ "${#reads_all[@]}" -gt 0 ] || return 1
  for i in "${reads_all[@]}"; do
    [ "$i" = "$suite" ] && return 0
  done
  return 1
}

# Names first, so a rename or a deletion moves every key even though this
# function only ever hashes the suite it's given.
names_key="$(printf '%s\n' "${suites[@]}" | sort | cksum)"

# One pass over every suite's contents, not one per `--reads-all` suite: the
# expensive part of "reads all of them" is shared, and each suite's own key
# still needs its own `cksum` call below.
all_blob_hash=""
if [ "${#reads_all[@]}" -gt 0 ]; then
  all_blob_hash="$(cat -- "${suites[@]}" | cksum)"
fi

suite_key() {
  local suite="$1"
  {
    printf '%s\n' "$shared_hash" "$names_key" "$suite"
    cat -- "$suite"
    is_reads_all "$suite" && printf '%s\n' "$all_blob_hash"
    true
  } | cksum
}

mkdir -p "$(dirname "$keys_file")"
existing_keys=()
if [ -f "$keys_file" ]; then
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] && existing_keys+=("$line")
  done < "$keys_file"
fi

has_key() {
  local k="$1" e
  [ "${#existing_keys[@]}" -gt 0 ] || return 1
  for e in "${existing_keys[@]}"; do
    [ "$e" = "$k" ] && return 0
  done
  return 1
}

# An unhashable shared hash covers nothing, so nothing can be vouched for:
# every suite runs, and no key — old or new — is trustworthy enough to keep.
unhashable=0
[ -n "$shared_hash" ] || unhashable=1

before_keys=()
hit_keys=()
miss_suites=()
miss_idx=()
for i in "${!suites[@]}"; do
  suite="${suites[$i]}"
  k="$(suite_key "$suite")"
  before_keys+=("$k")
  if [ "$unhashable" -eq 0 ] && [ -z "${GITLORE_GATE_FORCE:-}" ] && has_key "$k"; then
    hit_keys+=("$k")
  else
    miss_suites+=("$suite")
    miss_idx+=("$i")
  fi
done

cached_count=$(( ${#suites[@]} - ${#miss_suites[@]} ))
ran_count=${#miss_suites[@]}

if [ "$ran_count" -eq 0 ]; then
  printf 'bats: %d suites cached, 0 run — full log: (nothing run)\n' "$cached_count"
  exit 0
fi

script_dir="$(dirname "$0")"
junit_dir="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-bats-junit.XXXXXX")"
trap 'rm -rf "$junit_dir"' EXIT

cmd=("$script_dir/run-bats.sh")
[ "${#bats_opts[@]}" -gt 0 ] && cmd+=("${bats_opts[@]}")
cmd+=(--report-formatter junit --output "$junit_dir")
cmd+=("${miss_suites[@]}")

set +e
output="$("${cmd[@]}")"
status=$?
set -e

# Failure counts, one per testsuite the report holds, parsed with a real XML
# parser because a test name is an unescaped surface. Matched to `miss_suites`
# by position: bats writes one `testsuite` per input file in the order given,
# whatever order `--jobs` finishes them in. Position alone would hand one
# suite's pass to another if that ever stopped holding, so each testsuite's
# `name` must also be a suffix of the path at its position — bats strips the
# inputs' shared leading directory from it ("evals/lib/asserts.bats"), which
# rules out an exact match. A report that fails either check is as unusable as
# no report: nothing is recorded, and the suites run again.
verdict_failed=()
report="$(find "$junit_dir" -maxdepth 1 -name '*.xml' -print -quit)"
if [ -n "$report" ]; then
  while IFS=$'\t' read -r vfailed vname || [ -n "$vfailed" ]; do
    [ -n "$vfailed" ] || continue
    j=${#verdict_failed[@]}
    case "${miss_suites[$j]:-}" in
      *"$vname") verdict_failed+=("$vfailed") ;;
      *)
        echo "run-bats-cached: junit verdict $((j + 1)) is for '$vname', expected ${miss_suites[$j]:-no suite}; nothing recorded for this run" >&2
        verdict_failed=()
        break
        ;;
    esac
  done < <("$script_dir/parse-bats-junit.py" "$report")
fi
if [ "${#verdict_failed[@]}" -ne "${#miss_suites[@]}" ]; then
  echo "run-bats-cached: junit report held ${#verdict_failed[@]} usable verdicts for ${#miss_suites[@]} suites; nothing recorded for this run" >&2
  verdict_failed=()
fi

suite_failed() {
  local j="$1"
  [ "${#verdict_failed[@]}" -gt 0 ] || return 1
  printf '%s\n' "${verdict_failed[$j]}"
}

recorded_keys=()
if [ "$unhashable" -eq 0 ]; then
  for j in "${!miss_idx[@]}"; do
    i="${miss_idx[$j]}"
    suite="${suites[$i]}"
    before="${before_keys[$i]}"
    failed="$(suite_failed "$j")" || continue
    [ "$failed" -eq 0 ] || continue
    after="$(suite_key "$suite")"
    if [ "$after" = "$before" ]; then
      recorded_keys+=("$after")
    else
      echo "run-bats-cached: $suite changed while bats ran; its pass was not recorded" >&2
    fi
  done
fi

if [ "$unhashable" -eq 1 ]; then
  rm -f "$keys_file"
else
  {
    [ "${#hit_keys[@]}" -gt 0 ] && printf '%s\n' "${hit_keys[@]}"
    [ "${#recorded_keys[@]}" -gt 0 ] && printf '%s\n' "${recorded_keys[@]}"
    true
  } > "$keys_file"
fi

last_line="$(printf '%s\n' "$output" | tail -n 1)"
rest="$(printf '%s\n' "$output" | sed '$d')"
[ -n "$rest" ] && printf '%s\n' "$rest"
printf 'bats: %d suites cached, %d run — %s\n' "$cached_count" "$ran_count" "${last_line#bats: }"
exit "$status"
