#!/usr/bin/env bash
# Layer 2 stand-in for the memory-merger sub-agent.
# Reads the state file, resolves any conflict markers by taking the
# 'ours' side (current HEAD's content), git add -A, then invokes the
# continuation as `bash $CLAUDE_PLUGIN_ROOT/scripts/resolve.sh <cont>`.

run_stub_synth() {
  local mempath="$1"
  local statefile
  statefile=$(git -C "$mempath" rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ] || { echo "stub-synth: no state file at $statefile" >&2; return 1; }
  local conflicted
  conflicted=$(jq -r '.conflicted_files[]?' "$statefile")
  while IFS= read -r f; do
    [ -n "$f" ] || continue
    git -C "$mempath" checkout --ours -- "$f" 2>/dev/null || true
  done <<< "$conflicted"
  (cd "$mempath" && git add -A)
  local cont
  cont=$(jq -r .continuation "$statefile")
  bash "$CLAUDE_PLUGIN_ROOT/scripts/resolve.sh" "$cont"
}
