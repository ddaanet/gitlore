# Item 3.1 — slice 1 GREEN

All three stubs in `scripts/lib/index-sync.sh` replaced with real
implementations. `tests/index_sync.bats` was not touched.

## Per-test change

**`relay_marker_file suffixes the agent id`** — `gitlore_relay_marker_file` now
calls `_gitlore_agent_suffix "${2:-}"` exactly as
`gitlore_index_preimage_file`/`gitlore_compose_stamp_file` do, instead of always
returning the bare `gitlore-relay` path. Passes alone and in the full run.

**`relay_write then relay_drain splits the two channels and removes the marker`**
— two changes:

- `gitlore_relay_write` now resolves the keyed marker via
  `gitlore_relay_marker_file`, returns 1 without writing if that resolution
  fails, and writes both bodies in one redirected group
  (`{ printf delim; printf sysmsg; printf delim; printf ctx; } > "$marker"`) — a
  single `>` open, so a failed open (e.g. the marker path already occupied by a
  directory, per slice 4) leaves nothing on disk.
- `gitlore_relay_drain` now finds keyed markers under the gitdir with
  `find -maxdepth 1 -name 'gitlore-relay-*' -print0`, reads each with `awk`
  split on the two literal delimiter lines into `GITLORE_RELAY_SYSMSG` /
  `GITLORE_RELAY_CTX`, frames each block with a
  `--- gitlore-relay agent <id> ---` line, and `rm -f`s the marker after folding
  it in.

**`relay_drain folds two markers in filename order, over a gitdir path holding a space`**
— same drain implementation; the enumeration is `find ... -print0` into a bash
array (`read -r -d ''`, whitespace-safe for the spaced gitdir prefix), then the
array is joined on newline and piped through plain `sort` before folding, so the
fold order is deterministic (`gitlore-relay-a1` sorts before `gitlore-relay-a2`)
regardless of `find`'s own directory-entry order.

**`relay_drain on an empty store sets both variables empty and returns 0`** —
unaffected; still passes. `GITLORE_RELAY_SYSMSG`/`GITLORE_RELAY_CTX` are
assigned `""` unconditionally at the top of `gitlore_relay_drain` before the
enumeration runs, so the sentinel values are cleared even on the empty-store
path, and the decoy compose-stamp file survives because the glob is
`gitlore-relay-*`, never `gitlore-*`.

## Decision: the unsuffixed `gitlore-relay` marker

`gitlore_relay_drain` enumerates only `gitlore-relay-*` (suffixed/keyed markers)
— the bare `gitlore-relay` name is never matched by the glob and is left
untouched if it somehow existed. Two reasons, both stated in the function's
comment block:

1. Nothing in production ever writes the unsuffixed name — the hooks call
   `gitlore_relay_write` only when an agent id is present (per the dispatch), so
   the bare marker is a dead input for the drain in the current design.
2. The runbook's own wording says the drain "removes every **keyed** marker in
   the memory gitdir" — the glob scope follows the interface text directly
   rather than inventing a broader one.

This is a deliberate no-op on that input, not an oversight; no test was added
for it per the dispatch's instruction to leave that as an orchestrator scope
call.

## Sorting note (portability)

`gitlore_relay_drain`'s filename-order fold joins the marker array on newline
and pipes through a plain (non-`-z`) `sort`, rather than
`sort -z`/`find -print0 | sort -z`, because BSD `sort` (macOS) has no `-z`. This
is safe for this path class specifically: `_gitlore_agent_suffix` sanitizes the
agent-id portion of the filename to `[A-Za-z0-9-]`, so no marker filename can
itself contain a newline, and `sort` treats each joined line — including one
with an embedded space from the gitdir prefix — as one opaque sort key. The
enumeration step itself (`find -print0` into a `read -r -d ''` loop) remains
fully NUL-delimited and is what the spaced-path test exercises.

## Checks that passed, by name

- `bats -f "relay_marker_file suffixes the agent id" tests/index_sync.bats` — ok
- `bats -f "relay_write then relay_drain splits the two channels and removes the marker" tests/index_sync.bats`
  — ok
- `bats -f "relay_drain folds two markers in filename order, over a gitdir path holding a space" tests/index_sync.bats`
  — ok
- `bats -f "relay_drain on an empty store sets both variables empty and returns 0" tests/index_sync.bats`
  — ok
- `./scripts/run-bats.sh tests/index_sync.bats` — 75 passed, 0 failed
- `shellcheck -s bash tests/index_sync.bats` — clean, exit 0
- `shellcheck -s bash scripts/lib/index-sync.sh` — clean, exit 0
- `./scripts/lint-shell.sh` — 137 files clean
- `./scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/index_sync.bats tests/cc_hook_session_start.bats tests/cc_hook_add_tier.bats`
  — 124 passed, 0 failed
- `git status --short` — only `scripts/lib/index-sync.sh` modified beyond what
  was already dirty at dispatch (`tests/index_sync.bats` and the two report
  files from RED/test-review); nothing committed, nothing staged
