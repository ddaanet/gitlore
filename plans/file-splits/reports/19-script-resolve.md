# Split: scripts/resolve.sh

Moved the four continuation functions — `load_continuation_state` (original
lines 25–64, comment included), `compose_merged_indexes` (66–196),
`rest_unadopted_tier` (198–254), `push_or_report` (256–290) — as one
contiguous verbatim block (lines 25–290) into `scripts/lib/continuation.sh`.
`scripts/resolve.sh` sources it right after its existing four `source` lines
with `source "$PLUGIN_ROOT/scripts/lib/continuation.sh"`, matching the
absolute-path form its siblings use in that block. The new file's header
states, in its own words after reading all four functions: "Sourced by
scripts/resolve.sh only; its functions set that script's globals (mempath,
memroot, statefile, flavor, publish, merged_tier, tier_unadopted) and exit
on its behalf." `resolve.sh`'s own header gained one sentence naming the
split. `continuation.sh` is non-executable (`-rw-r--r--`), matching the other
`scripts/lib/*.sh` files.

`check_store_gates` was not moved — it stays in `scripts/resolve.sh`, as
instructed.

## Global/exit contract

All four functions read and set `resolve.sh`'s top-level variables rather
than taking/returning them as parameters: `load_continuation_state` sets
`memroot`, `mempath`, `statefile`, `flavor`, `publish`;
`compose_merged_indexes` sets `merged_tier`, `tier_unadopted`; several call
sites in the `continue-after-merge` dispatch (still in `resolve.sh`, after
the split) read those same names back. All four also `exit` directly on
several paths rather than returning a status the caller checks. This is
unchanged by the move — bash functions share the calling script's global
scope and its process regardless of which file defined them, once sourced —
but it means the two files are coupled by convention, not by an interface;
`continuation.sh`'s header says so.

## Test-helper name collision check

Grepped `tests/` for the four function names and for `merged_tier=`/
`tier_unadopted=` assignments outside the moved code: no hits. No collision.

## References updated

- `docs/references/tier-arrival-repair.md:126` mentions `compose_merged_indexes`
  by name only, with no file attribution — left unchanged.
- No hits for any of the four function names in `docs/design.md` or
  `docs/decisions.md`.
- Every other reference to `scripts/resolve.sh` in `tests/` and `scripts/`
  invokes it as a script (`bash "$RESOLVE"`, `RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"`,
  a printed remedy command) — none of these read its content as text, so
  none needed a change.

## FILE-AS-DATA: push_rejection_discriminator.bats

`push_or_report` carries the pinned rejection-classification pattern
(`"(fetch first)"*|*"(non-fast-forward)"`), which moved out of
`scripts/resolve.sh` into `scripts/lib/continuation.sh`. Confirmed with the
test's own grep:
```
$ grep -c -e '"(fetch first)"\*|\*"(non-fast-forward)"' -e '\*non-fast-forward\*|\*"fetch first"\*' scripts/resolve.sh scripts/lib/continuation.sh
scripts/resolve.sh:0
scripts/lib/continuation.sh:1
```
Updated `tests/push_rejection_discriminator.bats`'s `for site in …` loop in
the "every discriminating site still keys on the pinned patterns" test:
replaced `scripts/resolve.sh` with `scripts/lib/continuation.sh` in the list
of files asserted to carry the pattern. Checked the test's later assertions
(pre-push delegates, session-start compares ancestry instead) — neither
names `scripts/resolve.sh`, so nothing else needed a change. Grepped `tests/`
and `scripts/` for any other test reading `scripts/resolve.sh` as text
(`grep`/`sed`/`awk` over the path, or `"$RESOLVE"` used that way) — none
found; every other reference invokes the script.

## Verification

**1. No line lost:**
```
$ diff <(sort "$TMPDIR/resolve.sh.orig") <(cat scripts/resolve.sh scripts/lib/continuation.sh | sort) | grep '^<'
(no output)
```

**2. `bash -n` and function-body equivalence** (sourcing the old file is not
possible — it executes — so extracted each of the four function bodies by
name from the pre-split copy and the new file and compared verbatim):
```
$ bash -n scripts/resolve.sh scripts/lib/continuation.sh && echo OK
OK
$ for f in load_continuation_state compose_merged_indexes rest_unadopted_tier push_or_report; do
    cmp "$TMPDIR/old-$f.txt" "$TMPDIR/new-$f.txt" && echo "$f: identical"
  done
load_continuation_state: identical
compose_merged_indexes: identical
rest_unadopted_tier: identical
push_or_report: identical
```

**3. Line counts:**
```
$ wc -l scripts/resolve.sh scripts/lib/continuation.sh
  267 scripts/resolve.sh
  275 scripts/lib/continuation.sh
```
Both ≤ 380.

**4. Targeted suites**, via `scripts/run-bats.sh`, split across two
foreground calls (each backgrounded automatically past the 120s Bash
foreground wait, then awaited):

Batch 1 — `tests/resolve.bats tests/resolve_both_flavors.bats
tests/resolve_compose.bats tests/resolve_compose_continuation.bats
tests/resolve_compose_refusals.bats tests/resolve_compose_root_index.bats
tests/resolve_merge_briefing.bats tests/resolve_merge_local.bats
tests/resolve_merge_remote.bats`:
```
bats: 56 passed, 0 failed
```

Batch 2 — `tests/resolve_recovery.bats tests/resolve_recovery_landed.bats
tests/resolve_recovery_landed_commit.bats tests/tier_divergence.bats
tests/tier_divergence_continuation.bats tests/push_rejection_discriminator.bats
tests/merge_memory.bats tests/merge_memory_fetch.bats
tests/merge_memory_repair.bats tests/merge_memory_repair_arrivals.bats
tests/merge_memory_tiers.bats tests/plugin_distribution.bats`:
```
bats: 109 passed, 0 failed
```

**5.** `just lint`, run once at the end after all three files:
```
lint-shell: 141 files clean
```
