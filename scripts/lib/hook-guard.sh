#!/usr/bin/env bash
# gitlore_batch_hook_guard (D60): a PostToolBatch hook that dies reports on both
# channels and exits 0. Function-only: sourcing this installs no trap, redirects
# nothing and creates no file. The guard is called from a hook, once, after its
# memory path resolves.

# Call once from a hook, after the memory path resolves and before the first
# fallible step. Args: $1 = hook name; $2 = memory worktree path; $3 = the
# consequence sentence for the agent, with what did not happen this batch.
#
# The hook's stderr goes to a capture file in the memory store's git dir, so
# that a death can be reported as one JSON object on stdout. The ERR trap
# records the failing command so that a death with no stderr still names what
# failed. GITLORE_HOOK_OWNED is a newline-joined list of files the hook has
# claimed; the EXIT trap removes them on every exit, a death included.
gitlore_batch_hook_guard() {
  GITLORE_HOOK_OWNED=""
  GITLORE_HOOK_NAME="$1"
  GITLORE_HOOK_CONSEQUENCE="$3"
  GITLORE_HOOK_CAPTURE=""
  GITLORE_HOOK_FAILED_CMD=""
  GITLORE_HOOK_FAILED_LINE=""
  GITLORE_HOOK_FAILED_STATUS=""
  set -E

  # Without a capture the guard still reports nothing but a remapped status,
  # so a store that cannot take the file is no reason to stop the hook.
  local gitdir=""
  if [ -n "$2" ]; then
    gitdir=$(git -C "$2" rev-parse --absolute-git-dir) || gitdir=""
  fi
  if [ -n "$gitdir" ] && GITLORE_HOOK_CAPTURE=$(mktemp "$gitdir/gitlore-hook-XXXXXX"); then
    # fd 9 keeps the real stderr for the EXIT trap to restore.
    exec 9>&2 2>"$GITLORE_HOOK_CAPTURE"
  fi

  trap 'GITLORE_HOOK_FAILED_STATUS=$?; GITLORE_HOOK_FAILED_CMD=$BASH_COMMAND; GITLORE_HOOK_FAILED_LINE=$LINENO' ERR
  trap 'gitlore_hook_guard_exit' EXIT
}

# EXIT trap. $? must be read first: it is the hook's status. The handler runs
# with errexit and nounset off, so nothing in it can replace that status.
gitlore_hook_guard_exit() {
  local rc=$?
  trap - ERR
  set +eu

  # The ERR record counts only when it came from the status this exit carries;
  # an explicit `exit 3` after an ignored failure must not name that failure.
  local cmd="" line=""
  if [ "${GITLORE_HOOK_FAILED_STATUS:-}" = "$rc" ]; then
    cmd="$GITLORE_HOOK_FAILED_CMD"
    line="$GITLORE_HOOK_FAILED_LINE"
  fi

  local cap="${GITLORE_HOOK_CAPTURE:-}"
  if [ -n "$cap" ]; then
    exec 2>&9 9>&-
  fi
  gitlore_hook_guard_remove_owned

  if [ "$rc" -eq 0 ]; then
    if [ -n "$cap" ] && [ -f "$cap" ]; then
      cat -- "$cap" >&2
      rm -f -- "$cap"
    fi
    exit 0
  fi

  if [ -n "$cap" ] && [ -f "$cap" ]; then
    local json=""
    if json=$(gitlore_hook_guard_json "$rc" "$cap" "$cmd" "$line") && [ -n "$json" ]; then
      rm -f -- "$cap"
      printf '%s\n' "$json"
      exit 0
    fi
    # The report cannot be encoded: the stderr is the only record left.
    cat -- "$cap" >&2
    rm -f -- "$cap"
  fi

  # A status of 2 is not reused: Claude Code treats exit 2 as a block, and a
  # PostToolBatch hook's block ends the turn with no reply.
  if [ "$rc" -eq 2 ]; then
    exit 1
  fi
  exit "$rc"
}

# Removes each file named in GITLORE_HOOK_OWNED. Newline-joined, one path per
# line; a path with spaces is one line, and a path with a newline is not
# supported.
gitlore_hook_guard_remove_owned() {
  printf '%s\n' "${GITLORE_HOOK_OWNED:-}" | while IFS= read -r owned || [ -n "$owned" ]; do
    if [ -n "$owned" ]; then
      rm -f -- "$owned"
    fi
  done
}

# Builds the one JSON object a death reports. Prints it on stdout and returns
# non-zero when jq does not produce it. Args: $1 = status; $2 = capture path;
# $3 = failing command, empty when none is recorded; $4 = its line.
gitlore_hook_guard_json() {
  local text="" where="" sys="" ctx=""
  text=$(cat -- "$2")
  if [ -n "$3" ]; then
    where=" at line $4, running: $3"
  fi
  sys="gitlore: hook $GITLORE_HOOK_NAME died with status $1$where. Its stderr: ${text:-(none)}"
  ctx="$sys $GITLORE_HOOK_CONSEQUENCE"
  jq -n --arg s "$sys" --arg c "$ctx" \
    '{systemMessage: $s,
      hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
}
