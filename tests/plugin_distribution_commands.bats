#!/usr/bin/env bats
# D70 guards on the gitlore repo AS A DISTRIBUTED PLUGIN: the bin/ entry points,
# the retired discovery keys and clause file, and the skill wording that names
# them. Companion to plugin_distribution.bats, which holds the other distribution
# guards; both inspect this repo's own tracked files, because /plugin install
# clones THIS repo recursively.

load helpers/setup

# D70: the entry points are the plugin's bin/ names. No script, skill, command
# or hook reaches one through a git-config discovery key, and the approval
# clause file and its key are gone; docs/ prose is swept separately.
@test "distribution: the approval clause file is gone" {
  [ ! -e "$PLUGIN_ROOT/reference/memory-approval-clause.txt" ]
}

@test "distribution: no discovery key or clause-file name survives outside docs" {
  run grep -rnE 'commitCommand|pushCommand|mergeCommand|memoryApprovalClauseFile|memory_approval_clause|memory-approval-clause' \
    "$PLUGIN_ROOT/scripts" "$PLUGIN_ROOT/skills" "$PLUGIN_ROOT/commands" \
    "$PLUGIN_ROOT/hooks" "$PLUGIN_ROOT/bin"
  # precommitCommand hits are D58's cleanup, not discovery keys.
  hits=$(printf '%s\n' "$output" | grep -v 'precommitCommand' || true)
  [ -z "$hits" ]
}

# Each skill that runs a memory command names its bin/ name, the one the agent's
# PATH resolves, and no skill or script header still names the retired script
# path as the way to call it.
@test "distribution: skills name the bin/ commands (D70)" {
  grep -qE '(^|[^[:alnum:]:/-])gitlore-commit([^[:alnum:]-]|$)' "$PLUGIN_ROOT/skills/commit/SKILL.md"
  grep -qE '(^|[^[:alnum:]:/-])gitlore-commit([^[:alnum:]-]|$)' "$PLUGIN_ROOT/skills/memory-writing/SKILL.md"
  grep -qE '(^|[^[:alnum:]:/-])gitlore-commit([^[:alnum:]-]|$)' "$PLUGIN_ROOT/skills/resolve/SKILL.md"
  grep -qF '/gitlore:commit' "$PLUGIN_ROOT/skills/push/SKILL.md"
}

# D70: a summary passed with the call is judged at that moment, so the resolve
# retry passes the summary again, re-approved when the merge brought content it
# did not cover; the old bare retry is false.
@test "distribution: resolve's retry passes the summary again (D70)" {
  local skill="$PLUGIN_ROOT/skills/resolve/SKILL.md"
  run grep -e 'Do not pass the original summary again' -e 'no .-m. and no .-F.' -e 'PostToolBatch' "$skill"
  [ "$status" -eq 1 ]
  grep -qiE 'summary.*again|again.*summary' "$skill"
  grep -qiE 're-?approv' "$skill"
}
