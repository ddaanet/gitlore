# Per-suite bats sentinels — 2026-09-20

## Problem

`test-unit` and `test-integration` each guard one sentinel over the whole input
tree. Any edit under `tests/` moves the hash, so a RED step that touches one
suite reruns all ~100 (about nine minutes). The whole-tree sentinel stays: it is
the fast path for an untouched tree. This adds a finer cache beneath it, the way
`scripts/lint-shell.sh` keeps a per-file cache beneath the `lint` sentinel.

It does not shorten a GREEN step. An edit under `scripts/`, `hooks/` or
`tests/helpers/` moves every key, because nothing records which scripts a suite
exercises and guessing gives false greens.

## What a per-suite pass vouches for

A suite's key covers:

- the **shared hash**: the gate's existing `gate-inputs-hash` (tool versions,
  names and contents) over the gate's declared inputs
  *minus the suite files themselves* — `tests/*.bats` and
  `tests/evals/lib/*.bats` excluded by pathspec;
- the **names** of every suite the gate runs, so adding, renaming or deleting a
  suite moves every key (a suite that enumerates its siblings sees the change);
- the suite's own path and contents;
- for a suite that **reads other suites' contents**, the contents of all of
  them. Which suites those are is declared, not inferred, and a guard test keeps
  the declaration honest (below).

A key is recorded only for a suite that ran and passed in this run, and only if
the key computed after the run equals the one computed before it — the same
mid-run rule `record-sentinel` applies to the whole gate.

## Contract

### `scripts/run-bats-cached.sh`

```
scripts/run-bats-cached.sh <keys-file> <shared-hash> [--reads-all <suite>]... \
    -- <bats args and suites, as scripts/run-bats.sh takes them>
```

1. Splits the arguments after `--` into bats options and suite paths (a suite is
   an argument ending in `.bats`; `--jobs <n>` and the like pass through).
2. Computes one key per suite as above. Few processes: one `cksum` over all
   suite files, not one per suite.
3. A suite whose key is a line of `<keys-file>` is a hit and is not run, unless
   `GITLORE_GATE_FORCE` is set, which runs everything.
4. Runs the misses through `scripts/run-bats.sh` in one invocation, so `--jobs`
   parallelism is kept, and obtains a verdict **per suite**. bats' TAP stream
   carries no file names; `--report-formatter junit` does (one `testsuite` per
   file). Parsing it may use `python3`, already a gate dependency; no regex over
   XML.
5. Rewrites `<keys-file>` with the keys of every hit plus every miss that passed
   and whose key is unchanged after the run. Self-pruning, like the lint cache.
   A failed or unparsable report records no miss and says so on stderr; hits are
   kept.
6. Exits with the bats status; with no misses, exits 0 without invoking bats.
7. Signs off with what happened, never a bare OK:
   `bats: 97 suites cached, 3 run — 41 passed, 0 failed — full log: …`.

### The recipes

`test-unit` and `test-integration` keep `sentinel-guard` and `record-sentinel`
exactly as they are. Between them, the recipe computes the shared hash with the
prolog's own `gate-inputs-hash` — by setting `gate_inputs` to the gate's inputs
plus the two exclude pathspecs in a subshell, so `check-sentinel`'s variables
are not clobbered — and calls the script with
`${GITLORE_GATE_DIR:-$(git rev-parse --git-path gitlore/gates)}/<gate>.suites`
as the keys file. An unhashable tree (empty shared hash) runs everything and
records nothing per suite.

### Suites that read other suites

Find them first: grep the suites for globs or listings over `tests/` (`*.bats`,
`ls-files -- tests`, `$BATS_TEST_DIRNAME/`). `tests/justfile_gates.bats` reads
suite *names* (covered by the names component); any suite that greps suite
*contents* — `tests/bsd_portability.bats` is a candidate — goes in a justfile
variable passed as `--reads-all`. A guard test in `tests/justfile_gates.bats`
fails when a suite matches the content-reading pattern and is not declared.

## Tests, written first

A new `tests/run_bats_cached.bats`, driving the script against tiny real suites
in a temp directory with the real `bats`:

- a second run over unchanged suites runs nothing, exits 0, reports all cached;
- editing one suite runs that suite only;
- a different shared hash runs everything;
- adding a suite runs everything (names component);
- a failing suite is not recorded and runs again; the passing misses beside it
  ARE recorded (the per-suite verdict — this is the test that fails under a
  one-verdict-for-all implementation);
- a `--reads-all` suite runs when a sibling's contents change;
- `GITLORE_GATE_FORCE=1` runs everything;
- a suite edited while the run is in flight is not recorded;
- the exit status is bats' own on failure.

Each guard-style test that is green before the code exists gets a mutation run
to prove it discriminates.

In `tests/justfile_gates.bats`: both recipes reach `run-bats-cached.sh` before
`record-sentinel` (extend the existing reach test, whose runner for the two bats
gates changes name); the stubbed `discovered_suites` run still exits 0 and still
lists every suite — the stub `bats` writes no junit report, which must degrade
to "nothing recorded", not to a failure, because discovery runs forced.

## Out of scope

`docs/references/testing.md` and `CLAUDE.md` — the main session writes those
after review. `check-distribution` — one suite, nothing to split.
