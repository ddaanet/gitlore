# Split: scripts/lib/util.sh

Moved the tail group — `gitlore_tier_paths`, `gitlore_active_tiers`,
`gitlore_active_tier_scopes`, `gitlore_memory_remote_name`,
`gitlore_memory_approval_clause`, `gitlore_parent_visibility` (original lines
357–474, each with its comment block) — verbatim into
`scripts/lib/util-config.sh`. Named `util-config.sh`, not `util-tiers.sh`: only
the first three are about tiers (discovery/listing); the last three are
remote-name derivation, the approval-clause template, and visibility —
collectively "store configuration" rather than tiers specifically. Moving only
the first three (68 lines) would leave `util.sh` at 406 lines, still over the
380 cap, so all six had to move regardless of naming; the rename reflects that.

`util.sh` sources it right after its own header with the standard two-line
form, and the header gained: "Tier and remote/publishing config helpers live
in util-config.sh, sourced below. It is function-only (safe to source twice,
unlike this file), so definition order between the two files does not
matter." `util-config.sh`'s own header states the same function-only/safe-
to-source-twice property and what it covers.

## Function-only check

All six moved functions are ordinary functions with only local state — no
`readonly`, no top-level assignment — confirmed by reading the extracted
range before writing the new file. `util-config.sh` is therefore safe to
source twice, unlike `util.sh` (which still declares
`GITLORE_SUBMODULE_NAME`, `GITLORE_PLACEHOLDER_URL`, `GITLORE_MIGRATION_MARKER`,
`GITLORE_PENDING_REF`, all `readonly`).

`tests/helpers/setup.bash` sources every `scripts/lib/*.sh` by glob
(alphabetical: `util-config.sh` sorts before `util.sh` since `-` < `.` in
ASCII) — so it sources `util-config.sh` directly once, then `util.sh` a
moment later, whose own `source` line re-sources `util-config.sh` a second
time. Harmless: function-only files tolerate re-sourcing, redefining the same
functions.

## References updated

- `scripts/cc-hooks/index-compose.sh:9` — comment attributing
  `gitlore_active_tier_scopes` to `(util.sh)` now says `(util-config.sh)`.
- `scripts/lib/index-compose.sh:228` — same attribution, same fix.
- `docs/references/commit-gate.md:184` — `gitlore_memory_approval_clause()`
  was cited as `scripts/lib/util.sh`; now `scripts/lib/util-config.sh`.
- `docs/references/commit-gate.md:216–223` ("resolve.sh reaches the clause
  through its callers, never by sourcing util.sh itself... source util.sh
  first, so gitlore_memory_approval_clause is in scope") — left unchanged:
  still literally true, since `util.sh` sources `util-config.sh` and callers
  that source `util.sh` still bring the function into scope.
- `tests/index_compose.bats:9` ("gitlore_tier_paths / gitlore_active_tiers
  come from [load helpers/setup, which sources every scripts/lib/*.sh].
  Re-sourcing util.sh here would fail on its readonly constants") — left
  unchanged: still accurate, `load helpers/setup` sources `util-config.sh`
  (directly, by glob) as part of "every scripts/lib/*.sh".
- No hits in `docs/design.md` or `docs/decisions.md` for any of the six
  function names.
- All other hits (`scripts/add-tier.sh`, `scripts/push-memory.sh`,
  `scripts/emit-memory-gate.sh`, `scripts/cc-hooks/session-start.sh`,
  `scripts/lib/index-compose-check.sh`, `scripts/lib/index-compose-project.sh`,
  `scripts/lib/resolve*.sh`, `scripts/install/create-remote.sh`,
  `scripts/cc-hooks/memory-commit-batch.sh`, `scripts/cc-hooks/post-tool-use.sh`,
  various `.bats` files, `docs/changelog/*`, `docs/references/tiered-memory.md`)
  are plain calls or generic mentions that name no source file — nothing to
  update.

## Verification

**1. No line lost:**
```
$ diff <(sort "$TMPDIR/util.sh.orig") <(cat scripts/lib/util.sh scripts/lib/util-config.sh | sort) | grep '^<'
(no output)
```

**2. Function equivalence** (`declare -f` dump over every `gitlore_*` name,
sourcing only `log.sh` then the file under test, since `util.sh`'s own
`readonly` globals make a from-scratch old/new comparison exact):
```
$ cmp "$TMPDIR/df-old-b.txt" "$TMPDIR/df-new-b.txt" && echo identical
identical
```

**3. Line counts:**
```
$ wc -l scripts/lib/util.sh scripts/lib/util-config.sh
  362 scripts/lib/util.sh
  129 scripts/lib/util-config.sh
```
Both ≤ 380.

**4. Targeted suite.** `tests/util*.bats` matched nothing — the actual file
is `tests/lib_util.bats` — substituted that. Ran via `scripts/run-bats.sh`:
```
tests/lib_util.bats tests/tier_discovery.bats tests/tier_divergence.bats
tests/tier_divergence_continuation.bats tests/tier_lockstep.bats
tests/add_tier.bats tests/add_tier_intent.bats
```
Result: `bats: 123 passed, 0 failed`. (Two unrelated sandbox network-egress
denials logged during the run — localhost ports 1 and 22, from an unrelated
test's negative-path probe — are not test failures.)

**5.** `just lint`, run once at the end after all three files:
```
lint-shell: 141 files clean
```
