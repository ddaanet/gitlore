# Item 3.1 — slice 1 RED

Stubs landed in `scripts/lib/index-sync.sh` (beside
`gitlore_index_preimage_file` and `gitlore_compose_stamp_file`, before
`_gitlore_agent_suffix`):

- `gitlore_relay_marker_file` — always prints the unsuffixed `gitlore-relay`
  path, ignoring `$2`.
- `gitlore_relay_write` — returns 0, writes nothing.
- `gitlore_relay_drain` — returns 0, sets `GITLORE_RELAY_SYSMSG` and
  `GITLORE_RELAY_CTX` to `""`.

Tests landed in `tests/index_sync.bats`, in a new
`--- relay markers (Item 3.1) ---` section right after the existing per-agent
preimage/compose-stamp cases.

## Case 1 — `relay_marker_file suffixes the agent id`

```
not ok 51 relay_marker_file suffixes the agent id
# (in test file tests/index_sync.bats, line 819)
#   `[[ "$output" == *-a1 ]]' failed
```

Died on the keyed-call assertion (`gitlore_relay_marker_file memory a1` must end
in `-a1`) — the stub always returns the bare path, so this is a genuine
assertion failure, not a missing symbol.

**Non-vacuity.** The test carries two `run` blocks. In a scratch copy with the
bare-call block moved first, the bare-call assertion (`!= *-a1`) **passed**
against the stub — expected, since the stub's unsuffixed default already matches
the correct bare-case behavior. Only the keyed-call assertion discriminates the
stub from GREEN; verified by running it alone (still fails, same line) after the
reorder. The bare-call assertion is a same-test validity check, not a second red
generator — noted so the "two assertions" shape isn't mistaken for two
independent reds.

## Case 2 — `relay_write then relay_drain splits the two channels and removes the marker`

```
not ok 52 relay_write then relay_drain splits the two channels and removes the marker
# (in test file tests/index_sync.bats, line 829)
#   `[ -f "$marker" ]' failed
```

Died on the marker-exists check right after `gitlore_relay_write` — the write
stub creates nothing, so no marker file exists (whether keyed or bare).

**Non-vacuity**, via three rounds of scratch-file reordering (each copy deleted
after use, `git status` clean throughout):

1. Moved `[ -f "$marker" ]` to the end, ahead of nothing: the five drain/channel
   assertions that never fired in the original order now run first. Result:
   `[[ "$GITLORE_RELAY_SYSMSG" == *"S1"* ]]` fails on its own (line now first) —
   independently discriminates the stub (drain always yields empty strings) from
   GREEN.
2. Trimmed to isolate the third channel assertion alone
   (`[[ "$GITLORE_RELAY_CTX" == *"C1"* ]]`, with the S1/a1 checks removed): also
   fails independently — confirms it isn't riding on an earlier assertion's
   failure.
3. Trimmed to isolate the two cross-check negatives (`SYSMSG != *"C1"*`,
   `CTX != *"S1"*`) and the final `[ ! -f "$marker" ]`: this run went **green**
   against the stub. Expected and reported, not hidden: with the write stub
   writing nothing, both variables are empty and no marker was ever created, so
   "doesn't contain the other channel's body" and "marker is gone" hold
   trivially. These three assertions carry real weight only once GREEN actually
   writes and drains content — the cross-check is what the runbook item names as
   pinning the split against a both-channels-get-both-bodies bug, and it needs a
   populated write to have something to guard. They are not the case's red
   generator; the marker-exists check and the `S1`/`C1` channel checks are.

## Case 3 — `relay_drain on an empty store sets both variables empty and returns 0`

Passes green against the stub — not a `not ok`. This is unavoidable given the
stub contract as specified in the dispatch ("`gitlore_relay_drain` returning 0
with both variables empty"): that is verbatim what this case asserts for the
empty-store path, so the stub was built to already satisfy it. Flagging this per
the vacuous-green identification the dispatch calls for, rather than letting a
3-for-3 pass/fail count imply all three reded. No code change closes this — it
is a property of a correctly-specified inert stub meeting a degenerate-input
assertion, and slice 1 GREEN must keep it passing rather than make it fail.

## Checks that passed, by name

- `./scripts/run-bats.sh tests/index_sync.bats` — 72 passed, 2 failed (the two
  genuine reds above; case 3 and all 70 pre-existing cases green).
- `./scripts/lint-shell.sh` — 137 files clean.
- `shellcheck -s bash tests/index_sync.bats` — clean, exit 0.
- `git status` — only `scripts/lib/index-sync.sh` and `tests/index_sync.bats`
  modified; no scratch files left behind.
