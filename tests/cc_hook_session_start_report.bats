#!/usr/bin/env bats
# SessionStart reports and never moves memory (D59).
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start

@test "live ahead of a clean HEAD is reported on both channels and HEAD is not moved (D59)" {
  make_parent_with_memory
  # Two commits on live that the detached HEAD does not have.
  advance_branch_with_file memory live EXTRA1.md extra1 "Advance live 1"
  advance_branch_with_file memory live EXTRA2.md extra2 "Advance live 2"
  enable_gitlore
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # The report: the count, the take command, on user and agent channels alike.
  assert_report_on_both_channels '2 commits.*/gitlore:merge'
  # Nothing moved: HEAD stays at the gitlink, live stays where it was, and the
  # working tree does not carry live's files.
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
  [ ! -e memory/EXTRA1.md ]
}

@test "dirty memory is reported on both channels, nothing moves (D14, D59)" {
  make_parent_with_memory
  advance_branch_with_file memory live EXTRA.md extra "Advance live"
  echo dirty > memory/scratch.md
  enable_gitlore
  head_before=$(git -C memory rev-parse HEAD)
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_report_on_both_channels 'uncommitted changes'
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ -f memory/scratch.md ]
}

@test "HEAD diverged from live names /gitlore:resolve on both channels, moves nothing, exit 0 (D59)" {
  make_parent_with_memory
  make_diverged_head_vs_live
  enable_gitlore
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_report_on_both_channels '/gitlore:resolve'
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
}

@test "local live is created from HEAD, not from origin/live, when it is missing (D59)" {
  make_parent_with_memory
  # A fresh clone has only origin/live; model it with a remote tip that differs
  # from the checked-out gitlink and no local live.
  publish_live_to_remote
  push_remote_commits 1
  git -C memory fetch -q origin live
  git -C memory checkout -q --detach HEAD
  git -C memory branch -D live >/dev/null
  head_before=$(git -C memory rev-parse HEAD)
  [ "$(git -C memory rev-parse origin/live)" != "$head_before" ]
  enable_gitlore
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse live)" = "$head_before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "origin/live strictly ahead is reported with its count; local refs do not move (D59)" {
  make_parent_with_memory
  publish_live_to_remote
  push_remote_commits 2
  enable_gitlore
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_report_on_both_channels '2 upstream.*/gitlore:merge'
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
}

@test "origin/live diverged from live is reported naming /gitlore:merge; local refs do not move (D59)" {
  make_parent_with_memory
  publish_live_to_remote
  push_remote_commits 1
  # A local commit that HEAD and live share, absent from the remote.
  git -C memory -c user.email=t@t -c user.name=t commit -q --allow-empty -m "local fact"
  git -C memory update-ref refs/heads/live HEAD
  enable_gitlore
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_report_on_both_channels 'diverged.*/gitlore:merge'
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
}

@test "an unfetchable remote is named on both channels, exit 0, local refs do not move (D59)" {
  make_parent_with_memory
  git -C memory remote set-url origin "$TMP_REPO/no-such-remote.git"
  enable_gitlore
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_report_on_both_channels '(?i)fetch'
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
  # git's stderr can carry text the remote chose, so it is shown to the user and
  # kept out of the agent's context.
  echo "$output" | jq -e '.systemMessage | test("no-such-remote")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("no-such-remote") | not'
}

@test "a placeholder remote is not fetched; local live-ahead is still reported (D59)" {
  make_parent_with_memory
  git -C memory remote set-url origin "./.git/gitlore-placeholder"
  advance_branch_with_file memory live EXTRA.md extra "Advance live"
  enable_gitlore
  # Whatever the fixture left behind must not pass for the hook's own fetch.
  fetch_head=$(git -C memory rev-parse --path-format=absolute --git-path FETCH_HEAD)
  rm -f "$fetch_head"
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  assert_report_on_both_channels '1 commit.*/gitlore:merge'
  echo "$output" | jq -e '.systemMessage | test("fetch"; "i") | not'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("fetch"; "i") | not'
  [ ! -e "$fetch_head" ]
}

@test "local live is created from HEAD when origin/live does not exist at all (D59)" {
  make_parent_with_memory
  git -C memory branch -D live >/dev/null
  run git -C memory rev-parse -q --verify refs/remotes/origin/live
  [ "$status" -ne 0 ]
  head_before=$(git -C memory rev-parse HEAD)
  enable_gitlore
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ "$(git -C memory rev-parse live)" = "$head_before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
}

@test "a reachable remote with no live branch is silent: nothing upstream to take (D59)" {
  make_parent_with_memory
  # The stock fixture remote carries only `main`.
  run git -C memory ls-remote --exit-code origin refs/heads/live
  [ "$status" -ne 0 ]
  enable_gitlore
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # The hook still speaks: the orientation rides additionalContext.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("gitlore:commit")'
  echo "$output" | jq -e '.systemMessage | test("fetch|upstream"; "i") | not'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("fetch|upstream"; "i") | not'
}
