# Batch 3 — the precommit gate machinery

All four items landed. Nothing is committed; the four changed files are the only
working-tree changes.

## Files changed

- `/Users/david/code/gitlore/justfile` — items 1, 2, 3
- `/Users/david/code/gitlore/tests/justfile_gates.bats` — tests for 1, 2, 3
- `/Users/david/code/gitlore/CLAUDE.md` — item 4
- `/Users/david/code/gitlore/docs/references/testing.md` — item 4

## Item 1 — the pass is recorded against the tree the checks read

`check-sentinel` now takes the input hash on every path, before the checks
start, and keeps it in `guard_hash`. `record-sentinel` re-hashes, records only
on a match, and on a mismatch removes any stale sentinel, prints
`gate: inputs changed while the checks ran; the pass was NOT recorded` on
stderr, and `exit 1`s so the recipe fails rather than handing the caller a green
verdict.

Two details worth naming. The guard hash is computed ahead of the
`GITLORE_GATE_FORCE` and missing-sentinel early returns, because a forced run
and a first run both reach `record-sentinel` and both need something to compare
against. And an unhashable guard hash is kept distinct from a mismatch: either
one empty means "could not hash inputs", which keeps the pre-existing
contract — no sentinel written, said loudly, recipe still exits 0.

Cost: one extra `gate-inputs-hash` on the uncached path, which is where it did
not run before. Sub-second against a nine-minute run.

### Red

`scripts/run-bats.sh tests/justfile_gates.bats`, against the unchanged justfile:

```
not ok 21 an input edited while the checks ran is not recorded as a pass
# (in test file tests/justfile_gates.bats, line 458)
#   `[ "$status" -ne 0 ]' failed
```

The old `record-sentinel` hashed after the edit and recorded it, so the gate
exited 0. The companion test `an edit outside the declared inputs during a run
still records the pass` was green from the start by design — it pins that the
comparison stays scoped to the gate's own inputs, so an unrelated mid-run edit
does not cost a re-run.

## Item 2 — `test-unit` no longer reads the integration suites

`test-unit`'s guard line is now

```
sentinel-guard test-unit {{ precommit_inputs }} ':(exclude)tests/integration_*'
```

`gate_inputs` is consumed as a pathspec list by
`git ls-files -z --cached --others --exclude-standard -- "${gate_inputs[@]}"`,
so a git exclude pathspec narrows the shared set in place with no new variable
and no change to how the existing declarations are checked. It is single-quoted
in the recipe: the `{{ precommit_inputs }}` interpolation beside it is
word-split on purpose, and an unquoted pathspec would reach the shell's own
globbing on the way past. No whitespace anywhere in the set, and the pathspec
form is core git, not a GNU extension.

Verified directly before writing the recipe: with the exclusion, `git ls-files`
over `precommit_inputs` yields 0 paths under `tests/integration_`, against 5
without it, and still yields the unit suites.

### Red

```
not ok 11 the unit gate's inputs leave the integration suites out, the integration gate's keep them
# (in test file tests/justfile_gates.bats, line 305)
#   `[[ "$output" != *"tests/integration_"* ]]' failed
```

The test asserts on the files the declared inputs *enumerate*, not on the text
of the declaration: two helpers (`guard_line`, `guard_input_files`) rebuild each
gate's `sentinel-guard` line from `just --dump --dump-format json`, resolving
interpolations through `just --evaluate`, then run `git ls-files` with exactly
those arguments against this repo. A pathspec that parsed but stopped excluding
would still fail it. `test-integration` and `lint` are asserted to keep the
integration suites, so the narrowing is pinned to the one gate that wants it.

## Item 3 — `plans/*/reports/` is out of the wrap set

### The premise holds

`plans/index-edit-propagation/reports/item-1-1-s1-red.md` was created in
`843bb12` and changed again in `f6ef928`, a later commit. Collapsing both
revisions' whitespace and comparing shows an identical word stream: the second
change is a pure rewrap, the formatter rewriting a report after its author
finished with it. `git log --stat` over the reports tree shows the same
two-commit shape on six more files under
`plans/index-edit-propagation/reports/`.

(`rumdl fmt --check plans` reports zero pending changes today, which is the same
fact from the other side — every existing report has already been through the
formatter.)

### No checker is weakened

`scripts/check-docs-links.py` is the only thing in the repo that caps a line
count. `main()` builds its file list from `discover(docs_dir)` where
`docs_dir = <root>/docs`, so `oversized-file` has never covered `plans/` at all;
an unwrapped report escapes no cap, because no cap applies to it.
`scripts/check-memory-hygiene.py` counts no lines and lists `plans` in
`REFERENCE_SCAN_EXCLUDES`. Nothing else under `scripts/` reads a line count of a
prose file. `check-docs-links.py` runs clean after the change (52 decisions, 121
files scanned, `oversized-file 0`).

`plans/` outside `reports/` stays wrapped — plans are read.

### Change and red

`format-docs` now runs
`rumdl fmt --no-cache --exclude 'plans/*/reports' docs plans`.

