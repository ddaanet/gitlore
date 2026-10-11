#!/usr/bin/env bash
set -euo pipefail
unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below

mkdir -p .claude

# settings.json — tracked. Rewritten in place through a variable rather than
# `mktemp` + `mv`: the temp file is created 0600 and mv would carry that mode
# onto a file that was 0644. The `del` drops a precommitCommand an earlier
# version wrote (D58: the commit is the agent's act, no command is recorded).
if [ -f .claude/settings.json ]; then
  merged=$(jq '.gitlore.enabled = true | del(.gitlore.precommitCommand)' \
     .claude/settings.json)
  printf '%s\n' "$merged" > .claude/settings.json
else
  jq -n '{gitlore: {enabled: true}}' > .claude/settings.json
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
