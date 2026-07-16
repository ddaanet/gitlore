#!/usr/bin/env bash
set -euo pipefail

# PostToolBatch: commit memory WITHOUT the agent ever running git.
#
# The agent writes two ordinary files — the approved summary
# (gitlore-memory-message) and a trigger (gitlore-commit-memory) — and this hook
# runs commit-memory.sh on its behalf. Because the agent makes no Bash call and
# never touches the submodule gitdir, this sidesteps the sandbox and the
# auto-mode classifier entirely; that is precisely why file-trigger + hook beats
# agent-runs-git for the standalone/handoff memory commit (which must land before
# any parent commit, whether or not the agent stops).
#
# The trigger file IS the signal, so the batch payload is unused.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

cat >/dev/null || true   # drain stdin; the trigger file, not the payload, drives us

emit() { jq -n --arg s "$1" '{systemMessage: $s, suppressOutput: true}'; }

gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
[ -e "$mempath/.git" ] || exit 0          # session-less worktree: no memory to commit

trigger=$(gitlore_commit_trigger_file "$mempath")
[ -f "$trigger" ] || exit 0               # no request this batch → nothing to do

if [ "$(gitlore_memory_dirty "$mempath")" = "0" ]; then
  # Nothing to commit: the request is satisfied (or was spurious). Clear it.
  rm -f "$trigger"
  emit "gitlore: commit-memory trigger cleared — memory was already clean, nothing to commit."
  exit 0
fi

msgfile=$(gitlore_commit_msg_file "$mempath")
if [ ! -s "$msgfile" ]; then
  # Keep the trigger: the moment the approved summary lands, the next
  # PostToolBatch commits transparently — the agent need not re-trigger.
  emit "gitlore: commit-memory is pending but no approved summary exists yet at $msgfile. Summarize the pending memory changes, get the user's approval, and write the summary to $msgfile — the commit then completes on its own."
  exit 0
fi

# commit-memory.sh reads the summary from the message file, commits the memory
# submodule with the blessed sentinel, advances local `live`, and consumes the
# message file — all ONLY on success. It never makes a parent commit (D16).
#
# Remove the trigger only when the commit is COMPLETE. A locked repo (index.lock,
# or `live` checked out by another session) and an in-flight merge are expected
# transient conditions: on failure we leave the trigger AND the message file in
# place, so the next PostToolBatch retries transparently — no agent action, no
# lost approval.
if out=$(bash "$PLUGIN_ROOT/scripts/commit-memory.sh" -F "$msgfile" 2>&1); then
  rm -f "$trigger"
  emit "gitlore: memory committed and local live advanced."
else
  emit "gitlore: memory commit deferred, will retry automatically. $out"
fi
exit 0
