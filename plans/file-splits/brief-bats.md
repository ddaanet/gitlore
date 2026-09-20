# Brief — splitting a bats suite against the 400-line cap

Shared rules for every bats split in this run. The dispatch message names the
suite, the proposed partition and the report path.

## Ground rules

- Repository: `/Users/david/code/gitlore`. Every command starts with
  `cd /Users/david/code/gitlore &&`.
- Do not commit, create or switch branches, use `--no-verify`, or touch files
  outside the repo. Untracked zero-byte dotfiles in the repo root (`.bashrc`,
  `.gitconfig`, `.mcp.json`, …) are sandbox artifacts: never delete, edit or
  report them.
- The working tree holds earlier, reviewed, uncommitted splits. Leave them
  alone.
- macOS is a target: bash 3.2, BSD tools. Helpers must not use GNU-only flags or
  bash 4 features.
- Every command runs in the FOREGROUND. Never pass `run_in_background`: a
  subagent does not receive a background task's completion notice and stalls.

## The split

- PURE MOVES. Each `@test` block, with the comment block directly above it,
  moves verbatim into exactly one new file. No test is renamed, reworded,
  merged, dropped or "improved". Section banner comments travel with the first
  test of their section.
- The original file name stays, holding one cohesive group; the others become
  `tests/<suite>_<topic>.bats`. Never start a new name with `integration_` — the
  justfile routes on that prefix.
- Every resulting `.bats` file ends at 380 lines or fewer. Do not shave comments
  or join lines to get there; split further at a section boundary instead, and
  say so in the report.
- Each new file repeats the header the original has — shebang, the
  `# shellcheck disable=` line only if the file still needs it (lint tells you),
  `bats_require_minimum_version` only if a test in it uses
  `run --separate-stderr` or another 1.5 feature, the `load` lines it needs —
  and opens with a 1–3 line comment saying what the file covers.
- Shared setup — file-level variables, `setup`/`teardown` bodies longer than one
  line, and helper functions used by more than one resulting file — moves to
  `tests/helpers/<suite-with-dashes>.bash`, loaded with `load helpers/<name>`. A
  helper used by a single resulting file stays in that file, above its first
  user as it is today. If an existing helper file already fits, use it instead
  of creating one. Helper bodies move verbatim; a file-level variable that
  relies on `$PLUGIN_ROOT` keeps working when loaded after `helpers/setup` —
  confirm by running the suite.
- Order inside each file follows the original order.

## References

Grep the repo (excluding `docs/changelog/` and `.claude/`) for the original
file's name — `tests/<suite>.bats` and bare `<suite>.bats`. Where a comment, doc
or memory-free text says a MOVED test or section lives in the original file,
point it at the new file. Check whether the `justfile`, `scripts/run-bats.sh`,
`tests/justfile_gates.bats`, `tests/plugin_distribution.bats` or
`docs/references/testing.md` enumerate suites by name. Do not edit anything
under `memory/`.

Run this and account for EVERY hit in the report — updated, or left and why (a
previous split missed three comments in `scripts/` and sibling suites):
`grep -rn '<suite>\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md`
A hit naming a test by its title is repointed to whichever new file that title
now lives in — find it with `grep -l`.

## Verification

1. Test names preserved — prints nothing:
   `diff <(git show HEAD:tests/<suite>.bats | grep '^@test' | sort) <(cat <all resulting .bats files> | grep -h '^@test' | sort)`
2. No line lost — prints nothing:
   `diff <(git show HEAD:tests/<suite>.bats | sort) <(cat <all resulting .bats files> <the helper file, if any> | sort) | grep '^<'`
   Any line it prints must be a header/`load`/setup line you deliberately
   replaced; list each in the report.
3. `wc -l` of every resulting file.
4. `scripts/run-bats.sh <all resulting .bats files>` — the pass count equals
   `git show HEAD:tests/<suite>.bats | grep -c '^@test'`, zero failed.
5. `just lint` (timeout 600000).
6. Do NOT run `just test-unit` or the whole suite. It outlives the Bash tool's
   foreground cap on this box, gets moved to the background, and a subagent
   never hears it finish. The main session runs it after your report. Your
   evidence is steps 1–5; finish every edit, the reference sweep included,
   before step 4 so they describe the final tree.

## Report

Write the report to the path the dispatch names: final partition with line
counts and test counts per file, the helper file's contents in one line each,
deviations from the proposed partition and why, every reference updated
(`file:line`), and each verification command with its verbatim result. Reply
with one line pointing at the report.
