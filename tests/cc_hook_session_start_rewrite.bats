#!/usr/bin/env bats
# SessionStart's divergence report on a clone left on rewritten history (D62):
# the first word such a clone hears names the crossing, not /gitlore:merge.
# The memory report travels on both channels (add_report); a tier's travels on
# the user's systemMessage alone (add_sysmsg). Fixture: helpers/rewrite-fixtures.bash.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/divergence-fixtures
load helpers/cc-hook-session-start
load helpers/rewrite-fixtures

mem_setup() {
  make_parent_with_memory
  rewrite_remote_history memory "$TMP_REPO/.bare-memory.git"
  rewrite_position_clone memory "$1"
  enable_gitlore
}

# The tier's new HEAD must be recorded in memory, or SessionStart's pin puts the
# tier back on the old gitlink before it compares.
tier_setup() {
  make_parent_with_memory
  mount_tier_at_live ddaanet
  rewrite_remote_history memory/ddaanet "$TMP_REPO/.bare-ddaanet.git"
  rewrite_position_clone memory/ddaanet "$1"
  git -C memory add ddaanet
  git -C memory commit -q -m "record the tier commit"
  # Memory's `live` at its HEAD: memory itself is level, so no /gitlore:push
  # hint in the message can come from anything but the tier.
  git -C memory update-ref refs/heads/live HEAD
  enable_gitlore
}

session_start() {
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
}

# --- memory ---

@test "session start: memory on a recorded old commit names the crossing on both channels" {
  mem_setup old
  session_start
  assert_report_on_both_channels 'cross-rewrite\.sh'
  assert_report_on_both_channels 'gitlore/rewrites'
  assert_channel_lacks .systemMessage '/gitlore:merge'
  assert_channel_lacks .hookSpecificOutput.additionalContext '/gitlore:merge'
}

@test "session start: record present, clone in fresh position — ordinary /gitlore:push divergence (control)" {
  mem_setup fresh
  session_start
  assert_report_on_both_channels 'diverged from live.*/gitlore:push'
  assert_lacks_on_both_channels '/gitlore:merge'
  assert_channel_lacks .systemMessage 'cross-rewrite'
  assert_channel_lacks .hookSpecificOutput.additionalContext 'cross-rewrite'
}

@test "session start: old position, record absent — ordinary /gitlore:push divergence (matched control)" {
  mem_setup old
  git --git-dir="$TMP_REPO/.bare-memory.git" update-ref -d refs/heads/gitlore/rewrites
  session_start
  assert_report_on_both_channels 'diverged from live.*/gitlore:push'
  assert_lacks_on_both_channels '/gitlore:merge'
  assert_channel_lacks .systemMessage 'cross-rewrite'
  assert_channel_lacks .hookSpecificOutput.additionalContext 'cross-rewrite'
}

@test "session start: an advertised but unfetchable record is named, not steered to /gitlore:merge" {
  mem_setup old
  rewrite_break_record "$TMP_REPO/.bare-memory.git"
  session_start
  assert_report_on_both_channels 'gitlore/rewrites'
  assert_channel_lacks .systemMessage '/gitlore:merge'
  assert_channel_lacks .hookSpecificOutput.additionalContext '/gitlore:merge'
}

@test "session start: never fetches an archive branch (old position)" {
  mem_setup old
  session_start
  [ -n "$(git -C memory ls-remote origin 'refs/heads/gitlore/archive/*')" ]
  assert_no_archive_fetched memory
}

@test "session start: never fetches an archive branch (fresh position)" {
  mem_setup fresh
  session_start
  [ -n "$(git -C memory ls-remote origin 'refs/heads/gitlore/archive/*')" ]
  assert_no_archive_fetched memory
}

@test "session start: moves no memory ref when it reports a rewrite" {
  mem_setup old
  head_before=$(git -C memory rev-parse HEAD)
  live_before=$(git -C memory rev-parse live)
  session_start
  assert_report_on_both_channels 'cross-rewrite\.sh'
  [ "$(git -C memory rev-parse HEAD)" = "$head_before" ]
  [ "$(git -C memory rev-parse live)" = "$live_before" ]
}

# --- a tier ---

@test "session start: a tier on a recorded old commit names the tier and the crossing" {
  tier_setup old
  session_start
  echo "$output" | jq -e '.systemMessage | test("ddaanet")'
  echo "$output" | jq -e '.systemMessage | test("cross-rewrite\\.sh")'
  echo "$output" | jq -e '.systemMessage | test("gitlore/rewrites")'
  assert_channel_lacks .systemMessage '/gitlore:merge'
  assert_channel_lacks .systemMessage '/gitlore:push'
}

@test "session start: a tier with a record but a fresh position — ordinary divergence names /gitlore:push (control)" {
  tier_setup fresh
  session_start
  echo "$output" | jq -e '.systemMessage | test("tier .ddaanet. has diverged from its remote")'
  echo "$output" | jq -e '.systemMessage | test("/gitlore:push")'
  assert_channel_lacks .systemMessage '/gitlore:merge'
  assert_channel_lacks .systemMessage 'cross-rewrite'
}

@test "session start: a tier on old position, record absent — ordinary divergence names /gitlore:push (matched control)" {
  tier_setup old
  git --git-dir="$TMP_REPO/.bare-ddaanet.git" update-ref -d refs/heads/gitlore/rewrites
  session_start
  echo "$output" | jq -e '.systemMessage | test("tier .ddaanet. has diverged from its remote")'
  echo "$output" | jq -e '.systemMessage | test("/gitlore:push")'
  assert_channel_lacks .systemMessage '/gitlore:merge'
  assert_channel_lacks .systemMessage 'cross-rewrite'
}

@test "session start: a tier whose record is advertised but unfetchable is named, not steered to /gitlore:merge" {
  tier_setup old
  rewrite_break_record "$TMP_REPO/.bare-ddaanet.git"
  session_start
  echo "$output" | jq -e '.systemMessage | test("ddaanet")'
  echo "$output" | jq -e '.systemMessage | test("gitlore/rewrites")'
  assert_channel_lacks .systemMessage '/gitlore:merge'
  assert_channel_lacks .systemMessage '/gitlore:push'
}

@test "session start: never fetches an archive branch into a tier" {
  tier_setup old
  session_start
  [ -n "$(git -C memory/ddaanet ls-remote origin 'refs/heads/gitlore/archive/*')" ]
  assert_no_archive_fetched memory/ddaanet
}
