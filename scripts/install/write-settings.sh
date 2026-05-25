#!/usr/bin/env bash
set -euo pipefail

mempath="$1"
precommit_cmd="$2"

mkdir -p .claude

# settings.json — tracked.
if [ -f .claude/settings.json ]; then
  tmp=$(mktemp)
  jq --arg pc "$precommit_cmd" \
     '.gitlore.enabled = true | .gitlore.precommitCommand = $pc' \
     .claude/settings.json > "$tmp"
  mv "$tmp" .claude/settings.json
else
  jq -n --arg pc "$precommit_cmd" \
     '{gitlore: {enabled: true, precommitCommand: $pc}}' > .claude/settings.json
fi

# Make sure .claude/settings.local.json is gitignored.
if [ -f .gitignore ]; then
  grep -qx '.claude/settings.local.json' .gitignore || \
    printf '\n.claude/settings.local.json\n' >> .gitignore
else
  printf '.claude/settings.local.json\n' > .gitignore
fi

# Hook dir.
git config gitlore.hooksDir "${CLAUDE_PLUGIN_ROOT}/scripts/git-hooks"
