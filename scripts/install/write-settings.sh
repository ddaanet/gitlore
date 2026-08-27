#!/usr/bin/env bash
set -euo pipefail
unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below

precommit_cmd="$1"

mkdir -p .claude

# settings.json — tracked. Rewritten in place through a variable rather than
# `mktemp` + `mv`: the temp file is created 0600 and mv would carry that mode
# onto a file that was 0644.
if [ -f .claude/settings.json ]; then
  merged=$(jq --arg pc "$precommit_cmd" \
     '.gitlore.enabled = true | .gitlore.precommitCommand = $pc' \
     .claude/settings.json)
  printf '%s\n' "$merged" > .claude/settings.json
else
  jq -n --arg pc "$precommit_cmd" \
     '{gitlore: {enabled: true, precommitCommand: $pc}}' > .claude/settings.json
fi

# Make sure .claude/settings.local.json is gitignored.
if [ -f .gitignore ]; then
  # Append a trailing newline first only if the file does not already end in one,
  # so we never introduce a blank line.
  if [ -n "$(tail -c1 .gitignore)" ]; then
    printf '\n' >> .gitignore
  fi
  grep -qxF '.claude/settings.local.json' .gitignore || \
    printf '.claude/settings.local.json\n' >> .gitignore
else
  printf '.claude/settings.local.json\n' > .gitignore
fi

# Hook dir.
plugin_root="${CLAUDE_PLUGIN_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
git config gitlore.hooksDir "${plugin_root}/scripts/git-hooks"
git config gitlore.commitCommand "${plugin_root}/scripts/commit-memory.sh"
git config gitlore.pushCommand "${plugin_root}/scripts/push-memory.sh"
git config gitlore.mergeCommand "${plugin_root}/scripts/merge-memory.sh"
git config gitlore.memoryApprovalClauseFile "${plugin_root}/reference/memory-approval-clause.txt"
