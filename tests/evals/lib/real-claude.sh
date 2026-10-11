#!/usr/bin/env bash
# Runs the real claude for an eval turn, past any dogfood shim on PATH.
#
# A developer's PATH can resolve `claude` to plugin-dev/bin/claude, which exports
# CLAUDE_CODE_PLUGIN_DIRS and execs the next claude, loading the plugin twice.
# eval_claude runs the child with every plugin-dev/bin entry removed from PATH
# and CLAUDE_CODE_PLUGIN_DIRS unset. The caller's shell is not changed.
#
# Residual bound: a shim directory spelled as a symlink, or with a `/./` or `//`
# inside it, is not recognised; only the plain and trailing-slash spellings are.
#
# Usage: eval_claude <claude args...>   (stdin, stdout, stderr and status pass through)

# Removes dogfood-shim entries from PATH, then execs claude in a subshell.
eval_claude() {
  local rest="$PATH:" entry dir kept=""
  while [ -n "$rest" ]; do
    entry="${rest%%:*}"
    rest="${rest#*:}"
    dir="$entry"
    while [ "${dir%/}" != "$dir" ]; do dir="${dir%/}"; done
    case "$dir" in
      */plugin-dev/bin) continue ;;
    esac
    kept="$kept:$entry"
  done
  (
    unset CLAUDE_CODE_PLUGIN_DIRS
    PATH="${kept#:}"
    exec claude "$@"
  )
}
