#!/usr/bin/env bats
# SessionStart over a root memory store holding a prepared merge, beyond the
# merge's own commands (session_start_mid_merge.bats): the position line beside
# it names no command, and a state file that cannot be parsed sends the repair
# to /gitlore:resolve and says so to the agent.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start
load helpers/merge-memory

# HEAD forked from local live, no remote involved: the head-vs-live flavor, a
# merge /gitlore:merge prepared. Leaves $statefile.
root_merge_prepared_against_live() {
  wire_memory_remote
  make_diverged_head_vs_live
  run bash "$CMD"
  [ "$status" -ne 0 ]
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
}

# Run SessionStart; $sys and $ctx are the two channels.
session_start_over_store() {
  enable_gitlore
  export GITLORE_LAUNCHED=1
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  sys=$(jq -r '.systemMessage // ""' <<<"$output")
  ctx=$(jq -r '.hookSpecificOutput.additionalContext // ""' <<<"$output")
}

# A state file that does not parse cannot say its publish mark, so the repair
# goes to /gitlore:resolve; the user's text is the one a state file with no
# mark and no briefing gets, and the agent is told the file could not be read.
# $1 is what the state file is overwritten with.
session_start_over_unreadable_state() {
  root_merge_prepared_against_live
  printf '{"flavor":"head-vs-live"}\n' > "$statefile"
  session_start_over_store
  local sys_plain="$sys"
  [[ "$ctx" != *"could not be read"* ]] || { printf 'a parsed state file is reported unreadable:\n%s\n' "$ctx" >&2; return 1; }
  printf '%s' "$1" > "$statefile"
  session_start_over_store
  [ "$sys" = "$sys_plain" ] || { printf 'the user text changed:\n%s\n---\n%s\n' "$sys_plain" "$sys" >&2; return 1; }
  [[ "$ctx" == *"Run /gitlore:resolve"* ]]
  [[ "$ctx" == *"$statefile, which could not be read as a merge state"* ]] || {
    printf 'the agent is not told the state file is unreadable:\n%s\n' "$ctx" >&2
    return 1
  }
  [[ "$stderr" != *"parse error"* && "$stderr" != *"jq:"* ]] || { printf 'jq text on stderr:\n%s\n' "$stderr" >&2; return 1; }
}

@test "SessionStart over an empty merge state file says the agent's state file could not be read" {
  session_start_over_unreadable_state ""
}

@test "SessionStart over a merge state file that is not JSON says the agent's state file could not be read" {
  session_start_over_unreadable_state "not json {"
}

# A tier's position beside a memory merge: the line lists it, and names no
# command, since the mid-merge report says not to commit memory or start
# another take; the report's own remedy stands.
@test "a tier ahead beside a mid-merge memory is listed with no /gitlore:push" {
  wire_memory_remote
  mount_tier_at_live ddaanet
  set_tier_manifest ddaanet
  commit_memory_state "memory: activate the tier"
  git -C memory push -q . HEAD:refs/heads/live
  git -C memory push -q origin live
  make_diverged_head_vs_live
  run bash "$CMD"
  [ "$status" -ne 0 ]
  [ -n "$(git -C memory rev-parse -q --verify MERGE_HEAD)" ]
  git -C memory/ddaanet -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local tier fact"
  git -C memory/ddaanet push -q . HEAD:refs/heads/live
  session_start_over_store
  for channel in "$sys" "$ctx"; do
    [[ "$channel" != *"Run /gitlore:push"* && "$channel" != *"Run /gitlore:merge"* ]] || {
      printf 'the line names a command beside the mid-merge report:\n%s\n' "$channel" >&2
      return 1
    }
    printf '%s\n' "$channel" | grep -qx 'gitlore: ddaanet 1 ahead' || {
      printf 'the tier is not listed in the bare line:\n%s\n' "$channel" >&2
      return 1
    }
    [[ "$channel" == *"continue-after-merge"* ]]
  done
}

