#!/usr/bin/env bats
# What each channel of an unresolvable-pin report carries. A url a contributor's
# PR controls (`.gitmodules`) or a remote the user configured is text the agent
# does not need and must not act on: the agent channel — SessionStart's
# additionalContext, and /gitlore:resolve's output under CLAUDECODE — carries
# the commit, the module and the remedy, and says the user has the urls. The
# user channel shows the urls with any credential removed — all the userinfo of
# an http(s) url, the `:password` of an ssh one, whose login the reader needs —
# so a credential embedded in a remote url never reaches either channel. The
# same rule covers the merge's refusal of a tier gitlink no repository holds.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/tier-fixtures
load helpers/cc-hook-session-start
load helpers/merge-memory
load helpers/take-order
load helpers/unresolvable-pin

TOKEN_TIER="ssh://user:tok3n@github.com/acme/tier.git"
TOKEN_OTHER="https://user:tok3n@example.com/acme/other.git"
TOKEN_MEM="ssh://user:tok3n@github.com/acme/mem.git"

# The tier's remote carries a credential and `.gitmodules` names another repo,
# also with a credential; the ssh stub serves the tier's fetch locally.
tier_gitlink_with_token_urls() {
  tier_gitlink_nobody_holds
  git -C memory/ddaanet config remote.origin.url "$TOKEN_TIER"
  serve_ssh_from "$TMP_REPO/.bare-ddaanet.git" memory/ddaanet
  git config --file memory/.gitmodules submodule.ddaanet.url "$TOKEN_OTHER"
  git -C memory add .gitmodules
  git -C memory commit -qm "record another repo, with a credential"
  git -C memory push -q . HEAD:refs/heads/live
}

parent_pin_with_token_urls() {
  parent_pin_nobody_holds
  git -C memory config remote.origin.url "$TOKEN_MEM"
  serve_ssh_from "$memory_remote" memory
  git config --file .gitmodules submodule.gitlore-memory.url "$TOKEN_OTHER"
  git add .gitmodules
  git commit -qm "record another repo, with a credential"
}

# Neither channel of the hook JSON in $output contains $1.
both_channels_lack() {
  jq -e --arg s "$1" '[.systemMessage // "", .hookSpecificOutput.additionalContext // ""] | all(.[]; contains($s) | not)' <<<"$output" >/dev/null || {
    printf 'a channel carries %s; hook output:\n%s\n' "$1" "$output" >&2
    return 1
  }
}

@test "SessionStart shows the user a tier remote and .gitmodules url without their credentials" {
  tier_gitlink_with_token_urls
  session_start
  sys_has "${lost:0:12}" "ssh://user@github.com/acme/tier.git" "https://example.com/acme/other.git" '/gitlore:push'
  both_channels_lack "tok3n"
  both_channels_lack "user:"
}

@test "SessionStart gives the agent the tier commit and the push remedy, and no url" {
  tier_gitlink_with_token_urls
  session_start
  ctx_has "${lost:0:12}" "ddaanet" '/gitlore:push'
  ctx_none "${lost:0:12}" "github.com" "example.com" ".bare-"
}

@test "SessionStart shows the user memory's remote and .gitmodules url without their credentials" {
  parent_pin_with_token_urls
  session_start
  sys_has "${lost:0:12}" "ssh://user@github.com/acme/mem.git" "https://example.com/acme/other.git" "merged upstream"
  both_channels_lack "tok3n"
  both_channels_lack "user:"
}

@test "SessionStart gives the agent the memory commit as not merged upstream, and no url" {
  parent_pin_with_token_urls
  session_start
  ctx_has "${lost:0:12}" "merged upstream"
  ctx_none "${lost:0:12}" "github.com" "example.com" "$TMP_REPO"
}

@test "/gitlore:resolve under CLAUDECODE names the tier commit and the push remedy with no url" {
  tier_gitlink_with_token_urls
  CLAUDECODE=1 run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  all=$(said)
  [[ "$all" == *"${lost:0:12}"* ]] || { printf 'resolve never names %s:\n%s\n' "${lost:0:12}" "$all" >&2; return 1; }
  [[ "$all" == *"/gitlore:push"* ]]
  [[ "$all" == *"revert-pin"* ]]
  [[ "$all" != *"github.com"* ]] || { printf 'the agent channel carries a url:\n%s\n' "$all" >&2; return 1; }
  [[ "$all" != *"example.com"* ]]
  [[ "$all" != *"tok3n"* ]]
}

@test "/gitlore:resolve for the user shows the tier urls without their credentials" {
  tier_gitlink_with_token_urls
  CLAUDECODE='' run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  all=$(said)
  [[ "$all" == *"ssh://user@github.com/acme/tier.git"* ]] || { printf 'the user channel lacks the stripped remote url:\n%s\n' "$all" >&2; return 1; }
  [[ "$all" == *"https://example.com/acme/other.git"* ]]
  [[ "$all" != *"tok3n"* ]] || { printf 'a credential reached the user channel:\n%s\n' "$all" >&2; return 1; }
}

