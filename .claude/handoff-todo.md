## Open decisions

- Whether a store commit made from a hook must clear inherited `GIT_AUTHOR_*`/`GIT_COMMITTER_*` (plan section 6, G3) — how `T` reached the memory stores; unchecked whether the unreleased tree still has the path.
- Whether stale commit ids in tracked files are rewritten after the push. Stated default: fix the four `docs/changelog/` ids (`27042ce`, `431faf7`, and `ea39932`, `2800e0e` in `2026-09-01-a-tier-live-ahead-of-its-pin-is-adopted.md`) from the final run's maps, leave `plans/` and the `tests/check_memory_hygiene.bats` fixture string.
- How the 23 GitHub releases behave when their tags are force-moved; unchecked.
- Whether `tier-triage-nudge` (no upstream) is published after the rewrite. Stated default: no.
- `plans/macos-check/out/`: `run.sh` output plus a stray `ddaanet-merge-report.md`. Stated default: gitignore the directory, delete the stray report.
- Inbox briefs, none actioned: `brief-https-submodule-urls.md` (claims check out), `brief-write-https-urls.md` (its "decided" items need confirming), `brief-launcher-memory-path-containment.md` (confirmed; default a red/green fix with a refusal message), `brief-orphan-report-fix-recipe.md` (unread), `brief-launcher-shim-second-sighting.md` and `brief-memory-gate-owner-inventory-and-existence.md` (unread).

## Remaining

- Release D61/D62; update the plugin here and on the laptop.
- Run the rewrite suites under bash 3.2 on macOS (`plans/macos-check/run.sh`); nothing has run there yet.
- Redo the option H rewrite on fresh mirrors, write both records, hand back archive, push and crossing commands.
- `cross-rewrite.sh`: a few refusals give no next step (not checked out, unreadable version, child fetch); child records are fetched once per gitlink per ref.
- Take the rewrite record's id length from the repository (`git rev-parse --show-object-format`: 40 or 64 hex) instead of hard-coding 40: the map-line and commit-map checks in `cross-rewrite.sh` and `record-rewrite.sh`, `ZEROS`, and "40-hex" in `docs/references/history-rewrites.md`; record version stays `1`. Not urgent while no store can be SHA-256 (not hosted on GitHub).
- Delete each `gitlore/archive/<date>` branch once every known clone has crossed (owner's call).
- Deliver `/tmp/claude-1000/gitlore-d60/brief-hook-authoring-posttoolbatch-exit-codes.md` to `/Users/david/code/plugin-craft/inbox/` (my human partner runs the copy).
- Re-run `plans/batch-hook-deaths/probe/run.sh 2` (real `claude`; expects an empty turn-1 result and `hook_stopped_continuation`).
- `memory/MEMORY.md` is over its 25600-byte budget; `/gitlore:index-audit` is the pass.
- `memory/ddaanet/main-follows-reviewed-branches.md` links `[[my-human-partner-owns-branching]]`, which does not exist in the tier.
- `docs/references/index-authoring-sync.md` sits at 398 of its 400-line cap; the next addition needs a split.