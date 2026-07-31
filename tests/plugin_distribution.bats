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
  run grep -qE '^allowed-tools:' <<<"$fm"
  [ "$status" -ne 0 ]
  # The approval-gated sub-agent must not be able to message the parent itself.
  run grep -qiE '^tools:.*SendMessage' <<<"$fm"
  [ "$status" -ne 0 ]
}

# Regression: slash commands must live directly under commands/ so they expose as
# /gitlore:<name>. A commands/gitlore/ subdir double-prefixes them to
# /gitlore:gitlore:<name>. Keep them flat, and don't reintroduce a redundant
# skills/<name> that would collide with a command of the same name.
@test "distribution: slash commands are flat (no /gitlore:gitlore: double-prefix)" {
  [ -f "$PLUGIN_ROOT/commands/install.md" ]
  [ -f "$PLUGIN_ROOT/commands/add-tier.md" ]
  [ ! -d "$PLUGIN_ROOT/commands/gitlore" ]
  for name in install add-tier; do
    [ ! -e "$PLUGIN_ROOT/skills/$name/SKILL.md" ]
  done
}

# Regression: resolve is a SELF-TRIGGERING skill, not a command (design.md:181 and
# the 2026-05-26 changelog row have said so since it gained its commit-triggered
# entry mode; only the file location lagged). A command is invoked deliberately by
# the user, but resolve's dominant entry is mechanical -- the agent must reach for
# it on its own when a commit or push emits `gitlore: memory merge prepared`, and
# only a skill description is matched against context to make that happen. It
# stays user-invocable as /gitlore:resolve either way, so the standalone repair
# path (`resolve.sh` health check, post-compaction re-entry, a push run in the
# user's own terminal) survives the move.
@test "distribution: resolve is a skill with a self-trigger description" {
  skill="$PLUGIN_ROOT/skills/resolve/SKILL.md"
  [ -f "$skill" ]
  # Must not ALSO exist as a command -- same name in both namespaces collides.
  [ ! -e "$PLUGIN_ROOT/commands/resolve.md" ]
  fm="$(awk 'NR==1&&/^---$/{f=1;next} /^---$/{exit} f' "$skill")"
  # CC does not fall back to the filename for a skill's dispatch id.
  echo "$fm" | grep -qE '^name:[[:space:]]*resolve[[:space:]]*$'
  # The description carries the hook's own stderr marker, which is what the
  # agent matches on when a gate yields mid-task.
  echo "$fm" | grep -qF 'gitlore: memory merge prepared'
}

# D20: push is a skill, not a command, for the same reason resolve is -- it is
# user-initiated at the front door (/gitlore:push) but must ALSO be reachable
# from context, at the end of a session that committed memory and will make no
# parent push. Only a skill description is matched against context. It stays out
# of commands/ so the two namespaces cannot collide on the name.
@test "distribution: push is a skill (not a command) and its script is executable" {
  skill="$PLUGIN_ROOT/skills/push/SKILL.md"
  [ -f "$skill" ]
  [ ! -e "$PLUGIN_ROOT/commands/push.md" ]
  fm="$(awk 'NR==1&&/^---$/{f=1;next} /^---$/{exit} f' "$skill")"
  # CC does not fall back to the filename for a skill's dispatch id.
  echo "$fm" | grep -qE '^name:[[:space:]]*push[[:space:]]*$'
  # The script the skill shells out to must ship executable -- a 100644 here
  # makes the skill's one Bash call fail for every installed user.
  [ -x "$PLUGIN_ROOT/scripts/push-memory.sh" ]
  # The skill must reach the script through the config key, never a hardcoded
  # plugin path: CLAUDE_PLUGIN_ROOT is unset in agent Bash.
  grep -qF 'git config gitlore.pushCommand' "$skill"
}

