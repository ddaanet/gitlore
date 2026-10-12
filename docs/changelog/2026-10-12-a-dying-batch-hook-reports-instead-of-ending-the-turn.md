# 2026-10-12 — A dying batch hook reports instead of ending the turn

**A `PostToolBatch` hook that dies tells the user and the agent (D60).**
Measured on CC 2.1.296, exit 2 from a `PostToolBatch` hook ends the turn with an
empty reply, and exit 1 or 3 goes on with the agent seeing nothing. The node had
stated the opposite on both counts: exit 2 blocks "only at `PreToolUse`", and a
non-zero exit is merely "less visible". `awk`, `cmp` and `grep` exit 2 on a file
they cannot open, so `index-sync-post.sh` ended the turn silently when its stash
vanished mid-batch. Each of the six `PostToolBatch` hooks now calls
`gitlore_batch_hook_guard`, which captures the hook's stderr and, on a death,
emits one object on `systemMessage` and `additionalContext` naming the hook, the
status, the failing command with its line and the captured error, and exits 0. A
guard that cannot capture or encode replays the stderr and exits non-zero, 2
turned into 1. The `PreToolUse` hooks are unaudited and unchanged.

**A batch hook no longer dies on a baseline another copy consumed.**
`index-sync-post.sh` and `index-compose.sh` claim their baseline by renaming it
to `<name>.$$` before reading it. A copy that finds the baseline gone exits 0
quietly; one that cannot move a baseline still in place dies into the report.
The claimed file is removed on every exit.

**The upgrade notice survives an unparseable payload and an unwritable marker.**
`plugin-upgrade-batch.sh` falls back to the shared `nosession` marker when the
payload does not parse, and sends the notice when the marker cannot be written,
repeating it next batch.

A report-builder step of `gitlore_compose_and_report` that dies after a
successful mount takes `add-tier-batch.sh` with it, and the guard reports the
death with add-tier's consequence instead of a mount report. That is left as it
is: no state reached from a fixture produces it, and the report already points
the agent at `.gitmodules`.
