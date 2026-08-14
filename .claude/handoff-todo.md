## Remaining

1. **`plans/brief-merge-dispatch-authorization.md`** — wording only: make a
   hook directive that names a sub-agent read as authorized by the command the
   user already ran. Applies to the whole class of such directives, not the one
   instance; tests asserting hook text move with it.
2. **`brief-resolve-noisy-noop-failure.md`** (repo root, untracked) — the
   standalone resolver fails noisily against a tier already at its remote tip,
   taking the resolve skill's "surface stderr verbatim and stop" branch on what
   is a no-op. Found from `onekeys`, so read the brief's own repro before
   deciding the fix.
3. **`plans/brief-hook-exec-and-compose-revert.md`, defect 1** — the installer
   appends its line after an existing `exec`, leaving it unreachable. Refuse or
   interpose rather than append silently. Self-contained to the install path.
4. **`brief-orphaned-merge-head-no-state-file.md`** (repo root, untracked) —
   merge core. `gitlore_prepare_merge` reads `pending` from `HEAD` rather than
   `live`, and the stale-merge guard keys on the state file rather than
   `MERGE_HEAD`. Pick one of the three fixes before writing code.
5. **`plans/brief-hook-exec-and-compose-revert.md`, defect 2** — composition
   reverts an incoming tier merge by mirroring root's wording down over a
   merged carrier. Highest blast radius of the set: it changes which surface is
   canonical, and a wrong answer silently destroys merged memory.
6. **`plans/brief-handoff-integration-evals.md`** — largest by effort, lowest
   blast radius: new eval scenarios only, no production code. Needs
   `lib/setup.sh` to become two-plugin aware, and the brief names PATH
   resolution for handoff's `bin/` as its single largest unknown. Evals cost
   money per run and are opt-in, not in the default gate.