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

# Build a bare tier REMOTE at $TMP_REPO/.bare-<tier>.git and echo its path.
# Default branch main with `live` alongside — the shape a tier remote must have
# (a `live` default gets checked out as a branch by the mount, and the ff-only
# `fetch origin live:live` then refuses).
# Args: $1 = tier name (default "ddaanet"); $2 = "nolive" to omit the live branch.
make_tier_remote() {
  local tier="${1:-ddaanet}" live="${2:-live}"
  local bare="$TMP_REPO/.bare-$tier.git" seed_dir
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
    [ "$live" = "nolive" ] || git branch live
  )
  git clone -q --bare "$seed_dir" "$bare"
  rm -rf "$seed_dir"
  printf '%s\n' "$bare"
}

# Mount a tier submodule inside an existing memory submodule.
# Requires: make_parent_with_memory has already run (cwd = $TMP_REPO).
# Args: $1 = tier subpath/name (default "ddaanet")
# Leaves: memory/<tier> checked out, the memory submodule committed, the parent
#         index NOT updated (the caller decides when the parent records it).
make_tier_in_memory() {
  local tier="${1:-ddaanet}" mempath="memory"
  local bare="$TMP_REPO/.bare-$tier.git"

  make_tier_remote "$tier" >/dev/null

  # Suppress the noise, but never the status: this is the fixture's central step,
  # and a silent failure here surfaces as a baffling assertion failure later.
  git -C "$mempath" -c protocol.file.allow=always \
    submodule add --name "$tier" "$bare" "$tier" >/dev/null 2>&1 \
    || { echo "make_tier_in_memory: submodule add '$tier' failed" >&2; return 1; }
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

# Write the tier activation manifest. Args: the active tier names, in
# precedence order. With no args the manifest is created empty.
set_tier_manifest() {
  : > memory/.gitlore-tiers
  local t
  for t in "$@"; do printf '%s\n' "$t" >> memory/.gitlore-tiers; done
}

# Append a bullet to a tier carrier's MEMORY.md (and create the file it names,
# so the store looks realistic). Args: $1 = tier, $2 = file name, $3 = hook.
seed_tier_bullet() {
  local tier="$1" file="$2" hook="$3"
  printf -- '- [%s](%s) — %s\n' "${file%.md}" "$file" "$hook" >> "memory/$tier/MEMORY.md"
  printf -- '---\nname: %s\ndescription: ""\n---\n\nbody\n' "${file%.md}" > "memory/$tier/$file"
}

# Commit the memory store's current tree. The down projection reads root at HEAD
# to tell a line root DELETED from one it never carried, so a test about a
# deletion has to establish that HEAD first. The blessed sentinel carries the
# commit past the FR11 gate. Args: $1 = commit subject (optional).
commit_memory_state() {
  git -C memory add -A || return 1
  GITLORE_MEMORY_COMMIT=1 git -C memory commit -q -m "${1:-memory: checkpoint}"
}

# Append a bullet to the ROOT index. Args: $1 = path (may be tier-prefixed),
# $2 = hook.
seed_root_bullet() {
  printf -- '- [%s](%s) — %s\n' "$(basename "${1%.md}")" "$1" "$2" >> memory/MEMORY.md
}

# Assert index $1's bullet block is EXACTLY the remaining args, in order.
#
# Use this instead of a presence grep paired with an absence grep whenever the
# absent string is a variant of the present one — a prefixed twin of an
# unprefixed line, the superseded wording of a line whose new wording is
# asserted. Such a pair cannot both be satisfied by the code that produces
# either, so no mutation makes the negative fail on its own: it restates the
# positive and can only ever go vacuous. An exact block has no absent string to
# go stale, and a dropped line, a stray duplicate, a reorder and a wording drift
# each fail it.
assert_bullets() {
  local f="$1"; shift
  local want got
  want=$(printf '%s\n' "$@")
  got=$(gitlore_index_part "$f" bullets)
  if [ "$got" != "$want" ]; then
    printf 'bullets of %s\n--- want ---\n%s\n--- got ---\n%s\n' "$f" "$want" "$got" >&2
    return 1
  fi
}

