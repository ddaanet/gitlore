# Split: scripts/lib/index-sync.sh

Moved the relay-marker group — `gitlore_relay_write`, `gitlore_relay_drain`,
`gitlore_relay_sweep`, `_gitlore_relay_sysblock`, `_gitlore_relay_ctxblock`
(original lines 111–292) — verbatim into `scripts/lib/index-sync-relay.sh`,
with a new four-line header (`#!/usr/bin/env bash` + a three-line comment
naming the group and "Part of lib/index-sync.sh; source that, not this
file."). `index-sync.sh` sources it with
`# shellcheck disable=SC1091` + `source "${BASH_SOURCE[0]%/*}/index-sync-relay.sh"`
right after `gitlore_compose_stamp_file`, and its own header comment gained
one sentence: "The relay-marker group lives in index-sync-relay.sh, sourced
below."

## Dependency check

`_gitlore_sanitize_id` is called by the relay group (`gitlore_relay_write`,
`gitlore_relay_drain`) AND by `_gitlore_agent_suffix`, which stays in
`index-sync.sh` (used by `gitlore_index_preimage_file` /
`gitlore_compose_stamp_file`, not part of the moved group) — so it remained in
`index-sync.sh`. Bash resolves function calls at call time, so definition
order across the two files does not matter as long as both are sourced before
either group runs, which they are.

## Sourcing sites verified

All hooks and helpers source `index-sync.sh` only (never call the relay
functions from a file that doesn't), so the new `source` line inside
`index-sync.sh` covers every one of them without changes:
`scripts/cc-hooks/{relay-drain,index-sync-pre,index-sync-post,index-compose,
nudge-reset,add-tier-batch,plugin-upgrade-batch,session-start}.sh`,
`scripts/add-tier.sh`, `tests/helpers/index-sync.bash` (sets `SRC` to
`index-sync.sh` only). `tests/helpers/setup.bash` sources every
`scripts/lib/*.sh` by glob, so it will also source `index-sync-relay.sh`
directly — harmless since it is function-only (no `readonly`, no top-level
state), same shape as the existing `resolve-*.sh` parts.
`${BASH_SOURCE[0]%/*}` resolves correctly in both cases since both files live
in `scripts/lib/`.

## References updated

- `scripts/lib/index-compose-check.sh:31` — a comment citing
  `index-sync.sh:186-189` (the `gitlore_relay_write` mv/existence-check
  shape) now cites `index-sync-relay.sh:77-81`, the same check's new
  location.
- No hits for the five moved function names in `docs/design.md`,
  `docs/decisions.md`, or `docs/references/`.
- `util.sh:405` and `index-compose.sh:229` cite `index-sync.sh` for
  `gitlore_get_frontmatter_description`, which was not moved — left as is.

## Verification

**1. No line lost:**
```
$ diff <(sort "$TMPDIR/index-sync.sh.orig") <(cat scripts/lib/index-sync.sh scripts/lib/index-sync-relay.sh | sort) | grep '^<'
(no output)
```

**2. Function equivalence** (`declare -f` dump over every `gitlore_*` name,
old file vs new pair):
```
$ cmp "$TMPDIR/df-old.txt" "$TMPDIR/df-new.txt" && echo identical
identical
```

**3. Line counts:**
```
$ wc -l scripts/lib/index-sync.sh scripts/lib/index-sync-relay.sh
  288 scripts/lib/index-sync.sh
  187 scripts/lib/index-sync-relay.sh
```
Both ≤ 380.

**4. Targeted suite** (`scripts/run-bats.sh`):
```
tests/index_sync.bats tests/index_sync_advisories.bats tests/index_sync_post.bats
tests/index_sync_propagation.bats tests/index_sync_relay.bats tests/index_sync_relay_refusals.bats
tests/cc_hook_index_compose.bats tests/cc_hook_index_compose_notices.bats
tests/cc_hook_index_compose_relay.bats tests/cc_hook_session_start.bats
tests/cc_hook_session_start_relay.bats
```
Result: `bats: 144 passed, 0 failed`

**5.** `just lint`, run once at the end after all three files:
```
lint-shell: 141 files clean
```
