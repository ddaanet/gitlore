#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR"

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"

# Guard 1: gitlore.enabled
enabled=$(jq -r '.gitlore.enabled // false' .claude/settings.json 2>/dev/null || echo false)
[ "$enabled" = "true" ] || exit 0

# Guard 2: gitlore-memory submodule registered
gitlore_has_submodule || exit 0

mempath=$(gitlore_memory_path)
absmem=$(cd "$mempath" 2>/dev/null && pwd || echo "$PROJECT_DIR/$mempath")

# Update settings.local.json (create or merge).
mkdir -p .claude
if [ -f .claude/settings.local.json ]; then
  tmp=$(mktemp)
  jq --arg p "$absmem" '.autoMemoryDirectory = $p' .claude/settings.local.json > "$tmp"
  mv "$tmp" .claude/settings.local.json
else
  printf '{"autoMemoryDirectory":"%s"}\n' "$absmem" > .claude/settings.local.json
fi

# Hook dir + wrappers.
git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
bash "$PLUGIN_ROOT/scripts/emit-wrappers.sh"

# Sentinel replay: re-apply hook-setup recorded at install time.
SENTINEL=".claude/gitlore-hook-setup"
if [ -f "$SENTINEL" ]; then
  cmd=$(head -1 "$SENTINEL" | tr -d '\n')
  case "$cmd" in
    "")
      echo "gitlore: empty sentinel; nothing to replay" >&2
      ;;
    direct)
      bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"
      ;;
    manual)
      echo "gitlore: hook wiring is 'manual'; verify .git/gitlore-pre-* are still invoked by your hooks." >&2
      ;;
    *)
      sh -c "$cmd"
      ;;
  esac
fi

# Branch model: guard, submodule init, checkout, ff-merge.
parent_branch=$(gitlore_parent_branch)
if [ "$parent_branch" = "live" ]; then
  msg=$(gitlore_say_for_agent_or_user \
    "gitlore: parent branch 'live' collides with the memory trunk. Rename the parent branch (git branch -m) before continuing." \
    "gitlore: this repo's parent branch is named 'live', which collides with gitlore's memory trunk. Rename it (git branch -m) before using gitlore.")
  echo "$msg" >&2
  exit 1
fi

if [ ! -f "$mempath/.git" ] && [ ! -d "$mempath/.git" ]; then
  git submodule update --init -- "$mempath" >&2
fi

if [ "$parent_branch" = "DETACHED" ]; then
  git -C "$mempath" checkout --detach live >/dev/null 2>&1 || true
else
  if git -C "$mempath" show-ref --verify --quiet "refs/heads/$parent_branch"; then
    git -C "$mempath" checkout -q "$parent_branch"
  else
    git -C "$mempath" checkout -q -b "$parent_branch" live
  fi
fi

if [ "$(gitlore_memory_dirty "$mempath")" = "0" ]; then
  if ! git -C "$mempath" merge --ff-only live >/dev/null 2>&1; then
    msg=$(gitlore_say_for_agent_or_user \
      "gitlore: memory branch '$parent_branch' diverged from live. Run /gitlore:resolve, then /clear." \
      "gitlore: memory branch '$parent_branch' has diverged from live. Open this project in Claude Code and run /gitlore:resolve, then start a fresh session.")
    echo "$msg" >&2
    exit 1
  fi
else
  echo "gitlore: memory has uncommitted changes; skipping live ff-merge." >&2
fi
