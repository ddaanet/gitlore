#!/usr/bin/env bash
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "$0")/../lib/util.sh"

mempath="$1"
parent_root=$(git rev-parse --show-toplevel)

# Idempotency: three states —
#   fully registered (.gitmodules has the entry)  → already_registered=1
#   partial install (module store + gitfile, .gitmodules missing) → partial_install=1
#   not started                                   → both 0
already_registered=0
partial_install=0
if git config --file .gitmodules "submodule.gitlore-memory.path" 2>/dev/null | grep -qx "$mempath"; then
  already_registered=1
elif [ -d "$(git rev-parse --git-common-dir)/modules/gitlore-memory" ] && [ -f "$mempath/.git" ]; then
  partial_install=1
fi

if [ "$already_registered" -eq 0 ] && [ "$partial_install" -eq 0 ]; then
  # 1. Plain init at the target path.
  git init -q "$mempath"
  (
    cd "$mempath"
    git config user.email "gitlore@local"
    git config user.name  "gitlore"
  )

  # 2. Seed content (auto-memory migration, else scaffold).
  src=$(gitlore_cc_memory_dir "$parent_root")
  if [ -d "$src" ]; then
    cp -R "$src"/. "$mempath/"
    # Replace the migrated source with a stub recording the move in-tree, so a
    # session later launched without the shim (writing to this default dir) finds
    # a breadcrumb rather than silently re-seeding stranded memory.
    gitlore_mark_migrated "$src"
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

# Partial install: steps 1–4 already ran (module store absorbed, gitfile in place),
# but .gitmodules was never written (e.g. sandbox blocked the write).  Repair it.
if [ "$partial_install" -eq 1 ]; then
  placeholder_url="./.git/gitlore-placeholder"
  if ! { [ -f .gitmodules ] && grep -q '\[submodule "gitlore-memory"\]' .gitmodules; }; then
    {
      printf '[submodule "gitlore-memory"]\n'
      printf '\tpath = %s\n' "$mempath"
      printf '\turl = %s\n' "$placeholder_url"
    } >> .gitmodules
  fi
fi

# Steps 6-7 operate on the submodule via `git -C "$mempath"` / `cd "$mempath"`.
# If it is registered (already_registered=1) but not checked out here — e.g. a
# fresh clone before SessionStart, or after `git submodule deinit` — $mempath
# has no .git and every such op walks up to the PARENT repo, staging the
# parent's HEAD as the memory gitlink (unclonable superproject) and creating
# branches in the parent. Refuse rather than corrupt. (On a first-time install
# the init block above created $mempath/.git, so this never trips there.)
if [ ! -e "$mempath/.git" ]; then
  echo "gitlore: '$mempath' is registered as a submodule but not checked out here." >&2
  echo "gitlore: start a Claude Code session (SessionStart checks it out) or run 'git submodule update --init -- $mempath', then re-run install." >&2
  exit 1
fi

# 6. Stage parent-side artifacts. Runs on every install — including idempotent
#    re-runs after a reset — so the install's "leave it staged" contract holds
#    regardless of working-tree state. The submodule gitlink is written via
#    `git update-index --cacheinfo` (mode 160000) rather than `git add` so we
#    don't trip git's "embedded git repository" advice, which fires on `git add
#    <dir>` for any directory containing a .git/ entry and, in modern git,
#    actually refuses to stage the directory as a submodule.
if git check-ignore -q .gitmodules 2>/dev/null; then
  if [ -f .gitignore ] && grep -qx '\.gitmodules' .gitignore; then
    # Some repos gitignore .gitmodules to quiet sandbox-induced churn. With a
    # real submodule, .gitmodules must be tracked — drop the ignore line.
    tmp=$(mktemp) && grep -vx '\.gitmodules' .gitignore > "$tmp" && mv "$tmp" .gitignore
  fi
fi
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
