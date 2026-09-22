# 2026-09-20 — The bats gates keep a pass per suite, and the store fixture's copy path costs a third of what it did

`test-unit` and `test-integration` each guarded one sentinel over the whole
input tree, so the granularity of a skip was all-or-nothing: a RED step touching
one suite reran all ~100. The sentinel is the right instrument for "nothing
moved", and the wrong one for "one thing moved".

A second cache goes beneath it. `scripts/run-bats-cached.sh`, reached through
the prolog's new `run-suites` verb, keeps one key per suite in `<gate>.suites`
beside the gate files: a shared hash — the gate's own input hash with the suite
files left out — the names of every suite the gate runs, and the suite's own
path and contents. Only the misses run. So an edit to one suite reruns that
suite; adding, renaming or deleting one reruns all of them, since a suite may
enumerate its siblings; and an edit under `scripts/`, `hooks/` or
`tests/helpers/` reruns all of them, because nothing records which scripts a
suite exercises. Integration half: 68 s cold, 9 s after touching one suite.

The hard part is attributing a verdict. Per-suite verdicts come from bats' junit
report through `scripts/parse-bats-junit.py`, matched to the suites by position
and cross-checked by name; a report that is missing, short, or out of order
records nothing and every suite runs again. A pass is recorded only if the suite
ran and passed in this run and its key is unchanged afterwards, and a failing
suite does not stop the passing ones beside it from being recorded. A suite that
read another suite's *contents* would need every suite in its key rather than
its own; `reads_all_suites` in the justfile is where such a suite is named, none
exists, and `justfile_gates.bats` fails when one appears undeclared.

Beside the caching, the fixture itself: `make_parent_with_memory` goes from 380
ms to 144 ms a call over 373 call sites. Path escapes are computed once in bash,
a file that lacks the template path is not rewritten, and `git submodule status`
— which exits 0 whatever the submodule's state — is replaced by a gitlink test
that also catches a present-but-empty submodule, which `rev-parse HEAD` resolves
to the parent.

Two things measured and not taken. Batching `rev-parse` in the hooks came out
within noise; the patch stays under `plans/precommit-speed/` unapplied, while
the replay-marker tests it prompted stay in the suite. The timings and the
argument against rewriting the hot path in Python are recorded there.
