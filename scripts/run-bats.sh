#!/usr/bin/env bash
set -euo pipefail

# Wraps `bats` to show only failures plus a pass/fail count. A full run's TAP
# stream ("ok 1 ...", "ok 2 ...", ...) is hundreds of lines long — too long to
# eyeball, and piping it through `tail -N` risks cropping the one "not ok"
# line that matters. The full stream still goes to a log file, so nothing is
# lost on a failure that needs more context than the diagnostic lines shown.
#
# Usage: run-bats.sh <bats-args...>   (same args you'd pass to `bats` directly)

# Xs last: BSD mktemp randomises only a trailing run of them, and uses a
# template like `name-XXXXXX.log` literally — the second run then dies on EEXIST.
log="$(mktemp "${TMPDIR:-/tmp}/gitlore-bats.XXXXXX")"

set +e
bats "$@" >"$log" 2>&1
status=$?
set -e

pass=$(grep -c '^ok ' "$log" || true)
fail=$(grep -c '^not ok ' "$log" || true)

if [ "$fail" -gt 0 ]; then
    awk '/^not ok /{show=1} /^ok /{show=0} show' "$log"
    echo
elif [ "$pass" -eq 0 ]; then
    # Nothing recognizable as TAP output at all (e.g. bats errored before
    # printing a plan) — don't discard it just because it isn't a normal
    # failure shape.
    cat "$log"
fi

echo "bats: $pass passed, $fail failed — full log: $log"
exit "$status"
