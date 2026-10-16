# Memory commits decoupled from the parent commit

2026-10-11. A memory commit becomes the agent's own act; nothing a parent
`git commit` does touches memory, and nothing at `SessionStart` moves it.

## Why

A parent commit over dirty memory meets the FR11 gate inside `pre-commit`, which
refuses until a summary is approved. A subagent cannot obtain that approval, so
its commits block. The gate is in the wrong place: approval is a conversation,
and a git hook has no one to converse with.

Sized for one clone per project, sharing through tiers. An in-process worktree
(`EnterWorktree`, `isolation: "worktree"`) writes the launch repo's memory
(D15), so a single clone has one memory HEAD and the `SessionStart` fast-forward
never has work to do; a separately launched linked worktree is the one case it
served, and `/gitlore:merge` takes that over.

## Decisions to record

Land in `docs/decisions.md` and their nodes (T6) when the code is true.

- **D58 — A memory commit is the agent's own act, never a side effect of a
  parent commit.** `commit-memory.sh` — directly, or through the trigger file
  `memory-commit-batch.sh` acts on — is the one commit path; the parent
  `pre-commit` hook, its wiring and the `precommitCommand` nudge are retired.
  After a successful commit the script stages the moved gitlink into the parent
  index, so the next parent commit records it with no hook; during a replay
  (rebase, cherry-pick, revert) it skips that staging and says so. FR11's
  approval stays: summarize, ask, then commit. *Rejected:* the hook standing
  down on a missing approval — keeps the wiring, the index capture and the
  replay guard alive for one case, and a refusing pre-commit can abort a rebase.
- **D59 — `SessionStart` moves memory nowhere; every advance is an explicit take
  or push.** Local `live` is created from the gitlink after a clone, not from
  `origin/live`, so HEAD equals `live` in a single checkout by construction. It
  reports — dirty, local `live` ahead of HEAD, `origin/live` ahead or diverged
  after a read-only fetch, as tiers already get — on both `systemMessage` and
  `additionalContext`, naming `/gitlore:merge`. `/gitlore:merge` gains the
  fast-forward of HEAD onto a local `live` that strictly contains it. A parent
  push still takes a behind remote (D49). *Rejected:* the clean-only
  fast-forward — no work in a single checkout, and in the multi-checkout case a
  take the user sees beats a move they cannot.

D16's "only blessed path is the parent commit" and D12's orientation line
invert; the changelog records both. D4, D50, D53, D54, D56 stay — they govern
the batch retry (see *Not in this slice*).

## Tasks

Each: red (an assertion naming the state of the world), green, the suite it
lives in. `just precommit` in the background before each commit.

**T1 — Retire the parent `pre-commit`.** Delete `scripts/git-hooks/pre-commit`
and `git_hook_pre_commit*.bats`. `emit-wrappers.sh` emits `gitlore-pre-push` and
a `gitlore-pre-commit` stub (exit 0, one comment) for consumer repos whose
tracked Lefthook/Husky/Overcommit config still names it — that config is a
published boundary; `.git/hooks/pre-commit` is not, so `wire-direct.sh` wires
`pre-push` only and removes a shim byte-identical to the one it used to write.
Every `wire-*.sh` and the `wire-manual.sh` snippet drop `pre-commit`; the
sentinel replay follows. Postcondition: a parent commit over dirty, unapproved
memory succeeds and records the gitlink it found. `integration_happy_path`,
`integration_memory_gate`, `tier_lockstep`, `emit_wrappers`,
`hook_manager_wire`, `install_run`, `write_settings` assert the new shape;
`integration_gitlink_staging` and `integration_replay_guard` are repurposed by
T3.

**T2 — Retire the nudge.** Delete `post-tool-use.sh`, `nudge-reset.sh`,
`cc_hook_post_tool_use.bats`, the `PostToolUse(Bash)` and both `nudge-reset`
entries in `hooks/hooks.json`, `gitlore.precommitCommand` from
`write-settings.sh`, `gitlore_commit_notified_file` and its `rm` in
`resolve-sync-memory.sh`. Postcondition:
`grep -r 'precommitCommand\|commit_notified' scripts hooks tests docs` is empty.

