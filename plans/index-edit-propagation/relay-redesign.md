# Relay redesign — C2, M1, M2, M3, M6 of the deliverable review

Design for the second fix pass over `reports/deliverable-review.md`. The runbook
for this pass is §Slices below; the design record lands in `docs/` per §Docs, in
the same commit as the code and tests.

## Findings settled here

- **C2** — same-event hooks run in parallel (code.claude.com/docs/en/hooks: "All
  matching hooks run in parallel"), so the read-merge-write on one per-agent
  marker loses reports, and two parent-side drains relay a block twice.
- **M1** — a drain can unlink a marker written between its read and its `rm`.
- **M2** — the parent-side drain runs only on a batch that changed the index;
  the batch that dispatched the subagent has no baseline, so the report waits
  for an unrelated index edit or the next SessionStart.
- **M3** — markers key on agent id alone, so a peer session in the same checkout
  drains them into the wrong conversation.
- **M6** — no test drives the two hooks concurrently, so every case above is
  green on the defective code.

## Facts the design rests on

1. Hooks matching one event run in parallel. Nothing in `hooks.json` orders
   `index-sync-post.sh` against `index-compose.sh`.
2. A hook firing inside a subagent receives the **parent's** `session_id`:
   `subagent-hook-output-probe.md` logs the subagent's `PostToolUse` stdin with
   `session_id` equal to the parent run's id and `agent_id` set. The hook-input
   schema is shared across events, so `PostToolBatch` carries the same field.
3. SessionStart on `compact` and `resume` keeps the session id; `/clear` and a
   fresh launch mint a new one.
4. `mv` within one gitdir is a same-filesystem rename: atomic, and exactly one
   of two movers of the same source succeeds.

## Decisions

**D51 (revised) — a subagent's report is a write-once file, keyed by session and
agent, drained by one hook.**

- **Write-once, never merged.** Each report is its own file:
  `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>` in the memory gitdir, where `S` is
  the sanitized session id (`nosession` when the payload has none), `A` the
  sanitized agent id (same `[A-Za-z0-9-]` class, `_` elsewhere — reuse
  `_gitlore_agent_suffix`'s mapping), `<epoch>` is `date +%s`, `<pid>` is the
  writing hook's `${BASHPID:-$$}` — `$$` is fixed at shell startup and shared by
  `&` subshells, `BASHPID` is per-subshell but absent on bash 3.2; a hook is its
  own process, so either is unique in production, and a concurrency test spawns
  its writers as `bash -c` processes rather than subshells so the guarantee it
  exercises is the one production has — and `H` is the writer's tag, `sync` or
  `compose`. Two writes from one process under one tag within one second would
  collide; no caller does that, and the install refuses an occupied name rather
  than overwrite it, a bound stated in the code. Built at `<name>.tmp` and
  installed by `mv`; the `.tmp` suffix stays excluded from every drain. Two
  hooks in one batch write two files, so there is no shared file to race on (C2
  write half). The refusal on an empty agent id stays. A path already occupied
  at install time is refused, temp removed — POSIX `mv` moves a source *into* an
  existing directory destination.
- **Framing order** is filename order under `LC_ALL=C sort`: grouped by agent,
  then by write time. Each file is framed `--- gitlore-relay agent <A> ---` as
  today; `A` is recovered from the name by stripping the known
  `gitlore-relay-<S>-` prefix and the three trailing `-<epoch>-<pid>-<H>` fields
  (`${rest%-*-*-*}`), which is unambiguous even if an id contains `-`.
- **One drainer.** A new `PostToolBatch` hook,
  `scripts/cc-hooks/relay-drain.sh`, is the only PostToolBatch consumer. It runs
  on every batch of the main thread (`agent_id` empty; a keyed run exits 0 at
  once), needs no baseline, and so runs on the very batch whose `Agent` call
  returned (M2). It enumerates `gitlore-relay-<S>-*` for its own session only
  (M3), reads each file, removes exactly the files it read, and emits both
  channels. The two reporting hooks lose their drain branches entirely (C2 drain
  half): they write when keyed and emit when unkeyed, nothing else.
- **No claim-by-rename.** With unique names the drain never removes a file it
  did not read, which is all M1 needed. Two drainers of one session key would
  need two live processes sharing a session id, which the platform does not
  produce: the batch hook and the SessionStart hook never overlap in one
  session, and a subagent never drains. A killed drainer re-delivers on the next
  run rather than stranding a claimed file.
- **SessionStart drains its own session** (`compact`, `resume`), and sweeps any
  `gitlore-relay-*` older than 7 days, the same `-mtime +7 -delete` shape as the
  nudge markers — temps included: the `.tmp` exclusion is a drain rule (a temp
  is never folded as a report), not a sweep rule, so a temp a killed writer
  stranded is collected by age rather than never. A report addressed to a
  session that ended is undeliverable: the conversation it describes is gone,
  and the store state it reported on is re-covered by SessionStart's own
  structural pass. It is removed by age rather than folded into a stranger's
  session.
- **Delivery timing residual.** A background subagent whose report lands after
  the parent's last batch of a turn is delivered on the parent's next batch, or
  at the next compact/resume; a session that ends with no further batch loses it
  to the sweep. Stated in the node, not solved.

**Rejected alternatives** (name each in `docs/decisions.md`):

- a shared per-agent marker each hook merges into — races under parallel hooks;
- a drain inside each reporting hook — two parallel drains relay twice, and a
  drain gated on that hook's own baseline misses the dispatching batch;
- claim-by-rename before reading — unnecessary with unique names, and a killed
  claimer strands the claimed file;
- folding another session's stranded markers at SessionStart — lands a report in
  a conversation that never dispatched the agent.

## Docs

All in the same commit as the code. Every claim is made from the code.

- `docs/references/index-authoring-sync.md`: the D38 paragraph starting "Inside
  a subagent both channels reach…" becomes a headed block
  **The relay — D51's mechanism** (the review's Minor: D51's link points at an
  unheaded paragraph), rewritten to the design above, including the atomic
  install, the `.tmp` exclusion and its residual, and the delivery-timing
  residual. The header bullet list of the node names it.
- `docs/references/cc-platform.md` D51: the measurement stays; the mechanism
  sentence now says "keyed by session and agent, drained by a dedicated
  PostToolBatch hook" and points at the block above.
- `docs/references/session.md` step 10: own-session drain plus the age sweep.
- `docs/decisions.md` D51 line and its *Rejected* line: the four above.
- `docs/design.md` Claude Code hooks bullet: names the relay drainer.
- `docs/references/configuration.md` gitdir state files: add the relay files.
- `docs/changelog.md`: one entry under today's date.
- Comments in `scripts/lib/index-sync.sh` and the two hooks that argue the old
  premise ("not sequential the way hooks within one session are", "two hooks can
  stage to the same key … merged into, not truncated") go with the code they
  argued.

## Slices

One tdd item, three slices; RED and GREEN as `edify:orchestrate` §2.3, with
these overrides from the task frame: the orchestrator owns `just precommit`
(background, main session) and the single commit; GREEN runs the touched bats
files and `just lint` only and commits nothing.

**Slice 1 — library.** `scripts/lib/index-sync.sh`:
`gitlore_relay_write mempath session agent tag sysmsg ctx`,
`gitlore_relay_drain mempath session`, `gitlore_relay_sweep mempath`, and
`gitlore_relay_marker_file` retired (nothing can predict a name). Tests in
`tests/index_sync.bats`, rewriting the `relay_*` cases to the new contract:

1. two writes under one agent in one session yield two files; the drain frames
   both, in write order, and removes both;
2. **concurrency**: 20 `gitlore_relay_write` calls for one agent run in parallel
   (`&` + `wait`), one drain; exactly 20 framing lines, every body present once
   — fails on the merge-write code (the review measured 86/200 losses for two
   writers);
3. a write for session S2 is not drained by S1 and survives it;
4. a `.tmp` beside the markers is neither folded nor removed by the drain (M1's
   "unlink another writer's temp" half); the unlink-between-read-and-rm half is
   settled by construction — unique names — and has no test;
5. the sweep removes a `gitlore-relay-*` older than 7 days (`touch -t`), `.tmp`
   included, and leaves a fresh marker and a fresh `.tmp` alone;
6. empty agent id refused; empty session maps to `nosession` on both sides.

**Slice 2 — hooks.** `relay-drain.sh` (new, executable, registered in
`hooks/hooks.json`), `index-sync-post.sh` and `index-compose.sh` (drain branches
removed, `session_id` parsed non-fatally, tag passed), `session-start.sh` (reads
its payload for `session_id`; own-session drain then sweep). Tests in
`tests/cc_hook_index_compose.bats`, `tests/cc_hook_session_start.bats`,
`tests/plugin_distribution.bats` (the hook is listed, exists, is executable):

1. **concurrency at hook level**: both reporting hooks run at once
   (`sync_feed a1 &`, `feed a1 &`, `wait`) for one keyed batch, then
   `relay-drain.sh` unkeyed with the same session: both reports present exactly
   once, in one loop of 10 iterations — replaces "both PostToolBatch hooks in
   one keyed batch reach the parent";
2. `relay-drain.sh` on a batch with no baseline and no index change still
   delivers (M2); a keyed run of it exits 0 with no output and leaves the files;
3. an unkeyed `index-sync-post.sh` / `index-compose.sh` run leaves a marker in
   place (they no longer drain) — replaces the "unkeyed … folds in" cases;
4. `relay-drain.sh` with session S1 leaves an S2 file standing;
5. session-start drains its own session's marker and not another's, and sweeps
   one older than 7 days;
6. the existing failed-write cases keep passing under the new signature.

**Slice 3 — docs**, per §Docs, dispatched to opus as prose; reviewed with the
code.