```
not ok 14 format-docs drives rumdl over docs/ and plans/, and refuses a version off the pin
# (in test file tests/justfile_gates.bats, line 380)
#   `[ "$(cat "$STUB_DIR/args")" = $'fmt\n--no-cache\n--exclude\nplans/*/reports\ndocs\nplans' ]' failed

not ok 15 the wrap set spares plans/*/reports/ and nothing else under plans/
# (in test file tests/justfile_gates.bats, line 428)
#   `[ "$(wc -l < "$WRAP_TREE/plans/job/reports/r.md")" -eq 3 ]' failed
```

The second test captures the recipe's real argument list through the rumdl stub,
then replays that list through the *real* rumdl against a three-file fixture
tree carrying a copy of `.rumdl.toml`. A stub alone would only prove a flag was
passed; this proves the pattern matches what it is meant to and nothing else —
`docs/d.md` and `plans/job/p.md` come back wrapped, `plans/job/reports/r.md`
comes back untouched. Its red was the fixture report being wrapped like
everything else, which is also what proves the fixture exercises the formatter.

## Item 4 — the gate paragraph

Each claim was checked against the justfile as it now stands. All five hold and
all five are stated:

| Claim | How it was verified |
| --- | --- |
| Validity is a content hash, not mtime | `check-sentinel` compares `cat "$sentinel"` against `gate-inputs-hash`, a `cksum` over names, contents and tool versions. No `stat`, `find -newer` or timestamp anywhere in the prolog. |
| The sequential fallback includes `just check-distribution` | It is a standalone recipe with its own `sentinel-guard`/`record-sentinel` pair and its own `distribution_inputs`; `just --summary` lists it (pinned by an existing test). |
| `format-docs`, `check-memory-hygiene.py`, `check-docs-links.py`, `check-version` are uncached and write no gate file | Neither `format-docs` nor `check-version` (in `plugin-dev/release.just`) calls `sentinel-guard`; the two Python checkers are plain lines in `precommit`'s body. |
| The gates path is per-worktree | `git rev-parse --git-path gitlore/gates` gives `.git/gitlore/gates` in the main tree and `/Users/david/code/gitlore/.git/worktrees/wt/gitlore/gates` inside a throwaway linked worktree. Worktree created and removed for the check. |
| `CLAUDE_CODE_DISABLE_BG_SHELL_PRESSURE_REAP=1` is set | Present under `env` in `/Users/david/code/gitlore/.claude/settings.local.json`. Read only. |

The "the box will not take two suites at once" rationale is gone from the
bullet, replaced by the reap setting as the reason a background run survives.
The bullet grew by five lines; the mechanism it used to carry in prose now sits
in `docs/references/testing.md` under a new `## What a sentinel vouches for`
section, which the bullet points at. That section also records the mid-run
invalidation, the `test-unit` narrowing and `GITLORE_GATE_FORCE`, and a short
paragraph above it records the `plans/*/reports/` exclusion.

`docs/design.md`'s NFR10 already said "input-hash sentinel" and needed no
correction. `just format-docs` has been run; it changed nothing beyond the files
listed above.

## Suites run

Foreground, one at a time, through `scripts/run-bats.sh`:

| Suite | Result |
| --- | --- |
| `tests/justfile_gates.bats` | 25 passed, 0 failed |
| `tests/plugin_distribution.bats` | 15 passed, 0 failed |
| `tests/check_docs_links.bats` | 43 passed, 0 failed |
| `tests/bsd_portability.bats` | 3 passed, 0 failed |
| `tests/lint_shell.bats` | 3 passed, 0 failed |

`scripts/lint-shell.sh`: 138 files clean, exit 0 — run after every edit to
`tests/justfile_gates.bats`.

`scripts/check-docs-links.py`: clean, all nine checks at 0.

## Not done

Nothing from the four items is outstanding. `just precommit`, `just test-unit`
and `just test-integration` were not run, per the dispatch — the main session
owns the gate. The three sentinels under `.git/gitlore/gates` are untouched by
this work, so the next `precommit` will re-run all of them: the justfile is a
declared input to every gate.
