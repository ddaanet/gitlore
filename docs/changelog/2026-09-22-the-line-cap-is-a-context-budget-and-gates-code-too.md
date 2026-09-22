# 2026-09-22 — The 400-line cap is a context budget, so the checker gates scripts, hooks and suites too

The cap was adopted for `docs/` on 2026-08-25 on an argument about what a reader
takes in at one go, and the nineteen splits of 2026-09-20 applied it to shell
scripts and bats suites on exactly that reading. It stopped there: the
`oversized-file` check in `scripts/check-docs-links.py` walked `docs/` alone, so
the rule outside it was a convention nothing would notice breaking. That is the
state the `docs/` cap was in before it got a checker, and the reason it got one.

The reading behind the cap is what settles the scope. An agent does the same
thing with a script that it does with a node — reads it whole, into one context
window shared with everything else the task needs — so the cap rations that
window rather than tidying documentation, and the file's language decides
nothing. `lib/resolve.sh` at 2084 lines cost what `design.md` at 810 cost, and
the same cut along a need-time seam fixed each.

`check-docs-links.py` gains a second walk. `discover_sources` covers
`SOURCE_DIRS` — `scripts`, `hooks`, `tests` — for `SOURCE_SUFFIXES` `.sh`,
`.bash`, `.bats` and `.py`, and every path it yields goes through the same
`check_size` that `docs/` does, blocking with `oversized-file` past 400 lines.
Two bats cases pin the new half: a 401-line `scripts/lib/big.sh` blocks, a
400-line `tests/big.bats` passes. Shell under `plans/` stays out — a plan's
scripts belong to a finished job, which is why `plans/*/reports/` is not wrapped
either. Nothing needed splitting to turn the gate on: the largest source file is
`tests/justfile_gates.bats` at 394 lines, so the check holds a position the tree
had already reached.

The line count is what gets counted, for code as for prose, and the honest
reason differs between them. In `docs/` the 80-column hard wrap closes the
arithmetic — 18–23 tokens a wrapped line, 400 lines under 10k tokens whatever
the file says. No formatter wraps a script, so the bound there rests on the
repo's own style; width comes out level (`scripts/lib/` averages 51 characters a
line against 58 across `docs/references/`), but code tokenizes denser per
character, so the token figure is an estimate for a script where it is an upper
bound for a node. What the cap bounds reliably for a script is the number of
definitions a reader holds at once.

This is recorded as **D55**, in `docs/decisions.md` and
[artifact-size.md](../references/artifact-size.md), with a new NFR12 in the hub
delegating to it. It is the first decision the index carries for a hygiene rule:
the `docs/` cap of 2026-08-25 landed as a changelog entry and nothing else, so
the argument for it — and the alternatives it ruled out, raising the cap and
gating tokens among them — sat in a dated record rather than in the file a
reader opens before weighing a new decision.
