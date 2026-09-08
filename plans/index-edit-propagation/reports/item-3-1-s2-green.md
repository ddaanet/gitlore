# Item 3.1 slice 2 — GREEN report

Both hooks wired: a keyed run stages its report via `gitlore_relay_write`
alongside its normal emission; an unkeyed run drains via `gitlore_relay_drain`
and folds the result into its own sysmsg/ctx pair before the emission guard. All
seven RED cases now pass, made green one at a time; no other case in either
suite or its neighbours regressed.

## Per test, what made it pass

Both hooks needed the same single insertion (see "Insertion point" below); no
test needed a change beyond that shared wiring landing.

- **"a keyed compose run writes a marker and still emits its own json"** —
  passed once the keyed branch (`agent_id` non-empty) called
  `gitlore_relay_write "$mempath" "$agent_id" "$GITLORE_COMPOSE_SYSMSG" "$GITLORE_COMPOSE_CTX"`.
  The hook's own emission was already unaffected (untouched code path), so this
  test needed only the write to start happening.
- **"an unkeyed compose run folds in the marker and removes it"** — passed once
  the unkeyed branch (`agent_id` empty) called `gitlore_relay_drain "$mempath"`
  and, when `GITLORE_RELAY_SYSMSG` was non-empty, appended it to
  `GITLORE_COMPOSE_SYSMSG` (and `GITLORE_RELAY_CTX` to `GITLORE_COMPOSE_CTX`)
  ahead of the existing `if [ -n "$GITLORE_COMPOSE_SYSMSG" ]` guard.
- **"a keyed index-sync run writes its replacement report to a marker"** — same
  shape as the compose keyed case, over the sync hook's `sysmsg`/`ctx` pair and
  its own `agent_id` (already read at line 23).
- **"an unkeyed index-sync run folds in the marker"** — same shape as the
  compose unkeyed case.
- **"an unkeyed compose run with no report of its own still emits the relay"** —
  this is what proves the fold sits *before* the guard: the fold happens
  unconditionally in the unkeyed branch, so `GITLORE_COMPOSE_SYSMSG` becomes
  non-empty purely from `GITLORE_RELAY_SYSMSG` even when the compose call itself
  produced nothing, and the guard then fires on that.
- **"an unkeyed compose run folds in a marker a keyed run wrote"** — the
  end-to-end seam: passed once both halves existed together — the keyed branch
  writing through `gitlore_relay_write` (framed, delimited format) and the
  unkeyed branch draining through `gitlore_relay_drain` (which parses that exact
  format). Confirms the two branches agree on the on-disk shape without a
  hand-rolled write on either side.
- **"an unkeyed index-sync run with no report of its own still emits the
  relay"** — same as the compose empty-own-report case, over the sync hook.

## Insertion point, both hooks

**`scripts/cc-hooks/index-compose.sh`** — inserted between the
`gitlore_compose_and_report "$mempath" "$manifest_touched"` call and the
pre-existing emission guard, which is now at line 87
(`if [ -n "$GITLORE_COMPOSE_SYSMSG" ]; then`). `agent_id` is read at line 44,
unchanged. The insertion is an `if [ -n "$agent_id" ]; then … else … fi`: the
keyed branch calls `gitlore_relay_write`; the unkeyed branch calls
`gitlore_relay_drain` and, guarded on `[ -n "$GITLORE_RELAY_SYSMSG" ]`, folds
both relay variables into `GITLORE_COMPOSE_SYSMSG`/`GITLORE_COMPOSE_CTX` with a
blank-line-joined append (matching the join style `gitlore_compose_and_report`
itself uses between its own sysmsg segments). Placed before the guard — not
after — precisely so the fold can turn an otherwise-empty
`GITLORE_COMPOSE_SYSMSG` non-empty and reach emission; a fold placed after the
guard would have this exact case in the RED report skip the whole `if` body.

**`scripts/cc-hooks/index-sync-post.sh`** — inserted directly before the
pre-existing emission guard, now at line 267 (`if [ -n "$sysmsg" ]; then`).
`agent_id` is read at line 23, unchanged. Same shape: keyed branch calls
`gitlore_relay_write "$mempath" "$agent_id" "$sysmsg" "$ctx"`; unkeyed branch
calls `gitlore_relay_drain "$mempath"` and, guarded on
`[ -n "$GITLORE_RELAY_SYSMSG" ]`, appends the relay variables into
`sysmsg`/`ctx` using the same
`if [ -n "$sysmsg" ]; then sysmsg="$sysmsg\n"; fi; sysmsg="${sysmsg}…"` idiom
the file already uses four times above (for `replaced`/`weak`/`refused`/
`budget`), so the new block reads like the code around it rather than
introducing a second style. Same reasoning on placement: before the guard, so an
unkeyed run with an empty `sysmsg` of its own still gets to emit once the fold
makes it non-empty.

## Checks that passed, by name

- `bats -f <name> tests/cc_hook_index_compose.bats` / `tests/index_sync.bats` —
  each of the seven cases individually, green.
- `scripts/run-bats.sh tests/cc_hook_index_compose.bats tests/index_sync.bats` —
  99 passed, 0 failed (92 pre-existing + 7 new; nothing else in either suite
  regressed).
- `scripts/run-bats.sh tests/cc_hook_session_start.bats tests/cc_hook_add_tier.bats tests/index_compose.bats tests/cc_hook_post_tool_use.bats`
  — 106 passed, 0 failed (no neighbouring suite regressed).
- `shellcheck -s bash scripts/cc-hooks/index-compose.sh scripts/cc-hooks/index-sync-post.sh`
  — clean.
- `scripts/lint-shell.sh` — 137 files clean.

Tree left dirty and unstaged, nothing committed, per this run's done criteria.
Only `scripts/cc-hooks/index-compose.sh`, `scripts/cc-hooks/index-sync-post.sh`
and this report were touched.