**T3 — `commit-memory.sh` stages the gitlink.** After
`gitlore_sync_memory_to_live` returns 0 and memory moved: unless a replay marker
(`rebase-merge`, `rebase-apply`, `CHERRY_PICK_HEAD`, `REVERT_HEAD` — the old
hook's list) exists in the superproject,
`git -C <superproject> add -- <mempath>`, superproject from
`rev-parse --show-superproject-working-tree`. A replay skips the staging and
reports it; a failed `add` is reported and exits 0 — the commit landed, the
pointer floats (D46). Red: `integration_gitlink_staging` asserts the parent's
`diff --cached --name-only` lists the memory path after `-m`;
`integration_replay_guard` asserts it does not mid-rebase; a no-op run stages
nothing. `memory-commit-batch.sh` inherits it unchanged.

**T4 — `SessionStart` reports, never moves.** In `session-start.sh`: `live` is
created from HEAD whether or not `origin/live` exists; the `merge --ff-only`
block becomes a report. Contract, each line on `add_sysmsg` *and* `protocol_ctx`
(the `session-tiers.sh` pattern — D14 makes `systemMessage` user-only), all
non-fatal: dirty → "uncommitted changes present"; clean and `live` strictly
contains HEAD → "N commits on live not checked out here — run /gitlore:merge";
HEAD and `live` diverged → "run /gitlore:resolve"; a remote that is not the
placeholder → `fetch origin live` read-only, then `origin/live` strictly ahead →
"N upstream memory commits — run /gitlore:merge", diverged → "run
/gitlore:merge", unfetchable → named. Counts from `rev-list --count`. Red:
`cc_hook_session_start.bats` asserts HEAD unchanged after a start with `live`
ahead and the line present on both channels; `integration_clone_restore` asserts
a clone's `live` equals its gitlink and the upstream line carries the count.
Delete the ff and divergence-exit cases those replace.

**T5 — `/gitlore:merge` fast-forwards HEAD onto local `live`.** In the root
store's take (`resolve-merge-stores.sh`): before the remote take, a clean store
whose `live` strictly contains HEAD is `checkout --detach live`'d and reported
as moved; dirty → reported, nothing moves. Red: `merge_memory.bats` asserts HEAD
equals `live` after a take with `live` ahead and no remote change.

**T6 — Docs and orientation.** `design.md` FR4, FR8, NFR5 (pre-push ordering
stays; the gitlink floats between commits), Components, Workflows;
`decisions.md` D58/D59; `git-hooks.md` → `pre-push` only, gitlink invariant
kept, `pre-commit` steps to the changelog; `commit-gate.md` (nudge gone; the
trigger file is the general path, no longer withheld); `session.md` 5–6;
`merge-and-resolve.md` phase list; `memory-entry-points.md` D16 wording;
`installation.md`, `configuration.md`, `workflows.md`; the SessionStart
orientation: "commit memory with the approved summary through
`commit-memory.sh`" replaces the prohibition, D12's gate kept as the guard of
compose and the `live` advance. Changelog entry. Root `CLAUDE.md` lockstep
paragraph; `memory/ddaanet/preflight-excludes-memory-submodule.md` (its *Why*
names the parent hook) via the memory-writing skill. `check-docs-links.py`
passes.

**T7 — Evals.** Rewrite or retire any `tests/evals` case driving the nudge or
expecting a parent commit to carry memory. `just evals` costs money: ask before
running.

Order: T1–T3 one commit (the hook's job moves to the script); T4–T5 one; T6
rides whichever commit makes its sentence true; T7 last.

## Not in this slice

- The batch retry machinery in `resolve-sync-memory.sh` — restamps, landing
  records, freshness verdicts — serves `memory-commit-batch.sh` and survives
  unchanged. Whether a failed batch should consume the trigger and re-ask is a
  separate decision with its own plan.
- `pre-push` stays, divergence yield included: no user interaction, and dropping
  it breaks NFR5 for every clone.
- `handoff` writes the trigger and message files and is untouched.

## Probe before T1

From the agent's Bash on a scratch clone with dirty memory:
`bash "$(git config gitlore.commitCommand)" -m "probe"`. If the permission layer
lets it run, the orientation line names the direct call; if not, the trigger
file. The trigger path is kept for `handoff` either way.
