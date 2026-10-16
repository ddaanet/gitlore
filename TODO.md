## Open decisions

- Whether stale commit ids in tracked files are rewritten. Stated default: fix the four `docs/changelog/` ids using the final maps (`27042ce`→`dd7419d`, `431faf7`→`38868ca`, `ea39932`→`5cd6cfd`, `2800e0e`→`6e456cf`), and leave `plans/` and the `tests/check_memory_hygiene.bats` fixture string.
- Whether `tier-triage-nudge` (no upstream) is published after the rewrite. Stated default: no.
- `plans/macos-check/out/`: `run.sh` output plus a stray `ddaanet-merge-report.md`. Stated default: gitignore the directory and delete the stray report.
- Inbox briefs, none actioned: `brief-https-submodule-urls.md` (claims check out), `brief-write-https-urls.md` (its "decided" items need confirming), `brief-launcher-memory-path-containment.md` (confirmed; default a red/green fix with a refusal message), `brief-orphan-report-fix-recipe.md` (unread), `brief-launcher-shim-second-sighting.md` and `brief-memory-gate-owner-inventory-and-existence.md` (unread).
- `plans/ddaanet-identity-rewrite/commit-map` is the scratch run's stale tier map, superseded by `run-2026-10-15/maps/tier-commit-map`. Stated default: delete it.

## Remaining

- Push the parents of the 13 crossed clones (claude-plugin-dev, craft, cwd-safety, edify, ghmem, handoff, micro-contrib, micro-craft, onekeys, plugin-craft, prohibitions, sandbox-lies, shell-gotchas); each is my human partner's call.
- Update gitlore to 0.10.0 on the laptop, then cross its clones with section 5 of `plans/ddaanet-identity-rewrite/run-2026-10-15/push-commands.md` (the laptop variant for its gitlore clone).
- `commit-memory.sh` and `push-memory.sh` load their libraries from `gitlore.hooksDir/../..` unless `CLAUDE_PLUGIN_ROOT` is set, so a newer script called by path sources an older cache's libs: 0.10.0's `commit-memory.sh` failed in cwd-safety (0.6.0 config) with `gitlore_approval_present: command not found`.
- `record-rewrite.sh`'s no-op message says `on origin` even when the remote was given as a URL.
- A plain parent `git fetch` in gitlore recurses into submodules and fails on the vendored `plugin-dev` gitlink `59ed770`, which exists nowhere.
- `cross-rewrite.sh`: a few refusals give no next step (not checked out, unreadable version, child fetch); child records are fetched once per gitlink per ref.
- Take the rewrite record's id length from the repository (`git rev-parse --show-object-format`: 40 or 64 hex) instead of hard-coding 40: the map-line and commit-map checks in `cross-rewrite.sh` and `record-rewrite.sh`, `ZEROS`, and "40-hex" in `docs/references/history-rewrites.md`; record version stays `1`. Not urgent while no store can be SHA-256 (not hosted on GitHub).
- Simplification (my human partner's plan): agent commits memory directly via heredoc + script, no hook commits, no memory pre-commit approval gate, no SessionStart ff — explicit `gitlore:merge` only. G3 (identity scrub) is moot under it; record that in the simplification's D-entry.
- Delete each `gitlore/archive/2026-10-15` branch (tier and memory store) once every known clone, the laptop's included, has crossed (owner's call).
- Deliver `/tmp/claude-1000/gitlore-d60/brief-hook-authoring-posttoolbatch-exit-codes.md` to `/Users/david/code/plugin-craft/inbox/` (my human partner runs the copy).
- Re-run `plans/batch-hook-deaths/probe/run.sh 2` (real `claude`; expects an empty turn-1 result and `hook_stopped_continuation`).
- `memory/MEMORY.md` is over its 25600-byte budget; `/gitlore:index-audit` is the pass.
- `memory/ddaanet/main-follows-reviewed-branches.md` links `[[my-human-partner-owns-branching]]`, which does not exist in the tier.
- `docs/references/index-authoring-sync.md` sits at 398 of its 400-line cap; the next addition needs a split.
