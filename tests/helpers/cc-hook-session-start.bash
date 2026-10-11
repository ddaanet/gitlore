#!/usr/bin/env bash
# Shared setup for the SessionStart hook suites: the hook path both drive,
# and the tmp-repo/worktree lifecycle both need for teardown.

# shellcheck disable=SC2034   # used by callers' @test bodies
SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

# Enable gitlore in the fixture repo, as a launched session sees it.
enable_gitlore() {
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
}

# Assert one report line, matched loosely by ERE, on BOTH hook channels: the
# user-only systemMessage and the agent's additionalContext (D14, D59). Reads
# the hook JSON from $output.
# shellcheck disable=SC2154   # $output is bats' `run` capture, set by the caller
assert_report_on_both_channels() {
  echo "$output" | jq -e --arg re "$1" '.systemMessage | test($re)'
  echo "$output" | jq -e --arg re "$1" '.hookSpecificOutput.additionalContext | test($re)'
}

# Publish `live` to the memory remote (the fixture's origin is a bare repo that
# carries only `main`) so a later fetch of `origin live` has something to find.
publish_live_to_remote() {
  git -C memory push -q origin live
}

# Add $1 commits to the memory remote's `live` that this checkout lacks, made
# from a scratch clone. Publish `live` first.
push_remote_commits() {
  local n="$1" i work rc
  work="$(mktemp -d "$TMP_REPO/remote-work.XXXXXX")"
  (
    cd "$work" || exit 1
    git clone -q -b live "$(git -C "$TMP_REPO/memory" config --get remote.origin.url)" .
    i=1
    while [ "$i" -le "$n" ]; do
      printf 'remote-%s\n' "$i" > "REMOTE_$i.md"
      git add -A
      git -c user.email=t@t -c user.name=t commit -q -m "remote fact $i"
      i=$((i + 1))
    done
    git push -q origin live
  )
  rc=$?
  rm -rf "$work"
  return "$rc"
}