@test "/gitlore:resolve under CLAUDECODE names the memory commit as not merged upstream with no url" {
  parent_pin_with_token_urls
  CLAUDECODE=1 run --separate-stderr bash "$PLUGIN_ROOT/scripts/resolve.sh"
  all=$(said)
  [[ "$all" == *"${lost:0:12}"* ]] || { printf 'resolve never names %s:\n%s\n' "${lost:0:12}" "$all" >&2; return 1; }
  [[ "$all" == *"merged upstream"* ]]
  [[ "$all" != *"github.com"* ]] || { printf 'the agent channel carries a url:\n%s\n' "$all" >&2; return 1; }
  [[ "$all" != *"example.com"* ]]
  [[ "$all" != *"tok3n"* ]]
}

@test "a tier remote carrying a credential still reads as the repo .gitmodules records without one" {
  tier_gitlink_nobody_holds
  git -C memory/ddaanet config remote.origin.url "https://user:tok3n@github.com/acme/tier.git"
  git config --file memory/.gitmodules submodule.ddaanet.url "https://github.com/acme/tier.git"
  git -C memory add .gitmodules
  git -C memory commit -qm "record the clean form"
  git -C memory push -q . HEAD:refs/heads/live
  # Read-only: the https fetch leaves the machine, so the fetch fails and the pin
  # check is skipped by SessionStart; the report builder is what is under test.
  run bash -c "cd '$PWD' && source '$PLUGIN_ROOT/scripts/lib/util.sh' && source '$PLUGIN_ROOT/scripts/lib/log.sh' && source '$PLUGIN_ROOT/scripts/lib/resolve.sh' && gitlore_unresolvable_tier_report memory ddaanet '$lost' user"
  [ "$status" -eq 0 ]
  [[ "$output" == *"https://github.com/acme/tier.git"* ]]
  [[ "$output" != *"different repo"* ]] || { printf 'one repo read as two:\n%s\n' "$output" >&2; return 1; }
  [[ "$output" != *"tok3n"* ]]
}

# The report builder for the user, over the tier's remote $1 and the url $2
# `.gitmodules` records for it.
tier_report_for_user() {
  tier_gitlink_nobody_holds
  git -C memory/ddaanet config remote.origin.url "$1"
  git config --file memory/.gitmodules submodule.ddaanet.url "$2"
  git -C memory add .gitmodules
  git -C memory commit -qm "record $2"
  git -C memory push -q . HEAD:refs/heads/live
  run bash -c "cd '$PWD' && source '$PLUGIN_ROOT/scripts/lib/util.sh' && source '$PLUGIN_ROOT/scripts/lib/log.sh' && source '$PLUGIN_ROOT/scripts/lib/resolve.sh' && gitlore_unresolvable_tier_report memory ddaanet '$lost' user"
  [ "$status" -eq 0 ]
}

# D64: `.gitmodules` records the https form while the tier's remote stays on
# ssh. The two name one repo, and the ssh url is shown with the login it needs.
@test "a tier remote on ssh://git@github.com reads as the https repo .gitmodules records, and keeps its login" {
  tier_report_for_user "ssh://git@github.com/acme/tier.git" "https://github.com/acme/tier.git"
  [[ "$output" == *"ssh://git@github.com/acme/tier.git"* ]] || { printf 'the ssh login was dropped:\n%s\n' "$output" >&2; return 1; }
  [[ "$output" != *"different repo"* ]] || { printf 'one repo read as two:\n%s\n' "$output" >&2; return 1; }
}

@test "a bare token in an https remote url is dropped from the user line" {
  tier_report_for_user "https://ghp_tok3n@github.com/acme/tier.git" "https://github.com/acme/tier.git"
  [[ "$output" == *"remote https://github.com/acme/tier.git holds"* ]] || { printf 'the remote is not shown clean:\n%s\n' "$output" >&2; return 1; }
  [[ "$output" != *"tok3n"* ]]
  [[ "$output" != *"different repo"* ]]
}

# The merge's refusal of a tier gitlink no repository holds follows the same
# rule: the agent gets the commit, the tier and the remedy; the user gets the
# remote without its password, and git's words.
@test "the tier gitlink refusal gives the agent no url and the user the remote without its password" {
  tier_gitlink_with_token_urls
  src="cd '$PWD' && source '$PLUGIN_ROOT/scripts/lib/util.sh' && source '$PLUGIN_ROOT/scripts/lib/log.sh' && source '$PLUGIN_ROOT/scripts/lib/resolve.sh' && gitlore_tier_holds_gitlink memory ddaanet '$lost'"
  CLAUDECODE=1 run --separate-stderr bash -c "$src"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"${lost:0:12}"* ]] || { printf 'the refusal never names the commit:\n%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" == *"/gitlore:push"* ]]
  [[ "$stderr" != *"github.com"* ]] || { printf 'the agent channel carries a url:\n%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" != *"tok3n"* ]]
  CLAUDECODE='' run --separate-stderr bash -c "$src"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"ssh://user@github.com/acme/tier.git"* ]] || { printf 'the user channel lacks the remote without its password:\n%s\n' "$stderr" >&2; return 1; }
  [[ "$stderr" != *"tok3n"* ]] || { printf 'a credential reached the user channel:\n%s\n' "$stderr" >&2; return 1; }
}
