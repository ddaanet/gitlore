#!/usr/bin/env bash
# Shared fixtures for the tier-divergence suites: the store-path constants,
# the tier mount, and the divergence shape every remote-divergence case needs.

PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"
PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"
RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"
SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"
export PRE_COMMIT PRE_PUSH RESOLVE SESSION_START

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
}
teardown() { teardown_tmp_repo; }

# Commit a tier fact locally after someone else advanced the tier remote, which
# is the shape every remote-divergence case below needs.
diverge_tier_from_remote() {
  local tier="${1:-ddaanet}"
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  echo "- [org fact](f.md) — ours" >> "memory/$tier/MEMORY.md"
  approve "memory: record the org fact"
  bash "$PRE_COMMIT"
  push_tier_fact "$tier" "- [their fact](t.md) — theirs" >/dev/null
}

tier_state_file() { git -C "memory/${1:-ddaanet}" rev-parse --git-path gitlore-merge-state; }
