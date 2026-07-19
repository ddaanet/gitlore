#!/usr/bin/env bash
# Factories for nested memory *tiers* — a submodule mounted inside the memory
# submodule (D17 slice 3).
#
# Characterization findings (Task 1 spike, 2026-07-19, git 2.x):
#   - Nested gitdir lands at <parent>/.git/modules/gitlore-memory/modules/<tier>;
#     memory/<tier>/.git reads "gitdir: ../../.git/modules/gitlore-memory/modules/<tier>".
#   - The tier is registered in the memory store's OWN .gitmodules only; the
#     parent's .gitmodules is untouched (discovery by enclosure works).
#   - A fresh mount checks out the remote's default branch (main); a local
#     `live` ref does not exist until `fetch origin live:live` creates it.
#   - `fetch origin live:live` is fast-forward-only: on divergence it prints
#     "! [rejected] ... (non-fast-forward)" and exits 1 (origin/live still
#     advances). That is the ff-only guarantee, for free — callers must tolerate
#     the non-zero exit.
#   - `checkout --detach live` works; `symbolic-ref -q HEAD` then exits 1.
#   - D11 linked memory worktree: `git -C <linked-memory> submodule update --init`
#     SUCCEEDS, but gives that worktree an INDEPENDENT tier clone at
#     .git/modules/gitlore-memory/worktrees/<wt>/modules/<tier> — a separate
#     object store and separate refs from the primary checkout's tier. Each
#     worktree therefore fast-forwards from the remote on its own (fine for
#     propagation-in; relevant to push lockstep in a later slice).

# Mount a tier submodule inside an existing memory submodule.
# Requires: make_parent_with_memory has already run (cwd = $TMP_REPO).
# Args: $1 = tier subpath/name (default "ddaanet")
# Leaves: memory/<tier> checked out, the memory submodule committed, the parent
#         index NOT updated (the caller decides when the parent records it).
make_tier_in_memory() {
  local tier="${1:-ddaanet}" mempath="memory"
  local bare="$TMP_REPO/.bare-$tier.git"

  local seed_dir
  seed_dir="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-tier-seed.XXXXXX")"
  git init -q -b main "$seed_dir"
  (
    cd "$seed_dir" || exit 1
    git config user.email "test@example.com"
    git config user.name  "Test"
    printf -- '---\ndescription: "org-wide facts for %s projects"\n---\n\n# %s tier index\n' \
      "$tier" "$tier" > MEMORY.md
    git add MEMORY.md
    git commit -q -m "Initial $tier"
    git branch live
  )
  git clone -q --bare "$seed_dir" "$bare"
  rm -rf "$seed_dir"

  git -C "$mempath" -c protocol.file.allow=always submodule add --name "$tier" "$bare" "$tier" >/dev/null 2>&1
  (
    cd "$mempath/$tier" || exit 1
    git config user.email "test@example.com"
    git config user.name  "Test"
  )
  # Blessed commit inside the memory submodule so the FR11 gate admits it.
  GITLORE_MEMORY_COMMIT=1 git -C "$mempath" commit -q -m "Add $tier tier"
  # The tier belongs to the memory trunk: advance every other local branch to the
  # tier commit, so whichever branch SessionStart checks out still sees the tier.
  # (Otherwise checking out a stale branch drops memory/.gitmodules and the tier
  # looks unmounted.)
  local head br
  head="$(git -C "$mempath" rev-parse HEAD)"
  while IFS= read -r br; do
    [ -n "$br" ] || continue
    git -C "$mempath" branch -f "$br" "$head" >/dev/null 2>&1 || true
  done < <(git -C "$mempath" for-each-ref --format='%(refname:short)' refs/heads)
}

# Push a new commit onto a tier remote's `live` branch and echo its SHA.
# Args: $1 = tier name (default "ddaanet"), $2 = line to append to MEMORY.md
push_tier_fact() {
  local tier="${1:-ddaanet}" line="${2:-- [x](x.md) — y}"
  local bare="$TMP_REPO/.bare-$tier.git" work
  work="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-tier-work.XXXXXX")"
  git clone -q "$bare" "$work"
  (
    cd "$work" || exit 1
    git config user.email "test@example.com"
    git config user.name  "Test"
    git checkout -q -B live origin/live
    printf '%s\n' "$line" >> MEMORY.md
    git commit -aqm "remote tier fact"
    git push -q origin live
  )
  git -C "$work" rev-parse HEAD
  rm -rf "$work"
}
