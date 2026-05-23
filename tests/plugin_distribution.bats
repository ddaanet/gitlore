#!/usr/bin/env bats
# Guards on the gitlore repo AS A DISTRIBUTED PLUGIN. Unlike the rest of the
# suite (which exercises fixtures), these inspect this repo's own tracked files,
# because /plugin install clones THIS repo recursively.

load helpers/setup

# Regression: Plan 04 Step 6 dogfood.
# `/plugin install gitlore@ddaanet` clones ddaanet/gitlore with --recurse-submodules.
# A relative submodule url (e.g. the local-only placeholder `./.git/gitlore-placeholder`)
# is resolved against the GitHub remote -> `git@github.com:ddaanet/gitlore.git/.git/...`
# -> "not a valid repository name" -> install aborts. The distributed .gitmodules must
# therefore carry an ABSOLUTE, fetchable url for the self-hosted memory submodule.
@test "distribution: gitlore-memory submodule url is absolute and fetchable" {
  [ -f "$PLUGIN_ROOT/.gitmodules" ]
  run git config --file "$PLUGIN_ROOT/.gitmodules" submodule.gitlore-memory.url
  [ "$status" -eq 0 ]
  url="$output"
  # Not the local-only placeholder.
  [ "$url" != "./.git/gitlore-placeholder" ]
  # Must be an absolute remote url scheme. This excludes both relative paths
  # (./foo) and bare filesystem paths (/foo) -- neither is fetchable by an
  # installer cloning from GitHub.
  [[ "$url" =~ ^(https?://|git@|ssh://|git://) ]]
}

# Regression: Plan 04 Step 6 dogfood.
# memory-merger failed to dispatch (Task subagent_type "gitlore:memory-merger" ->
# "Agent type not found") because its frontmatter lacked the REQUIRED `name:` field
# (CC does not fall back to the filename). It also used `allowed-tools:`, which CC
# ignores for AGENT definitions (that key is for skills/commands) -- so the agent
# silently inherited ALL tools, defeating the design's removal of SendMessage from
# the approval-gated sub-agent. `claude plugin validate` did not catch either.
@test "distribution: memory-merger agent declares name and uses tools (not allowed-tools)" {
  agent="$PLUGIN_ROOT/agents/memory-merger.md"
  [ -f "$agent" ]
  # Extract the YAML frontmatter (between the first two --- fences).
  fm="$(awk 'NR==1&&/^---$/{f=1;next} /^---$/{exit} f' "$agent")"
  # Required: a kebab-case name matching the dispatch id `gitlore:memory-merger`.
  echo "$fm" | grep -qE '^name:[[:space:]]*memory-merger[[:space:]]*$'
  # Must restrict tools via `tools:` ...
  echo "$fm" | grep -qE '^tools:[[:space:]]*'
  # ... and must NOT use the agent-invalid `allowed-tools:` key.
  ! echo "$fm" | grep -qE '^allowed-tools:'
  # The approval-gated sub-agent must not be able to message the parent itself.
  ! echo "$fm" | grep -qiE '^tools:.*SendMessage'
}

# Regression: slash commands must live directly under commands/ so they expose as
# /gitlore:<name>. A commands/gitlore/ subdir double-prefixes them to
# /gitlore:gitlore:<name>. Keep install/resolve flat, and don't reintroduce a
# redundant skills/install that would collide with the /gitlore:install command.
@test "distribution: slash commands are flat (no /gitlore:gitlore: double-prefix)" {
  [ -f "$PLUGIN_ROOT/commands/install.md" ]
  [ -f "$PLUGIN_ROOT/commands/resolve.md" ]
  [ ! -d "$PLUGIN_ROOT/commands/gitlore" ]
  [ ! -e "$PLUGIN_ROOT/skills/install/SKILL.md" ]
}
