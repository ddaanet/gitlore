# 2026-07-27 — `tests/evals/lib/judge.sh` gained a third exit state, so a hedged verdict stops reading as a rubric failure

The observed failure mode was not judge unavailability — the judge model
answered but hedged, e.g. `FAIL, but wait, on reflection this is fine — PASS`,
and the single-word-first-line parse either grabbed the wrong token or (with
trailing punctuation attached) matched neither `pass` nor `fail`. With only a
0/1 contract, `case ... *) exit 1` mapped every one of those onto "commit
message failed judge rubric," indistinguishable from a real content miss.
`judge.sh` now exits 0 (clean pass), 1 (clean fail), or 2 (claude invocation
failed, or the first line parsed to neither `pass` nor `fail`) — the latter
printing the raw response to stderr rather than guessing. Hardening the parse
alone, without the third state, would have made this worse: a stricter match
rejects more hedged responses outright, but with no distinct exit code the
rejects still fall into the same "failed rubric" bucket, so tightening the regex
only raises how often a non-content problem masquerades as one. Both call sites
(`asserts/memory-commit.sh`, `asserts/tier-write.sh`) now branch on the judge's
exit code, reporting "judge could not render a verdict" separately from a
genuine rubric miss. Also dropped the `2>/dev/null` on the `claude --print`
invocation itself — no more replacing a real error message with a guess — so an
invocation failure's own stderr is captured, not discarded. 2 new cases in
`tests/evals/lib/judge.bats`.
