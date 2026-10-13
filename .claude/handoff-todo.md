## Open decisions

- Whether the 26 tier commits by `gitlore <gitlore@localhost>` are mapped to `David Allouche <david@ddaa.net>` in the ddaanet rewrite, as `gitlore@local` was in gitlore-memory. Stated default: yes.
- Whether gitlore gets a guard before the tier force-push: today nothing refuses a rewritten tier, and an un-crossed clone's `/gitlore:merge`, `/gitlore:push` or parent push merges old history back and re-publishes it (plan section 1.4, reproduced with the real scripts). Candidates in plan section 6: G1 rewrite-aware take, G2 refusal only. A guard protects a clone only after a gitlore release and a plugin update there. Stated default: G2 as a red/green pair, released before the tier push.
- Whether a store commit made from a hook must clear inherited `GIT_AUTHOR_*`/`GIT_COMMITTER_*` (plan section 6, G3) — how `T` reached the memory stores. Installed 0.9.0 has the path; not yet checked whether the unreleased tree still does.
- Whether stale commit ids in tracked files are rewritten after the push: the mirrors' report lists them (two under `docs/changelog/`, the rest under `plans/`). Stated default: fix the two changelog ids, leave `plans/` as frozen records.
- How the 23 GitHub releases behave when their tags are force-moved; unchecked.
- Whether `tier-triage-nudge` (no upstream) is published after the rewrite. Stated default: no.
- `plans/macos-check/out/`: four files are `plans/macos-check/run.sh` output (it wipes the directory each run); `ddaanet-merge-report.md` is a stray report from a merge since completed. Stated default: add the directory to `.gitignore` and delete the stray report.
- Inbox briefs, read, none actioned: `brief-https-submodule-urls.md` (one url edit in `memory/.gitmodules`, through a memory commit and `/gitlore:push`; its claims check out), `brief-write-https-urls.md` (generator change; its four "decided" items came from another repo's session and need confirming here), `brief-launcher-memory-path-containment.md` (confirmed by reading `scripts/install/launcher-shim`: `$root/$mempath` is injected with no containment check; stated default a red/green fix with a message on refusal). `brief-orphan-report-fix-recipe.md` is unread.

## Remaining

- Run the option H rewrite pass and hand back the push and checkout commands.
- Commit the parent's `memory` pointer, moved by the tier merge, through an approved memory summary.
- Deliver `/tmp/claude-1000/gitlore-d60/brief-hook-authoring-posttoolbatch-exit-codes.md` to `/Users/david/code/plugin-craft/inbox/` (my human partner runs the copy).
- Re-run `plans/batch-hook-deaths/probe/run.sh 2` (real `claude`; expects an empty turn-1 result and `hook_stopped_continuation`).
- `memory/MEMORY.md` is at 102% of its 25600-byte budget, so the loader cuts its tail; `/gitlore:index-audit` is the pass.
- `memory/ddaanet/main-follows-reviewed-branches.md` links `[[my-human-partner-owns-branching]]`, which does not exist in the tier.
- `docs/references/index-authoring-sync.md` sits at 398 of its 400-line cap; the next addition needs a split.