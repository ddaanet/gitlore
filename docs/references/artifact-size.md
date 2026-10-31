# Artifact size — decision D55

The 400-line cap over every artifact a reader takes in at one go — a `docs/`
node, a shell script, a hook, a bats suite — and the `oversized-file` check that
makes it a gate. Enforced by `tools/check-docs-links.py`, which ships nothing
and gates this repository alone (D22).

- **D55** — the 400-line cap is a context budget, so it binds scripts, hooks and
  suites exactly as it binds `docs/`

---

## What the cap bounds

For prose the arithmetic is closed. `format-docs` hard-wraps `docs/` at 80
columns, a wrapped line runs 18–23 tokens, so 400 lines is under 10k tokens
whatever the file says. The line count is the binding limit and the token budget
follows from it, which is why lines are what the checker counts.

No formatter wraps a script, so that bound does not transfer — a shell line is
held short by the repo's own style and by shellcheck, not by a rule anything
enforces. What is measurable is width, and it comes out level: `scripts/lib/`
averages 51 characters a line against 58 across `docs/references/`. Code
tokenizes denser per character than English — identifiers split, punctuation
takes a token each — so treat the 10k figure as an estimate for a script where
it is an upper bound for a node, and do not lean on it for a file of dense
one-liners.

The quantity the cap bounds reliably for a script is not tokens but the number
of definitions a reader holds at once. A 2000-line library is a file nobody
reads whole, and a function whose neighbours have stopped telling you anything
is past the seam whether or not its tokens fit.

## Why it is a context rule, not a documentation rule

An agent does the same thing with a script that it does with a node: reads it
whole, into one context window it shares with everything else the task needs.
The cap is a claim about that window, not about how documentation ought to be
organized, so the file's language decides nothing. `lib/resolve.sh` at 2084
lines cost a reader what `design.md` at 810 cost, and the split that fixed each
was the same split.

The corollary is that the cap follows the reading, not the artifact type: it
covers plans, PRs and design docs for the same reason, and `~200` lines caps a
`SKILL.md` hub instead, because that one is paid on every invocation while a
node is opt-in.

## Splitting along a need-time seam

The response to a file over the cap is a cut along a seam a reader already
navigates, by pure moves — never a rewrite, and never prose shaved to fit.

- **A library keeps its name.** `lib/resolve.sh`, `lib/index-compose.sh`,
  `lib/index-sync.sh` and `lib/util.sh` stay the files callers source and pull
  in function-only siblings, so no call site changes.
- **A suite cuts along its own section banners**, with shared setup moving to
  `tests/helpers/`.
- **A node cuts along the clusters its summary already names**, which is how
  `tiered-memory.md` became five nodes with D17 left as the entry.

A pure move is checkable, and checking it is the point: function bodies
byte-identical under `declare -f`, every `@test` name preserved, comments naming
a moved function pointing at its new file.

## Soft in self-review, hard at the gate

The judgement is soft. A bounded overage on one cohesive document beats a
reflexive split whose cross-referencing costs the reader more than the overage
saved, and a file parked at exactly its cap has stopped emitting the signal the
count exists to emit. Satisfying it quietly — 150–300-character lines, shaved
docstrings — is borrowing against the split rather than making it.

The gate is binary. 401 lines blocks, 400 passes, and the boundary is pinned by
two bats cases on each side of it. What the gate buys is that the judgement gets
exercised at a fixed point instead of deferred indefinitely; what it costs is
that a file which genuinely wants 420 lines has to split anyway. That trade was
taken for `docs/` on the same terms.

## What the checker walks

`discover` walks `docs/` for `.md`. `discover_sources` walks `SOURCE_DIRS` —
`scripts`, `tools`, `hooks`, `tests` — for `SOURCE_SUFFIXES`: `.sh`, `.bash`,
`.bats`, `.py`. Every path from either walk goes through `check_size`, which
blocks with `oversized-file` past `MAX_LINES`. `oversized-file` is named in the
counter block whether or not it fired, like every other blocking check.

Shell under `plans/` is out of scope deliberately: a plan's scripts are run-once
artifacts belonging to a finished job, and `plans/*/reports/` is not even
wrapped for the same reason.

**D55 — The line cap is a context budget, so it binds code as well as `docs/`**

The cap was adopted for `docs/` on an argument about what a reader takes in at
one go, and that argument never mentioned markdown. The nineteen splits of
2026-09-20 applied it to scripts and suites on exactly that reading, and left
the rule outside `docs/` a convention with no checker — which is the state the
`docs/` cap was in before 2026-08-25, and it did not hold there either. A
convention decays silently at the first file that grows a hundred lines at a
time; the whole reason the `docs/` cap stuck is that `check-docs-links.py`
started refusing.

So the same check covers both, by extending its walk rather than its argument.
The largest source file when the gate landed was `tests/justfile_gates.bats` at
394 lines, so nothing needed splitting to turn the rule on — the gate holds a
position already reached rather than forcing a migration.

## Rejected alternatives

**Raising the cap.** A cap set to clear the largest file today is a cap set by
whatever grew last, and it has to move again the next time. The budget being
rationed belongs to the reader, not to the file, so it does not enlarge because
a file did.

**Gating tokens instead of lines.** Counting them calls the API: a local gate
run on every commit would need the network and a key, and its verdict would
shift under a tokenizer version with no edit to the tree. Lines are exact, free
and reproducible, and the wrap already ties them to tokens for prose.

**Leaving the rule outside `docs/` a convention with no checker.** Nothing would
notice when a script crossed 400 lines again. Every file that regressed would
regress silently, and the next reader to hit one would have no evidence a rule
had ever applied.

**A separate checker script for the source tree.** One rule split across two
files, each with its own discovery, reporting convention, justfile wiring and
gate hash. `check_size` was already written, already blocking and already
counted; the extension is a second walk feeding the same function. The residual
is that `check-docs-links.py` now under-describes its own scope — the docstring
carries the correction, and a rename is deferred rather than refused.

**Counting only shell files, not python.** The checkers are read whole by anyone
changing a gate, exactly as a shell library is. Exempting them would make the
gate's own implementation the one place in the repo where the rule it enforces
does not reach.
