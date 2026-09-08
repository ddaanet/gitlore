# Item 3.1 slice 2.5 — GREEN

One function changed: `gitlore_relay_write` in `scripts/lib/index-sync.sh`. Both
tests pass; nothing else touched.

## The change

When the marker already exists (`[ -f "$marker" ]`), the two channels are read
in full — with the same awk split `gitlore_relay_drain` uses — into `old_sys`
and `old_ctx` *before* the marker is opened for output. The new `sysmsg`/`ctx`
are then reassigned to `old_sys`$'\n'`sysmsg` / `old_ctx`$'\n'`ctx` (old first,
so write order is preserved), and the existing write block runs unchanged on the
merged values. When no marker exists, the `if` is skipped entirely and the
function takes exactly the path it always did.

**Why the read must finish before the write opens the file.** `old_sys` and
`old_ctx` are captured by `$(awk … "$marker")` command substitutions, each of
which forks, reads the file to EOF, and returns a plain string — by the time
`sysmsg`/`ctx` are reassigned, the file is fully read and closed, and no process
still holds it open. Only after that does the `{ … } > "$marker"` block run, so
the redirect's truncate-on-open never races the read. This is two separate
commands in sequence, never a read and a redirect to the same path in one
command — the failure mode the dispatch called out.

## Per test, what made it pass

**`relay_write merges a second report into an existing marker`**
(`tests/index_sync.bats:973`): all four assertions passed on the first run after
the change — no intermediate red state, since the fresh-write path was already
correct and the merge path was written directly from the mutation table's
constraints (append, not prepend; both channels, not one; no second marker; no
drift in the fresh-write bytes).

- Marker bytes after the first write (`:988`): unaffected by the change — the
  `if` is false on a fresh marker, so this is the pre-existing single-write
  path, byte for byte.
- Marker count of 1 before the drain (`:1012`): satisfied because
  `gitlore_relay_marker_file "$mempath" "$agent_id"` resolves to the same path
  both times for the same agent id, and the second call's `if` branch merges
  into it rather than opening a second name.
- `GITLORE_RELAY_SYSMSG` exact block (`:1027`): the drain's sysblock for the
  merged marker is `S1\nS2` (old body, newline, new body), framed by the drain
  into `--- gitlore-relay agent a1 ---\nS1\nS2\n` — the literal the test pins.
- `GITLORE_RELAY_CTX` exact block (`:1031`): same shape, `C1\nC2`.

**`both PostToolBatch hooks in one keyed batch reach the parent`**
(`tests/cc_hook_index_compose.bats:373`): passed on the first run after the
change. `index-sync-post.sh` writes its report to the `a1` marker;
`index-compose.sh`'s later write in the same batch now merges into it instead of
truncating it, so the unkeyed parent-side drain finds both "reset frontmatter to
match MEMORY.md" and "recomposed tier pointers" in the folded `systemMessage`.
Neither hook script was touched — both already called `gitlore_relay_write` with
their own report; the fix is entirely inside the helper they share.

## Fresh-marker byte-identity (the M9 constraint)

Confirmed both by reasoning and by the test's own byte-exact assertion at
`:988`, which ran and passed: with no marker on disk, the `if [ -f "$marker" ]`
body never executes, so `sysmsg`/`ctx` reach the write block exactly as passed
in, and the write block itself is character-for-character what it was before
this change. The first `gitlore_relay_write memory a1 "S1" "C1"` call in the
test produces
`--- gitlore-relay-sysmsg ---\nS1\n--- gitlore-relay-ctx ---\nC1\n` on disk,
matching the test's `$(cat "$marker")` literal exactly (trailing newline
stripped by the substitution, as documented in the test's own comment).

## Scope discipline

Only `scripts/lib/index-sync.sh` was edited (`gitlore_relay_write` and its
comment). `gitlore_relay_drain` and `gitlore_relay_marker_file` are unchanged —
the merge did not need them, since the drain's existing awk split already parses
whatever `gitlore_relay_write` now produces. Neither `.bats` file was touched.
No hook script under `scripts/cc-hooks/` was touched. Nothing under `docs/`,
`memory/`, or `plans/` besides this report. Nothing committed, tree left dirty
and unstaged (`git status --short` shows only the two frozen test files, this
file, and the SUT edit).

The updated comment cites no `plans/` or `memory/` path — only the mechanism and
the reason, matching the rest of the file's comment density and idiom
(multi-line string literals for framed blocks, `$(...)` for awk-captured channel
bodies, same as `gitlore_relay_drain` already uses).

## Checks that passed, by name

- `bats -f "relay_write merges a second report into an existing marker" tests/index_sync.bats`
  — 1 passed.
- `bats -f "both PostToolBatch hooks in one keyed batch reach the parent" tests/cc_hook_index_compose.bats`
  — 1 passed.
- `scripts/run-bats.sh tests/index_sync.bats tests/cc_hook_index_compose.bats` —
  101 passed, 0 failed.
- `scripts/run-bats.sh tests/cc_hook_session_start.bats tests/cc_hook_add_tier.bats tests/index_compose.bats tests/cc_hook_post_tool_use.bats tests/lib_util.bats`
  — 130 passed, 0 failed.
- `shellcheck -s bash scripts/lib/index-sync.sh` — clean.
- `scripts/lint-shell.sh` — 137 files clean.
- `git status --short` — only `scripts/lib/index-sync.sh` modified beyond the
  frozen, pre-existing diffs to `tests/cc_hook_index_compose.bats` and
  `tests/index_sync.bats`; nothing committed or staged.
