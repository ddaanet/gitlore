# 2026-09-21 — The suite refuses a bats run under bash below 4.1, where its `[[ ]]` assertions pass silently

macOS is a declared target and ships `/bin/bash` 3.2, so the suite had to be
told what that bash does to a bats assertion. Measured with bats 1.14.0 on bash
3.2.57: a failing non-final `[[ ]]` passes silently, while a failing `[ ]` or a
failing plain command still fails the test. Nearly every assertion in this suite
is a non-final `[[ "$output" == *"…"* ]]`, so a run there was not merely
unreliable — it was a green report from suites whose assertions never
discriminated anything, which is worse than no run at all.

Rewriting the assertions as `[ ]` was the obvious repair and does not work: the
glob match is the whole point of the form, and `[ ]` cannot express it. The
floor is enforced instead. `require_assertion_bash` in
`tests/helpers/setup.bash` — which every suite loads — returns 1 under any bash
below 4.1, with the remedy in the message, so a run under 3.2 fails every suite
at load time rather than reporting a pass. `tests/bsd_portability.bats` holds
the lock-in, beside the other BSD-and-3.2 contracts.

That splits the repo's bash requirement in two, and the split is load-bearing
rather than a caveat: the shipped scripts still target 3.2, because that is what
a user's machine runs them on, while the suite that checks them needs 4.1.
`scripts/test-macos.sh` is what reconciles the two on a Mac — bats under a
modern bash, the scripts a test execs under the system's own — and it is the
standing macOS run.
