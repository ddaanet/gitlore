# Split report — tests/merge_memory.bats

## Final partition

| File | Lines | Tests |
| --- | --- | --- |
| `tests/merge_memory.bats` | 292 | 16 |
| `tests/merge_memory_tiers.bats` | 244 | 7 |
| `tests/merge_memory_repair.bats` | 320 | 8 |
| `tests/merge_memory_repair_arrivals.bats` | 275 | 7 |
| `tests/merge_memory_fetch.bats` | 134 | 4 |
| `tests/helpers/merge-memory.bash` | 62 | — (helper) |

Total: 42 tests preserved (matches `grep -c '^@test' tests/merge_memory.bats` on
the pre-split `HEAD` copy). All five `.bats` files are well under the 380-line
cap.

Boundaries match the dispatch's proposed partition exactly (by test name, not
by the stale line numbers the brief quoted from a since-modified working tree):

- `tests/merge_memory.bats`: "exits 0 with a note…" through "a synced
  placeholder origin is nothing to take…".
- `tests/merge_memory_tiers.bats`: "fast-forwards a pinned tier…" through
  "adopts a TIER's local 'live' that ran ahead…".
- `tests/merge_memory_repair.bats`: "a take repairs a duplicate pointer…"
  through "a take's repair keeps the duplicate its pin lacks".
- `tests/merge_memory_repair_arrivals.bats`: "a take repairs a welded line
  that arrived" through "a refused live update after the repair leaves no
  trace".
- `tests/merge_memory_fetch.bats`: "a take fetches first and takes a repair
  another consumer published" through the end.

## Helper file: `tests/helpers/merge-memory.bash`

One line each:

- `CMD="$PLUGIN_ROOT/scripts/merge-memory.sh"` — file-level var, used by every resulting file.
- `SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"` — file-level var; only one test (in `merge_memory_tiers.bats`) uses it today, but the rule places file-level vars here regardless of use count.
- `setup() { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; MEMORY_REMOTE=...; export MEMORY_REMOTE; }` — bats setup, needed by every file.
- `teardown() { teardown_tmp_repo; }` — bats teardown, needed by every file.
- `wire_memory_remote()` — wires the memory store's own remote; called by nearly every test across all five files.
- `push_memory_fact()` — publishes a commit to the memory remote the store hasn't fetched; used in `merge_memory.bats` and `merge_memory_tiers.bats`.
- `tier_gitdir_files()` — snapshot of a tier's gitdir bookkeeping files; used in `merge_memory_repair.bats` and `merge_memory_repair_arrivals.bats`.
- `repair_scratch_dirs()` — leftover repair scratch dirs under a TMPDIR; used in the same two files.

`strand_live_behind_head()` is used only by two tests, both inside
`tests/merge_memory.bats`, so it stayed there (above its first user, as the
rule for single-file helpers requires) rather than moving to the shared file.
`push_tier_files()` is used only inside `tests/merge_memory_repair_arrivals.bats`
(by one test, before its own textual definition further down — preserved
verbatim, matching the original file's order, since bash hoists function
definitions before the script body runs) and also stayed put.

`helpers/stub-synth` is loaded only by `tests/merge_memory_tiers.bats`
(the only file whose tests call `run_stub_synth`); the other four files drop
that `load` line since nothing in them uses it — the original loaded it
unconditionally, so this is a deliberate per-file trim per the brief's "the
`load` lines it needs".

## Deviations from the proposed partition

None in boundary placement — the five-way split matches the dispatch exactly.
The dispatch's quoted line numbers no longer matched the working tree (the
file had drifted between when the brief was written and when this split ran),
so tests were located by title instead; boundaries are unchanged.

Two mechanical follow-ons beyond a pure line move:

- `tests/merge_memory_repair_arrivals.bats` had `tier_gitdir_files()` and
  `repair_scratch_dirs()` defined at the top of its range (originally lines
  864–877); since both moved to the shared helper (multi-file use), the
  duplicate in-file definitions were dropped from this file's copy.
- `tests/helpers/merge-memory.bash` needed
  `# shellcheck disable=SC2034` on both `CMD` and `SESSION_START` — shellcheck
  linting the helper file alone can't see that they're consumed by the
  `.bats` files that `load` it. Matches the existing precedent in
  `tests/helpers/index-sync.bash:6` and `tests/helpers/triggers.bash:19`.

## References updated

`grep -rn 'merge_memory\.bats' docs/design.md docs/decisions.md docs/references scripts tests skills agents justfile CLAUDE.md`
hit three lines, all in `tests/killed_take_repro.bats` (a different suite that
copies `wire_memory_remote` and reuses `strand_live_ahead_of_pin`'s fixture
shape) — no hits elsewhere, and the justfile / `scripts/run-bats.sh` /
`tests/justfile_gates.bats` / `tests/plugin_distribution.bats` /
`docs/references/testing.md` do not enumerate suites by name (the one
`plugin_distribution.bats` hit for `merge-memory.sh` is the script, not this
test file).