# merge is push's other half — take without publishing — and is a skill for the
# same reasons: /gitlore:merge is the front door, but a session start that named
# an upstream-ahead tier has to reach it from context.
@test "distribution: merge is a skill (not a command) and its script is executable" {
  skill="$PLUGIN_ROOT/skills/merge/SKILL.md"
  [ -f "$skill" ]
  [ ! -e "$PLUGIN_ROOT/commands/merge.md" ]
  fm="$(awk 'NR==1&&/^---$/{f=1;next} /^---$/{exit} f' "$skill")"
  echo "$fm" | grep -qE '^name:[[:space:]]*merge[[:space:]]*$'
  [ -x "$PLUGIN_ROOT/scripts/merge-memory.sh" ]
  grep -qF 'git config gitlore.mergeCommand' "$skill"
}

# Regression: D15 — the in-process-worktree memory-drift guard must be registered
# as a PostToolUse hook on the EnterWorktree|ExitWorktree matcher, and its script
# must exist and be executable (verified to fire; targeted matcher chosen).
@test "distribution: worktree-drift hook is wired on EnterWorktree|ExitWorktree (D15)" {
  run jq -r '.hooks.PostToolUse[] | select(.matcher=="EnterWorktree|ExitWorktree") | .hooks[].command' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [[ "$output" == *"worktree-drift.sh"* ]]
  [ -x "$PLUGIN_ROOT/scripts/cc-hooks/worktree-drift.sh" ]
}

# The memory-commit trigger hook (FR11) must be registered on PostToolBatch —
# additive to the index-sync entry that shares the event — and executable, so a
# distributed plugin can commit memory on a file trigger without the agent
# running git (sidesteps the sandbox and the auto-mode classifier).
@test "distribution: memory-commit-batch hook is wired on PostToolBatch and executable" {
  run jq -r '[.hooks.PostToolBatch[].hooks[].command | select(test("memory-commit-batch"))] | length' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  [ -x "$PLUGIN_ROOT/scripts/cc-hooks/memory-commit-batch.sh" ]
}

# D21: the mid-session upgrade notice must be registered on PostToolBatch and
# ship executable. It is the one gitlore notice a stale session can still emit —
# hooks.json invokes by path, so a 100644 here would silence exactly the sessions
# whose plugin root has gone stale, in every installed repo.
@test "distribution: plugin-upgrade-batch hook is wired on PostToolBatch and executable" {
  run jq -r '[.hooks.PostToolBatch[].hooks[].command | select(test("plugin-upgrade-batch"))] | length' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  [ -x "$PLUGIN_ROOT/scripts/cc-hooks/plugin-upgrade-batch.sh" ]
  # Recorded mode, not the local filesystem mode: a marketplace clone reproduces
  # git's mode, and a local chmod would mask the bug.
  run git -C "$PLUGIN_ROOT" ls-files -s scripts/cc-hooks/plugin-upgrade-batch.sh
  [ "$status" -eq 0 ]
  [[ "$output" == 100755* ]]
}

# Positional invariant (add-tier triage-nudge design): add-tier-batch must run
# BEFORE index-compose in PostToolBatch. If a future edit swaps them back, a
# one-turn "write the intent file + list the tier" write would have
# index-compose fire while the tier is still unmounted — it would see a
# manifest entry for an absent module and refuse, forcing the two-turn flow
# back. This pins the order so that regression fails loudly here instead of
# surfacing as a baffling add-tier eval failure.
@test "distribution: add-tier-batch precedes index-compose in PostToolBatch" {
  run jq -r '.hooks.PostToolBatch[].hooks[].command' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  add_tier_line=$(printf '%s\n' "$output" | grep -n 'add-tier-batch' | cut -d: -f1)
  compose_line=$(printf '%s\n' "$output" | grep -n 'index-compose' | cut -d: -f1)
  [ -n "$add_tier_line" ]
  [ -n "$compose_line" ]
  [ "$add_tier_line" -lt "$compose_line" ]
}
