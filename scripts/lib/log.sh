#!/usr/bin/env bash
# Branch a message based on whether we're being run inside a Claude Code session.

# Args: $1 = agent-targeted text, $2 = user-targeted text.
# Output goes to stdout for easy capture in tests. Hook scripts redirect to stderr
# at the call site when failing.
gitlore_say_for_agent_or_user() {
  local agent_msg="$1"
  local user_msg="$2"
  if [ -n "${CLAUDECODE:-}" ]; then
    printf '%s\n' "$agent_msg"
  else
    printf '%s\n' "$user_msg"
  fi
}