- `tests/killed_take_repro.bats:14-17` — "reused by the same-shaped tests in
  tests/merge_memory.bats" repointed to name both
  `tests/merge_memory_tiers.bats` and `tests/merge_memory_repair_arrivals.bats`,
  the two files the `strand_live_ahead_of_pin`-shaped tests now live in.
- `tests/killed_take_repro.bats:41-43` — "Copied from tests/merge_memory.bats"
  repointed to `tests/helpers/merge-memory.bash`, where `wire_memory_remote`
  now actually lives, and reworded "every take test in that file" to "every
  take test in the merge_memory* suites".
- `tests/killed_take_repro.bats:73-75` — "every gitlore_adopt_advanced_live
  test in tests/merge_memory.bats" repointed to name
  `tests/merge_memory_tiers.bats` and `tests/merge_memory_repair_arrivals.bats`.

## Verification

1. Test names preserved:
   ```
   diff <(git show HEAD:tests/merge_memory.bats | grep '^@test' | sort) \
        <(cat tests/merge_memory.bats tests/merge_memory_tiers.bats tests/merge_memory_repair.bats tests/merge_memory_repair_arrivals.bats tests/merge_memory_fetch.bats | grep -h '^@test' | sort)
   ```
   Result: no output (clean).

2. No line lost:
   ```
   diff <(git show HEAD:tests/merge_memory.bats | sort) \
        <(cat tests/merge_memory.bats tests/merge_memory_tiers.bats tests/merge_memory_repair.bats tests/merge_memory_repair_arrivals.bats tests/merge_memory_fetch.bats tests/helpers/merge-memory.bash | sort) \
        | grep '^<'
   ```
   Result: one line — `< # The spaced-root cases re-root $TMP_REPO inside their own test body.`
   This is the deliberate reword: the original comment (plural "cases")
   covered two spaced-root scenarios in one file; after the split, only one
   spaced-root test remains in `tests/merge_memory_tiers.bats`, so its header
   comment says "case" (singular) — text confirmed present, just no longer
   byte-identical to the original line.

3. `wc -l` of every resulting file:
   ```
   292 tests/merge_memory.bats
   244 tests/merge_memory_tiers.bats
   320 tests/merge_memory_repair.bats
   275 tests/merge_memory_repair_arrivals.bats
   134 tests/merge_memory_fetch.bats
    62 tests/helpers/merge-memory.bash
   ```

4. `scripts/run-bats.sh tests/merge_memory.bats tests/merge_memory_tiers.bats tests/merge_memory_repair.bats tests/merge_memory_repair_arrivals.bats tests/merge_memory_fetch.bats`
   Result: `bats: 42 passed, 0 failed`. 42 matches
   `git show HEAD:tests/merge_memory.bats | grep -c '^@test'`.

5. `just lint`
   Result: `lint-shell: 141 files clean`.

6. `just test-unit` — **not confirmed by this agent.** Three attempts each
   ended without a clean readable verdict from this session:
   - First attempt (`timeout 590 just test-unit`, foreground) exceeded the
     tool's wait window and was moved to the background; its later
     completion notification reported `failed with exit code 143`
     (terminated), not a pass/fail from the recipe itself.
   - A gate-file poll (`until [ "$g" -nt tests/merge_memory.bats ]; do sleep
     15; done; timeout 30 just test-unit | head -3`) found the gate file
     already newer than the split's own input mtimes, but the following
     `timeout 30`/`timeout 60 just test-unit` calls each printed "Terminated"
     (exit 143) rather than a `cached (inputs unchanged)` line — inconclusive
     on whether the gate's content hash actually matches these files' current
     contents.
   - A full `scripts/run-bats.sh --jobs 4 tests/*.bats` run was started in the
     foreground and again exceeded the tool's wait window before finishing;
     its background id is `bezjld0gy`
     (`/tmp/claude-1000/-Users-david-code-gitlore/f525585e-baa9-47aa-87ee-1f6e5be1dfa5/tasks/bezjld0gy.output`).
   Per the team lead's instruction, this run was stopped rather than waited
   out further — **the main session is verifying `just test-unit` for this
   change.**

   Addendum: the `bezjld0gy` background task (the full
   `scripts/run-bats.sh --jobs 4 tests/*.bats`, not `just test-unit` itself)
   finished after this report was first written, with a completion
   notification landing on its own: `bats: 991 passed, 0 failed`. That covers
   the whole suite, not just this split, and is a `run-bats.sh` run rather
   than a `just test-unit` gate pass, so it does not by itself confirm the
   gate's cached-hash verdict — treat it as corroborating, not as the step 6
   verification the main session is doing.

   Steps 1–5 above passed cleanly in this agent's own runs.
