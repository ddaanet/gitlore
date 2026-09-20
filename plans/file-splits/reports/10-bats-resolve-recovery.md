# Split: tests/resolve_recovery.bats

## Final partition

### `tests/resolve_recovery.bats` — 305 lines, 12 tests
Kept as the "one cohesive group": continued preparations, the
interrupted-preparation section, and the checkout-cleared MERGE_HEAD section.

- recovery: a prepared merge met by a later gate is continued, not discarded
- recovery: /gitlore:resolve continues a prepared merge rather than re-preparing it
- recovery: a merge prepared in an earlier session lands through the continuation
- recovery: a merge that never started is reported, not announced as prepared
- recovery: the state file is written before the preparation starts, and cleared when it fails
- recovery: a preparation interrupted after its merge staged is completed by the next gate, not flagged
- recovery: a preparation interrupted before its merge ran is discarded, and the gate re-prepares it
- recovery: MERGE_HEAD with no state file is a merge gitlore did not prepare, and blocks
- recovery: a checkout-cleared merge that nothing landed is discarded, and the gate re-prepares it
- recovery: /gitlore:resolve repairs a checkout-cleared merge instead of refusing over it
- recovery: a checkout-cleared merge with its synthesis staged keeps it and asks for the sub-agent
- recovery: a merge that landed before the checkout is restored, not declared dead

### `tests/resolve_recovery_landed.bats` — 129 lines, 4 tests
The two rc-0 branches of `gitlore_recover_landed_merge`'s gitlink staging, and
adoption idempotency/scope.

- recovery: a landed tier merge stages the moved gitlink in the memory store's index
- recovery: the branch where HEAD already carries the landed merge stages it too
- recovery: adoption is a no-op when the enclosing index already records the tier's HEAD
- recovery: the same recovery for the memory root stages nothing in the parent repo

### `tests/resolve_recovery_landed_commit.bats` — 248 lines, 7 tests
The rest of the landed-tier-merge section: the pin guard letting a follow-up
memory commit through, staging-failure reporting, the host-project exclusion,
upstream-text preservation through adoption, and the "cannot take" refusal —
plus the two tests that close out the original file (a checkout-cleared
merge whose authority moved, and an unclassifiable stale merge state), which
land here only because the brief's cut point falls before them, not because
they share the landed-tier-merge topic. See Deviations.

- recovery: after the recovery, a memory commit runs to completion instead of aborting on the pin guard
- recovery: a staging failure for a landed tier merge is reported, and the recovery still returns 0
- recovery: a host project that keeps a root MEMORY.md is not a memory store
- recovery: the upstream text a landed tier merge brought in survives the commit that adopts it
- recovery: a landed tier merge the root index cannot take is left unstaged
- recovery: a checkout-cleared merge whose HEAD is not the authority names both shas
- recovery: a stale merge state naming no pending commit is reported, not guessed at

### `tests/helpers/resolve-recovery.bash` — 45 lines
- `RESOLVE`/`PRE_COMMIT` file-level path variables (`RESOLVE` unused within
  the helper itself, so carries `# shellcheck disable=SC2034`)
- `setup()` — `setup_tmp_repo`; export `CLAUDE_PLUGIN_ROOT`; `make_parent_with_memory`; `git config gitlore.hooksDir`
- `teardown()` — `teardown_tmp_repo`
- `tier_prepare_head_vs_live()` — diverges a tier from its own `live` and
  prepares the merge through the real hook; called from both
  `resolve_recovery_landed.bats` and `resolve_recovery_landed_commit.bats`

## Deviations from the proposed partition

The cut points (26–318 kept, 320–463 and 464–699 for the two landed files)
matched the brief's proposed line ranges exactly and produced files at
305/129/248 lines, all comfortably under 380 — no further cut was needed.

Content deviations, both required by the split:
- `tier_prepare_head_vs_live`'s doc comment used `# --- Item 1.3 slice 1: ...
  ---` banner delimiters in the original, marking it as a section header
  inside the single file. Moved to the helper, it is now a plain function
  doc comment (no `---` delimiters) rather than a section banner, since the
  helper file is not divided into banner-marked sections.
- The original file-header carried `# shellcheck disable=SC2030,SC2031` with
  a comment explaining it was for `tier_prepare_head_vs_live`'s `run`. That
  function moved to the helper, and `just lint` reports the resulting files
  (including the helper) clean without the disable, so it was dropped rather
  than carried forward unused.
- Did not rename `resolve_recovery_landed_commit.bats` despite its last two
  tests not being about a landed commit — noted above in the file's summary
  rather than invented a name that would misdescribe the other five.

## References updated

None. The `grep -rn 'resolve_recovery\.bats' docs/design.md docs/decisions.md
docs/references scripts tests skills agents justfile CLAUDE.md` sweep found
two hits, both in `tests/tier_divergence.bats:208` and
`tests/index_compose_pins_edge.bats:123`, citing the checkout-cleared
MERGE_HEAD / stale-state-guard mechanism by way of example — that mechanism's
tests stayed in the retained `tests/resolve_recovery.bats`, so both citations
are still accurate and needed no change. No enumeration hits in `justfile`,
`scripts/run-bats.sh`, `tests/justfile_gates.bats`,
`tests/plugin_distribution.bats`, or `docs/references/testing.md`. `plans/`
hits are out of scope per the brief and left untouched.

## Verification

1. Test names preserved:
   ```
   $ diff <(grep '^@test' "$TMPDIR/resolve_recovery.orig.bats" | sort) \
          <(cat tests/resolve_recovery.bats tests/resolve_recovery_landed.bats tests/resolve_recovery_landed_commit.bats | grep -h '^@test' | sort)
   (no output)
   ```
2. No line lost (only the deliberate rewording noted above survives the filter):
   ```
   $ diff <(sort "$TMPDIR/resolve_recovery.orig.bats") \
          <(cat tests/resolve_recovery.bats tests/resolve_recovery_landed.bats tests/resolve_recovery_landed_commit.bats tests/helpers/resolve-recovery.bash | sort) | grep '^<'
   < # --- Item 1.3 slice 1: gitlore_recover_landed_merge stages the gitlink it
   < # Each @test is its own subshell, and tier_prepare_head_vs_live's `run` is
   < # consumed within that same test, so SC2030/SC2031 are false positives here.
   < # meet the pin guard on a tier gitlore itself just left ahead. ---
   < # shellcheck disable=SC2030,SC2031
   ```
   All five lines are the banner-delimiter and now-unneeded shellcheck-disable
   text described above.
3. `wc -l` of every resulting file:
   ```
   $ wc -l tests/resolve_recovery.bats tests/resolve_recovery_landed.bats tests/resolve_recovery_landed_commit.bats tests/helpers/resolve-recovery.bash
     305 tests/resolve_recovery.bats
     129 tests/resolve_recovery_landed.bats
     248 tests/resolve_recovery_landed_commit.bats
      45 tests/helpers/resolve-recovery.bash
   ```
4. `scripts/run-bats.sh` pass count equals the original's `@test` count (23):
   ```
   $ scripts/run-bats.sh tests/resolve_recovery.bats tests/resolve_recovery_landed.bats tests/resolve_recovery_landed_commit.bats
   bats: 23 passed, 0 failed — full log: /tmp/claude-1000/gitlore-bats.KJytoa
   ```
5. `just lint`, run once for both suites in this dispatch:
   ```
   $ just lint
   lint-shell: 141 files clean
   ```
6. `just test-unit` not run, per brief step 6 — the main session runs it.
