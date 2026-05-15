#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
cd "$PROJECT_DIR"

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

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
