## Brief: rewrite gitlore's bats negatives to be non-vacuous by construction

2026-07-31

Target repo: `/Users/david/code/gitlore` (gitlore itself, not a dependency).

### Decisions

- **Paired structure is the default; mutation is the fallback.** Every negative
  assertion is paired with a positive over the **same fixture**, differing only
  in the guard's trigger input. Positive red = the path or the wording drifted.
  Negative red = the guard was deleted or widened. Targeted mutation is kept
  only for negatives that cannot be paired with a positive proving their path.
- **Trigger strings live in test-side globals.** Every string a negative refutes
  is held in a global defined in `tests/helpers/` and asserted by at least one
  positive test. A rename in production turns the positive red; the global is
  corrected once and the negative moves with it.
- **The literal is duplicated test-side on purpose.** Do NOT source the string
  from the production lib. Sourcing moves both sides together, and the positive
  stops pinning the wording — it can then only detect non-emission, not a bad
  rename. The duplication is the pin.
- **Few grouped positives license many negatives.** One positive over a fixture
  pins the strings and proves the path; each negative flips a single condition
  against it. Prefer this to one positive per negative.
- The rule is already encoded in
  `memory/ddaanet/feedback_mutation_check_negatives.md`. Read it first; this
  brief is the application, that file is the rule.

### Constraints

- **The rule ships un-dogfooded.** It was derived and written down without being
  run against a real suite. First job is to validate it on actual tests and
  report back where it does not hold — the memory is expected to change.
- Run the suite through `scripts/run-bats.sh` (via `just test-unit` /
  `just test-integration`), never bare `bats`: the wrapper prints only `not ok`
  blocks plus a pass/fail count and stashes full TAP in a tmp file. Do not pipe
  raw `bats` through `tail` — a truncated tail crops the one `not ok` that
  matters. Invoke `bats` directly only when debugging the wrapper itself.
- `just precommit` before any commit, unprompted. `just evals` drives the real
  claude CLI and costs money — run it only when explicitly asked.
- Load the `shell-scripting:shell-gotchas` skill before writing OR reviewing
  `.bats`/`.sh` diffs. ShellCheck misses the BSD / `set -e` / hook-env class.
- Whitespace safety is not a nit: test against a spaced input, prefer
  NUL-delimited forms.
- Do not hand-edit `plugin-dev/` — it is a vendored subtree.
- `memory/` is a git submodule with a per-commit approval gate. Never
  `git commit` inside it; committing the parent records and gates it.

### Rejected approaches

- **DRY-ing the trigger literal into a shared production constant.** Makes the
  positive a tautology for wording changes. Rejected explicitly.
- **A general mutation sweep.** One targeted mutation per assertion, naming the
  line the test watches — a sweep does not identify which guard is pinned.
- **Manual mutation as the default discipline.** It proved mostly that the
  matcher string was live and correctly spelled, which the paired structure now
  gets for free and keeps working as the code moves.

### Additional context

Current negative-assertion sites (`refute_output` / `refute_line` /
`assert_failure`), by count:

- `tests/index_compose.bats` — 13 (the bulk of the work)
- `tests/resolve_merge_briefing.bats` — 5
- `tests/install_remote.bats` — 1
- `tests/cc_hook_index_compose.bats` — 1

Helpers live in `tests/helpers/`: `setup.bash`, `fixtures.bash`,
`tier-fixtures.bash`, `divergence-fixtures.bash`, `gh-mock.bash`,
`stub-synth.bash`. The trigger globals belong in `setup.bash` or a new
`triggers.bash` loaded from it.

bats-specific traps that make this failure mode concrete:

- `run missing_function` exits 127, satisfying `-ne 0` before the code exists —
  a vacuous negative that looks green.
- `grep -qF` matches any ONE line of a multi-line pattern.
- SC2314: a bare `! cmd` asserts nothing; use `run !`.
- `@test` bodies run under errexit.
- A positive match on an **accumulating output channel** (a log, a status line,
  a notification payload several producers append to) is vacuous when the string
  matched is one an unrelated producer already emits. Match a phrase unique to
  the message under test.

Validation requirement: any test written or restructured here must be shown to
go red under a deliberate fault before it counts as evidence. An *error* is not
a red — a run that dies on a missing file or a parse error never reached the
assertion. See `memory/ddaanet/feedback_tests_must_go_red.md`.
