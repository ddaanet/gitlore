# Artifact size — decision D73

The byte cap over every artifact a reader takes in at one go — a `docs/` node, a
shell script, a hook, a bats suite, a plan — and the toolkit check that makes it
a gate. Enforced by `plugin-dev/check-size.sh`, wired into `precommit` as
`check-size`.

- **D73** — the cap is 20000 bytes per file, 10000 for a `SKILL.md`, counted by
  the toolkit's `check-size` over every file git does not ignore; it is a
  context budget, so it binds scripts, hooks and suites as it binds `docs/`

---

## What the cap bounds

The cap rations a reader's context window, and bytes are the measure that tracks
it. Bytes as `wc -c` counts them, whitespace included, come to about 10k tokens
for 20000 bytes of English, and the Read tool presents a file of that size at
about that count. A byte count is exact, free and reproducible on every machine,
and unlike a line count it does not depend on how a formatter wrapped the file:
150–300-character lines pass a line cap and fill the window anyway.

Code tokenizes denser per byte than English — identifiers split, punctuation
takes a token each — so treat the 10k figure as an estimate for a script where
it is an upper bound for a node, and do not lean on it for a file of dense
one-liners.

The quantity the cap bounds reliably for a script is not tokens but the number
of definitions a reader holds at once. A file nobody reads whole is past its
seam whether or not its tokens fit.

A `SKILL.md` hub has the lower cap because it is paid on every invocation, while
a node is opt-in.

## Why it is a context rule, not a documentation rule

An agent does the same thing with a script that it does with a node: reads it
whole, into one context window it shares with everything else the task needs.
The cap is a claim about that window, not about how documentation ought to be
organized, so the file's language decides nothing. The corollary is that the cap
follows the reading, not the artifact type: it covers plans, PRs and design docs
for the same reason.

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
count exists to emit. Satisfying it quietly — long lines, shaved docstrings — is
borrowing against the split rather than making it.

The gate is binary: a file over its cap blocks. What the gate buys is that the
judgement gets exercised at a fixed point instead of deferred indefinitely; what
it costs is that a file which genuinely wants a little more has to split anyway,
or be named in `size.exempt` with a reason.

## What the checker walks

The walk, the metric, what is skipped, the `size.exempt` format and the report
are in the toolkit manual,
[size-check.md](../../plugin-dev/manual/size-check.md). `plans/` is among the
skipped paths on purpose: a plan's scripts are run-once artifacts belonging to a
finished job.

**D73 — The byte cap is a context budget, so it binds code as well as `docs/`**

The cap was adopted for `docs/` on an argument about what a reader takes in at
one go, and that argument never mentioned markdown. A rule outside `docs/` left
as a convention with no checker decays silently at the first file that grows a
hundred lines at a time; the reason the `docs/` cap stuck is that a gate
refused. One toolkit check covers every file, so the rule has one
implementation, one discovery and one report, and `check-docs-links.py` carries
no size check of its own.

`check-size` runs uncached as a `precommit` dependency: a pass over the tree's
file sizes costs less than the bookkeeping of a gate file.

## Rejected alternatives

**Raising the cap.** A cap set to clear the largest file today is a cap set by
whatever grew last, and it has to move again the next time. The budget being
rationed belongs to the reader, not to the file, so it does not enlarge because
a file did.

**Gating tokens instead of bytes.** Counting tokens calls the API: a local gate
run on every commit would need the network and a key, and its verdict would
shift under a tokenizer version with no edit to the tree. Bytes are exact, free
and reproducible, and they track tokens closely enough to ration a window.

**Leaving the rule a convention with no checker.** Nothing would notice when a
file crossed the cap again. Every file that regressed would regress silently,
and the next reader to hit one would have no evidence a rule had ever applied.

**A separate checker script for the source tree.** One rule split across two
files, each with its own discovery, reporting convention, justfile wiring and
gate hash. One script covers every file.

**Counting only shell files, not python.** The checkers are read whole by anyone
changing a gate, exactly as a shell library is. Exempting them would make the
gate's own implementation the one place in the repo where the rule it enforces
does not reach. The byte check counts every file.

**Keeping the line check beside the byte check.** The two measures disagree, so
a file can pass one and fail the other, and a reader cannot tell which budget a
failure spends. The byte check alone bounds the window.
