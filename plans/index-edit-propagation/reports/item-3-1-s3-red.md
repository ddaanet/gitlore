# Item 3.1, slice 3 — RED report

Scope: `tests/cc_hook_session_start.bats` only. SUT
(`scripts/cc-hooks/session-start.sh`) untouched, per instructions. Tree is dirty
and unstaged; nothing committed, no `just` recipe run.

## Case 1 — `session-start drains a stranded relay marker` (positive)

Writes a marker under agent `a1` via `gitlore_relay_write`, runs
`session-start.sh` against a clean `make_parent_with_memory` fixture, asserts
both channels and the marker's removal.

`not ok` block from `./scripts/run-bats.sh tests/cc_hook_session_start.bats`:

```
not ok 22 session-start drains a stranded relay marker
# (in test file tests/cc_hook_session_start.bats, line 373)
#   `[[ "$sysmsg" == *"STRANDED SYSMSG BODY"* ]]' failed
```

Died on the first content assertion (`tests/cc_hook_session_start.bats:373`):
`session-start.sh` never calls `gitlore_relay_drain`, so the marker's sysmsg
body never reaches `.systemMessage`.

**Non-vacuity evidence.** The 4 assertions after the setup (`:373-376`) plus the
marker-removal assertion (`:379`) were each isolated as the sole assertion in a
scratch copy of the test, appended to the file, run with `bats -f SCRATCH`, then
removed (never relocated — the file's `load helpers/…` paths are
directory-relative). All five failed independently against the unfixed SUT:

```
not ok 1 SCRATCH positive framing-only        # [[ "$sysmsg" == *"$RELAY_FRAMING a1 ---"* ]]
not ok 2 SCRATCH positive ctx-body-only       # [[ "$ctx" == *"STRANDED CTX BODY"* ]]
not ok 3 SCRATCH positive ctx-framing-only    # [[ "$ctx" == *"$RELAY_FRAMING a1 ---"* ]]
not ok 4 SCRATCH positive marker-gone-only    # [ ! -f "$marker" ]
```

None was vacuous at RED — each dies on its own check when reached, not on a
fixture error or missing symbol (`gitlore_relay_write`,
`gitlore_relay_marker_file` already exist and succeed; the write/marker-exists
assertions at `:359-366` all pass). Every one of the four is also non-vacuous
going into GREEN: `gitlore_relay_drain` is the only thing that can put the
framing line or the relayed body on either channel, and `rm -f "$marker"` inside
it is the only thing that removes the marker file, so each assertion pins a
distinct piece of the drain's behaviour (sysmsg body, sysmsg framing, ctx body,
ctx framing, marker cleanup) rather than five ways of restating one fact.

## Case 2 — `session-start with no marker emits no relay framing` (negative)

Same fixture, no marker written. Currently passes (bats: `ok 23`) — for a real
reason, not vacuously: `session-start.sh` never emits the relay framing today
regardless of a marker's presence, so this assertion is already true and stays
true after GREEN only if the drain correctly gates on "marker found," not
"marker absent means nothing".

**Non-vacuity evidence.** Isolated as
`SCRATCH negative reordered marker-gone-check-absent`, with the two channel
checks reordered (ctx before sysmsg, reversing the committed test's order) and
run alone via `bats -f SCRATCH`:

```
ok 5 SCRATCH negative reordered marker-gone-check-absent
```

Passes under either ordering, confirming neither assertion depends on evaluation
order and both genuinely execute (not short-circuited past a prior death point).
This negative is the one that would catch a fold implemented unconditionally
(framing always emitted) rather than gated on a marker actually existing — case
1 alone would not catch that bug, since it only exercises the marker-present
path.

## Case 3 — stranded-marker-is-the-only-news — determined unreachable

Traced session-start.sh's control flow instead of writing a case:
`emit_session_json` (`:76-85`) omits `systemMessage` only when `$sysmsg` is
empty at call time. Every branch of the `gitlore_memory_dirty` if/elif/else at
`:193-212` calls `add_sysmsg` unconditionally before either falling through to
the rest of the script or hitting its own early `emit_session_json; exit 0` (the
diverged and ff-failure branches) — "memory ready", "… uncommitted changes …",
"diverged", or "could not be fast-forwarded". Every code path that reaches *any*
`emit_session_json` call passes through exactly one of those four branches
first, so `$sysmsg` is unconditionally non-empty at every call site this hook
has today. The guard-failure fixtures (no `settings.json`, `enabled:false`, no
submodule registered) exit before `mempath` is even resolved and emit no JSON at
all (`assert_session_start_did_nothing`), not an empty-`systemMessage` JSON — so
they don't reach `emit_session_json` either.

Conclusion: no fixture reaches `emit_session_json` with `$sysmsg` empty, so a
case asserting "the relay alone drives `.systemMessage`" would be a tautology,
not a red — it can't discriminate a correct fold from one that never runs,
because `.systemMessage` is guaranteed non-empty independent of the relay in
every reachable state. Documented in a comment block in the test file (after the
two new `@test`s) rather than written as a case that cannot fail.

## Checks that passed, by name

- `./scripts/run-bats.sh tests/cc_hook_session_start.bats` — 22 passed, 1 failed
  (case 1, as expected at RED); case 2 passes for a verified non-vacuous reason.
- `shellcheck -s bash tests/cc_hook_session_start.bats` — clean.
- `/Users/david/code/gitlore/scripts/lint-shell.sh` — 137 files clean.
