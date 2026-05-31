#!/usr/bin/env bash
# Exit 0 if gh is available and authenticated; non-zero with a fix-up
# message on stderr otherwise. Must do no destructive work.
set -euo pipefail

# gh is opportunistic (FR9): a missing or unauthed gh is NOT a hard failure —
# install falls back to local-only and the user can add a remote later. Only
# emit an advisory note so the agent can offer the gh path if desired.
if ! command -v gh >/dev/null 2>&1; then
  echo "gitlore: 'gh' CLI not found — proceeding; remote creation will be local-only unless a URL is supplied." >&2
elif ! gh auth status >/dev/null 2>&1; then
  echo "gitlore: 'gh' is not authenticated — proceeding; remote creation will be local-only unless a URL is supplied." >&2
fi

if [ -z "${CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS:-}" ]; then
  cat >&2 <<'EOF'
gitlore: CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS is not set.
gitlore: /gitlore:resolve requires it to dispatch the memory-merger sub-agent.
gitlore: Continuing install — set it before semantic merge is needed:
gitlore:   export CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1
EOF
fi

exit 0
