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

# Assert the root memory store reports `in sync.` and the ready line is gone: a
# systemMessage paragraph with `in sync.` that names no tier (a tier's line holds
# its name, here `ddaanet`), and neither form of the old ready line ("memory
# ready", "memory ready (detached at live)"). Args: $1 = the hook JSON.
assert_memory_in_sync() {
  jq -e '.systemMessage // "" | split("\n\n") | any(.[]; contains("in sync.") and (contains("ddaanet") | not))' <<<"$1" >/dev/null || {
    printf 'no systemMessage paragraph reports memory in sync.; systemMessage:\n%s\n' "$(jq -r '.systemMessage // ""' <<<"$1")" >&2
    return 1
  }
  jq -e '.systemMessage // "" | (contains("memory ready") or contains("detached at live")) | not' <<<"$1" >/dev/null || {
    printf 'the ready line is still printed beside in sync.; systemMessage:\n%s\n' "$(jq -r '.systemMessage // ""' <<<"$1")" >&2
    return 1
  }
}

# Assert a jq regex does not match one hook channel. Reads the hook JSON from
# $output. Args: $1 = jq path (.systemMessage or .hookSpecificOutput.additionalContext),
# $2 = regex.
# shellcheck disable=SC2154   # $output is bats' `run` capture, set by the caller
assert_channel_lacks() {
  echo "$output" | jq -e --arg re "$2" "$1 | test(\$re) | not"
}

# Assert a regex is absent from BOTH channels. Pair each use with a positive
# assertion over the same fixture, or an absent message passes too.
assert_lacks_on_both_channels() {
  assert_channel_lacks .systemMessage "$1"
  assert_channel_lacks .hookSpecificOutput.additionalContext "$1"
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
