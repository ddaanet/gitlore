# Merge-commit hygiene

Ruled 2026-09-01. Merges are automated from the human's perspective: both
parents of every gitlore merge already passed an approval gate (the local side
at its own FR11 commit, the upstream side in the repo that published it), so a
merge prompts for nothing and carries a canned message. Explicit operations
leave a clean memory store; the implicit SessionStart fast-forward keeps
producing no commit.

## Settled points

1. Scope is **all** gitlore merges — tier stores and the memory store's own
   resolve merges alike. FR11's "including merge commits produced by
   `/gitlore:resolve`" clause inverts into an exemption.
2. The parent agent keeps its own sanity check of a divergence synthesis; only
   the user escalation drops. A rejection still loops the sub-agent.
3. Merge-commit subject: `merge <merged-repo-name> from <consumer-repo-name>`
   (e.g. `merge ddaanet-memory from gitlore`). The consumer name matters
   because a tier's `live` history is shared: it says which repo performed the
   merge.
4. Merge-commit body: subjects of the **second-parent (local) side** only —
   what the merge brought *into* `live`. The local repo is the only consumer
   that cares what was new in `live`; every other consumer of the shared
   history wants what the merge contributed to it. Matches git's own `--log`
   convention under D6 (authority first parent, pending second).
5. Root bookkeeping commit after a tier take:
   `Update MEMORY.md for <tier> tier merge.`, body = subjects of the taken
   tier commits (`<old-gitlink>..<new-live>`), so a fast-forward take — which
   creates no tier commit — is still recorded.
6. Push takes upstream: push is attempt-push → on refusal, take/merge → push
   again. A **behind** store is taken inline (fast-forward + adoption + root
   commit); a **diverged** store still yields to `/gitlore:resolve` and the
   skill re-pushes (NFR1 — no AI in the hook path).

## Contracts

New helpers in `scripts/lib/resolve.sh`:

- `gitlore_store_repo_name <store>` — basename of `remote.origin.url` minus
  `.git`; a placeholder or absent remote falls back to the store directory's
  basename.
- `gitlore_consumer_name <mempath>` — basename of
  `git -C <mempath> rev-parse --show-superproject-working-tree` (the parent
  repo), for tier and memory merges alike.
- `gitlore_root_tier_commit <mempath> <tier> <store> <old> <new>` — commits
  the already-staged pair (`MEMORY.md` + tier gitlink; bare `commit`, never
  `-a`/`add -A`) in the root store under `GITLORE_MEMORY_COMMIT=1` with the
  canned message from point 5, then ff-pushes `HEAD:live`. Refused — with the
  current stage-only behavior and a notice — when the root store was dirty or
  its index unclean **before** the take, so pre-existing unapproved edits
  never ride an unprompted commit; that fallback keeps D43's staged-pair
  discipline as the degraded path rather than dead code.

Changed paths:

- `gitlore_merge_one_store` (ff+adoption branch): capture the pre-take dirty
  state and old gitlink, then after adoption call `gitlore_root_tier_commit`.
  The memory root's own ff take needs no commit (its `MEMORY.md` moved with
  the fast-forward).
- `resolve.sh continue-after-merge`: replace `commit --no-edit` with the
  canned message — subject from point 3, body
  `git log --format=%s HEAD..MERGE_HEAD` — via `commit -q -F -`. For a tier
  merge, after the gitlink staging, the same root bookkeeping commit (same
  dirty guard).
- `gitlore_push_stores`: the two `behind` branches (tier and memory) call
  `gitlore_merge_one_store` instead of printing the `/gitlore:merge` notice,
  then continue; the tier loop runs before memory's push, so a bookkeeping
  commit created by a tier take is published by the same run. Shared with
  `pre-push` by design (D42): a parent `git push` is an explicit operation,
  and the take keeps its lockstep guarantee (taken commits are already on the
  tier remote).
- `resolve.sh check_store_gates` behind-notice: left pointing at
  `/gitlore:merge` for now (still true); folding a take into the repair pass
  is a follow-up.

Docs:

- `design.md`: FR11 exemption sentence; new **D49** (canned, unprompted merge
  commits; explicit takes leave a clean store) in the merge-and-resolve group.
  The file sits at the 400-line cap — trim or split as needed.
- `merge-and-resolve.md`: D49 argument; merge-skill section ("commits
  nothing" → commits its bookkeeping); resolve step 3 (parent check only, no
  user escalation) and step 4 (canned message).
- `tier-stores.md` D43: the "dirty — expected" and staging paragraphs become
  the degraded path; the happy path commits.
- `git-hooks-and-entry-points.md`: push-skill section and D20 (behind → take).
- `workflows.md`: publish and resolve step lists.
- `skills/merge/SKILL.md`, `skills/push/SKILL.md`, `skills/resolve/SKILL.md`,
  `agents/memory-merger.md`: approval language (parent verdict, not user),
  clean-store outcome, push-takes-upstream.
- `changelog.md` entry.

Tests (update pinned behavior, then new):

- `merge_memory.bats`: tier ff take now asserts the canned root commit, clean
  store, and body subjects; dirty-root fallback keeps the stage-only
  assertions.
- `push_memory.bats` / `push_behind_vs_diverged.bats` / `pre_push_hook.bats`:
  behind → take, not notice.
- `tier_divergence.bats` / `resolve_compose.bats` / `resolve_merge_*.bats`:
  continuation commit message is canned; tier merge leaves a committed root.
- New units for `gitlore_store_repo_name` / `gitlore_consumer_name` /
  message format.
