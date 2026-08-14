## Remaining

1. **`plans/brief-memory-index-glued-bullets.md`, request 4** — the
   `PreToolUse`/`PostToolUse` pair on `Edit`. Design decided and written up in
   the brief. Scope is every `Edit`, not only index files: the shape test is
   cheap, the defect is not index-specific, and narrowing it would starve the
   retirement signal. Settle `Edit`'s output-object shape before committing to
   `updatedToolOutput`.
2. **`plans/brief-merge-dispatch-authorization.md`** — wording only: make a
   hook directive that names a sub-agent read as authorized by the command the
   user already ran. Applies to the whole class of such directives, not the one
   instance; tests asserting hook text move with it.
3. **`brief-resolve-noisy-noop-failure.md`** (repo root) — the standalone
   resolver fails noisily against a tier already at its remote tip, taking the
   resolve skill's "surface stderr verbatim and stop" branch on what is a
   no-op. Found from `onekeys`, so read the brief's own repro before deciding
   the fix.
4. **`plans/brief-hook-exec-and-compose-revert.md`, defect 1** — the installer
   appends its line after an existing `exec`, leaving it unreachable. Refuse or
   interpose rather than append silently. Self-contained to the install path.
5. **`brief-orphaned-merge-head-no-state-file.md`** (repo root) — merge core.
   `gitlore_prepare_merge` reads `pending` from `HEAD` rather than `live`, and
   the stale-merge guard keys on the state file rather than `MERGE_HEAD`. Pick
   one of the three fixes before writing code.
6. **`plans/brief-hook-exec-and-compose-revert.md`, defect 2** — composition
   reverts an incoming tier merge by mirroring root's wording down over a
   merged carrier. Highest blast radius of the set: it changes which surface is
   canonical, and a wrong answer silently destroys merged memory.
7. **`plans/brief-handoff-integration-evals.md`** — largest by effort, lowest
   blast radius: new eval scenarios only, no production code. Needs
   `lib/setup.sh` to become two-plugin aware, and the brief names PATH
   resolution for handoff's `bin/` as its single largest unknown. Evals cost
   money per run and are opt-in, not in the default gate.