## Current task

Plan 04 (marketplace install) is fully closed — Step 6's two-turn `memory-merger` approval flow was verified end-to-end under `--plugin-dir` and committed — so the next task is to draft Plan 05, the D10 memory-redirect launcher.

## Open decisions

- Plan 05 shape: the D10 redirect is a launch-time `--settings` shim pointing CC's `autoMemoryDirectory` at the `memory/` submodule (project-tier settings are ignored — see `reference_auto_memory_directory`). Decide whether it's a wrapper script vs a documented launch flag, and confirm now is the time to write it (plan-as-late-as-possible → yes, Plan 04 just shipped). This is the fix for the live-dir-vs-submodule divergence surfaced during the Step 6 verification.
