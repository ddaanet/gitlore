#!/usr/bin/env bash
set -euo pipefail

mempath="$1"
parent_root=$(git rev-parse --show-toplevel)

# Idempotency: if already registered, just ensure branches exist and exit.
already_registered=0
if git config --file .gitmodules "submodule.gitlore-memory.path" 2>/dev/null | grep -qx "$mempath"; then
  already_registered=1
fi

if [ "$already_registered" -eq 0 ]; then
  # 1. Plain init at the target path.
  git init -q "$mempath"
  (
    cd "$mempath"
    git config user.email "gitlore@local"
    git config user.name  "gitlore"
  )

  # 2. Seed content (auto-memory migration, else scaffold).
  #    CC encodes the project dir name by replacing every non-[A-Za-z0-9] byte
  #    with `-` (see anthropic/claude-code bundle; verified empirically against
  #    ~/.claude/projects/ entries). The >200-char truncate+hash fallback is
  #    out of scope here — repo abs paths reaching 200 chars are vanishingly
  #    rare and the scaffold path handles miss gracefully.
  encoded=$(printf '%s' "$parent_root" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  src="$HOME/.claude/projects/$encoded/memory"
  if [ -d "$src" ]; then
    cp -R "$src"/. "$mempath/"
  else
    cat > "$mempath/MEMORY.md" <<'EOF'
# Memory Index

(populated by Claude over time)
EOF
  fi

  # 3. Initial commit.
  (
    cd "$mempath"
    git add -A
    git commit -q -m "Initial memory"
  )

  # 4. Absorb gitdir manually: move <mempath>/.git into .git/modules/gitlore-memory
  #    and replace it with a gitfile pointer. This mirrors what `git submodule add`
  #    would do, but works in a parent repo with no commits yet.
  #
  #    (git submodule absorbgitdirs requires the submodule to already be tracked in
  #    the index, which needs at least one commit in the parent repo.)
  mkdir -p .git/modules/gitlore-memory
  cp -a "$mempath/.git/." .git/modules/gitlore-memory/
  rm -rf "$mempath/.git"
  printf 'gitdir: ../.git/modules/gitlore-memory\n' > "$mempath/.git"
  git config -f .git/modules/gitlore-memory/config core.worktree "../../../$mempath"

  # 5. Register in .gitmodules with a local placeholder URL.
  #    Plan 02 rewrites this to a real remote.
  placeholder_url="./.git/gitlore-placeholder"
  if [ -f .gitmodules ] && grep -q '\[submodule "gitlore-memory"\]' .gitmodules; then
    :
  else
    {
      printf '[submodule "gitlore-memory"]\n'
      printf '\tpath = %s\n' "$mempath"
      printf '\turl = %s\n' "$placeholder_url"
    } >> .gitmodules
  fi

fi

# 6. Stage parent-side artifacts. Runs on every install — including idempotent
#    re-runs after a reset — so the install's "leave it staged" contract holds
#    regardless of working-tree state. The submodule gitlink is written via
#    `git update-index --cacheinfo` (mode 160000) rather than `git add` so we
#    don't trip git's "embedded git repository" advice, which fires on `git add
#    <dir>` for any directory containing a .git/ entry and, in modern git,
#    actually refuses to stage the directory as a submodule.
git add .gitmodules
mem_sha=$(git -C "$mempath" rev-parse HEAD)
git update-index --add --cacheinfo "160000,${mem_sha},${mempath}"

# 7. live + worktree branches (idempotent).
cd "$mempath"
git show-ref --verify --quiet refs/heads/live || git branch live

cd "$parent_root"
parent_branch=$(git symbolic-ref --short -q HEAD 2>/dev/null || echo DETACHED)

cd "$mempath"
if [ "$parent_branch" = "DETACHED" ]; then
  git checkout -q --detach live
else
  git show-ref --verify --quiet "refs/heads/$parent_branch" || git branch "$parent_branch" live
  git checkout -q "$parent_branch"
fi
