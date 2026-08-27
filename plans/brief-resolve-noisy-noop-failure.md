## Brief: `/gitlore:resolve`'s standalone health check fails noisily when there's nothing to merge

2026-08-13 — target: `gitlore` (this repo) · found from `onekeys`

### Decisions

- Running the standalone resolver (`scripts/resolve.sh`, no subcommand — the
  "Standalone" entry mode in `skills/resolve/SKILL.md`) against a tier that is
  already exactly at its remote tip (`HEAD` and `origin/live` identical)
  printed:

  ```
  Already up to date.
  gitlore: could not prepare the memory merge against 'live'. Inspect the memory worktree at <path>.
  ```

  and exited non-zero. That's the resolve skill's "surface stderr verbatim and
  stop" branch — a real-looking failure requiring investigation — for a store
  that was already perfectly healthy. This is what the skill doc's own exit-code
  contract says shouldn't happen: "0 — healthy or simple repair complete."
- Reproduced against the plugin cache's **v0.4.1**
  (`~/.claude/plugins/cache/ddaanet/gitlore/0.4.1`), which is what's
  actually installed and running for consumers on that pin. Its
  `gitlore_prepare_merge` has no ancestry short-circuit at all — it goes
  straight to `checkout --detach <authority>` +
  `merge --no-commit --no-ff <pending>`, and when `pending` and
  `authority` are the same commit, git reports `Already up to date.` and
  creates no `MERGE_HEAD`. The function then treats "no `MERGE_HEAD`" as
  an unconditional failure, with no way to distinguish "genuinely
  unmergeable" from "nothing to merge."
- **This repo's own dev `HEAD` (unreleased, past the v0.5.0 tag) already
  has partial mitigation**, added in `afb02b9` ("classify a refused push
  by ancestry, not git's wording") and present in `gitlore_merge_one_store`
  (the `/gitlore:merge` flow) as a clean early return:
  `if merge-base --is-ancestor "$remote" "$head"; then printf 'already
  holds everything...'; return 0; fi` — exactly the no-op-with-informative-
  message shape this brief is asking for, and it does look right where I
  checked it. What I could **not** confirm in the time I spent reading
  is whether every entry point that can reach `gitlore_prepare_merge` /
  `gitlore_yield_merge` — not just the ones I traced
  (`gitlore_merge_one_store`, `gitlore_push_stores`,
  `gitlore_sync_memory_to_live`, `gitlore_sync_tiers_to_live`) — has an
  equivalent pre-check before calling into the shared merge-prep path.
  `gitlore_prepare_merge` itself still has only the one added in
  `afb02b9` (`is-ancestor "$pending" "$authority"`), and still `return 1`s
  on the generic path for anything that isn't that specific case, so any
  caller that reaches it without its own ancestry pre-check will still
  get the noisy failure.

### Constraints

- The fix, wherever coverage is still missing, should follow the shape
  already used in `gitlore_merge_one_store`: detect "authority already
  contains pending" (or the reverse — a clean fast-forward) **before**
  attempting `merge --no-commit --no-ff`, and return 0 with a plain
  "already in sync" / "fast-forwarded to <sha>" message — not route
  through `gitlore_prepare_merge`'s generic failure path at all.
- Whatever the fix, it should hold for the standalone resolver entry point
  specifically (`scripts/resolve.sh` with no args) — that's the one this
  brief's repro went through, and it's the one `gitlore:resolve`'s skill
  doc directs a user to for "state is unclear."

### Rejected approaches

- None weighed yet — this is a first pass over an unfamiliar and actively-
  changing area of the codebase (`afb02b9` landed the day before this was
  found), not a full audit. Treat the "not confirmed" note above as the
  actual scope of what's left, not a suggestion.

### Additional context

Repro, against v0.4.1 installed for `onekeys`: mount the `ddaanet` tier,
let it fetch and sit exactly at `origin/live` (no divergence, no
uncommitted content), then run
`bash ~/.claude/plugins/cache/ddaanet/gitlore/0.4.1/scripts/resolve.sh`.

Diagnosed by comparing `git -C <mempath> rev-parse HEAD` against
`git -C <mempath> rev-parse origin/live` right after the failure — they
were equal, confirming there was no real divergence to resolve.

Worth checking whether this is already fully closed on `HEAD` and just
needs a release + version bump for consumers to pick up, versus whether
some entry point still lacks the pre-check `gitlore_merge_one_store` has.
