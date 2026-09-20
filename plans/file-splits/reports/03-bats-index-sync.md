# Split report — tests/index_sync.bats

## Final partition

| File | Lines | Tests |
|---|---|---|
| `tests/index_sync.bats` | 176 | 20 (index_pairs/set_frontmatter_description/get_frontmatter_description units + per-agent pre-image/compose-stamp paths) |
| `tests/index_sync_post.bats` | 334 | 18 (pre/post hook: stashing, agent keying, batch propagation, reporting, failure handling) |
| `tests/index_sync_propagation.bats` | 374 | 17 (unchanged/added/self-reference/traversal guards, hook wiring, e2e, per-agent race) |
| `tests/index_sync_relay.bats` | 264 | 6 (D51 relay markers, cases 1–5) |
| `tests/index_sync_relay_refusals.bats` | 308 | 10 (relay case 6–7, occupied-name/traversal refusals, robustness carryovers) |
| `tests/index_sync_advisories.bats` | 257 | 16 (has_literal, frontmatter_type, index budget, routing-key advisory channel) |
| `tests/helpers/index-sync.bash` | 32 | — (shared fixtures) |

Total: 87 tests, matching `git show HEAD:tests/index_sync.bats | grep -c '^@test'` (87). Every file is at or under the 380-line cap.

## Helper file contents (`tests/helpers/index-sync.bash`)

- `SRC` — path to `scripts/lib/index-sync.sh` (`# shellcheck disable=SC2034`: used only via `. "$SRC"` in each file's own `setup()` and by `bash -c '. "$1"' _ "$SRC" ...` calls in the relay suites, never read directly in this file).
- `PRE` — path to `scripts/cc-hooks/index-sync-pre.sh`.
- `POST` — path to `scripts/cc-hooks/index-sync-post.sh`.
- `pre_stdin()` — feeds a payload to `$PRE` via stdin.
- `post_stdin()` — feeds a payload to `$POST` via stdin.
- `batch_payload()` — builds a `PostToolBatch` JSON payload from file-path arguments, honoring `TEST_SESSION_ID`/`TEST_AGENT_ID`/`TEST_AGENT_TYPE` env overrides.

Loaded by every resulting file with `load helpers/index-sync`, alongside the pre-existing `load helpers/setup` and `load helpers/fixtures` (which already supplied `make_parent_with_memory`, `_gitlore_build_parent_with_memory` and `relay_marker_for` — no new fixture file needed for those).

## Deviations from the proposed partition

None in test placement — every `@test` landed in the file the dispatch named, at the line boundaries given (109→post, 454→propagation, 815→kept in the original file, 884→relay, 1137→relay_refusals, 1431→advisories).

One addition beyond the dispatch's explicit helper list: `PRE`, `POST`, `pre_stdin`, `post_stdin` and `batch_payload` are shared across three of the five hook-test files (`index_sync_post.bats`, `index_sync_propagation.bats`, `index_sync_advisories.bats` — the last needs `post_stdin`/`batch_payload` for its "post: ..." advisory-channel cases even though it carries no pre/post *hook mechanics* tests). Per the brief's shared-setup rule ("a helper function used by more than one resulting file moves to `tests/helpers/<suite>.bash`"), all five moved to the new helper file rather than being duplicated or left only in `index_sync_post.bats`.

Each split file's `# shellcheck disable=SC2030,SC2031` header line, present in the original for its `export CLAUDE_PLUGIN_ROOT=...`/`PATH=...` reassignments inside `@test` blocks, was re-added to every file that still contains such a reassignment (`index_sync_post.bats`, `index_sync_propagation.bats`, `index_sync_relay_refusals.bats`, `index_sync_advisories.bats`) — confirmed by re-running lint after the first pass flagged the omission. `index_sync.bats` and `index_sync_relay.bats` also carry it: the former for its `PATH="$fakebin:$PATH" run ...` case, kept from the original disable; the latter has no such reassignment and does not need it (and does not carry it).

`bats_require_minimum_version 1.5.0` (needed for `run --separate-stderr`) is kept only in `tests/index_sync_post.bats` and `tests/index_sync_propagation.bats`, the two files whose tests use that form. No other resulting file uses it.

## References updated

None. `justfile`, `scripts/run-bats.sh`, `tests/justfile_gates.bats`, `tests/plugin_distribution.bats` and `docs/references/testing.md` all discover unit suites via `tests/*.bats` globbing (`justfile:150`) rather than enumerating `index_sync.bats` by name — confirmed by `grep -n "index_sync" justfile scripts/run-bats.sh tests/justfile_gates.bats tests/plugin_distribution.bats docs/references/testing.md`, which returned nothing. The only in-repo mentions of `tests/index_sync.bats` by name are historical, in the frozen plan `plans/2026-07-15-index-frontmatter-sync.md` — left untouched, since that document records what was done at the time, not current file layout.

## Verification

1. Test names preserved:
   ```
   diff <(git show HEAD:tests/index_sync.bats | grep '^@test' | sort) \
        <(cat tests/index_sync.bats tests/index_sync_post.bats tests/index_sync_propagation.bats \
              tests/index_sync_relay.bats tests/index_sync_relay_refusals.bats tests/index_sync_advisories.bats \
          | grep -h '^@test' | sort)
   ```
   Result: no output — `TEST NAMES MATCH` printed by the trailing `&&`.

2. No line lost:
   ```
   diff <(git show HEAD:tests/index_sync.bats | sort) \
        <(cat tests/index_sync.bats tests/index_sync_post.bats tests/index_sync_propagation.bats \
              tests/index_sync_relay.bats tests/index_sync_relay_refusals.bats tests/index_sync_advisories.bats \
              tests/helpers/index-sync.bash | sort) \
   | grep '^<'
   ```
   Result: no output — every original line accounted for in the union.

3. `wc -l` of every resulting file: see the table above (176 / 334 / 374 / 264 / 308 / 257 / 32).

4. `scripts/run-bats.sh tests/index_sync.bats tests/index_sync_post.bats tests/index_sync_propagation.bats tests/index_sync_relay.bats tests/index_sync_relay_refusals.bats tests/index_sync_advisories.bats`:
   ```
   bats: 87 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.F1AC8Q
   ```
   87 matches `git show HEAD:tests/index_sync.bats | grep -c '^@test'` (87).

5. `just lint`:
   ```
   lint-shell: 141 files clean
   ```
   (A second invocation reported `lint: cached (inputs unchanged)`, confirming the pass was recorded.)

6. `just test-unit` (run in the background per the 10-minute foreground cap; the completion notification carried exit code 0):
   ```
   bats: 976 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.ssBlJx
   ```
   Full unit suite green, including the six index-sync files above.
