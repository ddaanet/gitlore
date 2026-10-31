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
  grep -qE '^name:[[:space:]]*memory-merger[[:space:]]*$' <<<"$fm"
  # Must restrict tools via `tools:` ...
  grep -qE '^tools:[[:space:]]*' <<<"$fm"
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
  [ -f "$PLUGIN_ROOT/commands/index-audit.md" ]
  # `-e`, not `-d`: a plain file named `commands/gitlore` is not a namespace
  # but is still not a command, and the directory test would pass over it.
  [ ! -e "$PLUGIN_ROOT/commands/gitlore" ]
  for name in install add-tier index-audit; do
    [ ! -e "$PLUGIN_ROOT/skills/$name/SKILL.md" ]
  done
}

# D47: memory-writing is a skill because its entry is a write under memory/,
# which no user types -- only a skill description is matched against context,
# and only if it names that moment. `memory/` is the token that pins it. Its
# other half, index-audit, is a command: a human decides when to run the pass.
@test "distribution: memory-writing is a skill whose description names the write moment (D47)" {
  skill="$PLUGIN_ROOT/skills/memory-writing/SKILL.md"
  [ -f "$skill" ]
  [ ! -e "$PLUGIN_ROOT/commands/memory-writing.md" ]
  fm="$(awk 'NR==1&&/^---$/{f=1;next} /^---$/{exit} f' "$skill")"
  grep -qE '^name:[[:space:]]*memory-writing[[:space:]]*$' <<<"$fm"
  # shellcheck disable=SC2016
  grep -qF '`memory/`' <<<"$fm"
  # The store-wide pass is the command, and the skill routes to it by name
  # rather than carrying the budgets itself.
  grep -qF '/gitlore:index-audit' "$skill"
  grep -qF 'memory-writing' "$PLUGIN_ROOT/commands/index-audit.md"
}

# D48: the description reaches the moment a fact is DRAFTED. The three moments
# that act on facts already written carry the trigger in text gitlore emits
# anyway — one per site, so a site losing it is visible here rather than only
# in an eval.
@test "distribution: the three post-write moments each invoke memory-writing (D48)" {
  # The commit moment: the gitlore:commit skill's review directive (D70). The
  # directive must precede the summary format it would otherwise read as a
  # footnote to, so compare line numbers rather than test for presence.
  local skill="$PLUGIN_ROOT/skills/commit/SKILL.md" directive_line body_line
  directive_line=$(grep -n 'invoke the .gitlore:memory-writing. skill' "$skill" | head -1 | cut -d: -f1)
  body_line=$(grep -n '^## Summary format' "$skill" | head -1 | cut -d: -f1)
  [ -n "$directive_line" ]
  [ -n "$body_line" ]
  [ "$directive_line" -lt "$body_line" ]
  # A store migrated by install, and the announcement the step is conditioned on.
  grep -qF 'gitlore:memory-writing' "$PLUGIN_ROOT/commands/install.md"
  grep -qF 'migrated auto-memory from' "$PLUGIN_ROOT/commands/install.md"
  grep -qF 'migrated auto-memory from' "$PLUGIN_ROOT/scripts/install/init-submodule.sh"
  # A tier mount: the nudge is the mechanical surface, the command body the
  # readable one. Both, since a hand edit of .gitlore-tiers reaches only the
  # nudge and a reader of the command reaches only the body.
  grep -qF 'gitlore:memory-writing' "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
  grep -qF 'gitlore:memory-writing' "$PLUGIN_ROOT/commands/add-tier.md"
  # Both commands pre-approve the call, so the trigger costs no permission
  # prompt — allowed-tools grants, it does not restrict.
  grep -qF 'Skill(gitlore:memory-writing)' "$PLUGIN_ROOT/commands/install.md"
  grep -qF 'Skill(gitlore:memory-writing)' "$PLUGIN_ROOT/commands/add-tier.md"
}

# Regression: resolve is a SELF-TRIGGERING skill, not a command (the Skills bullet
# of design.md's Architecture has said so since it gained its commit-triggered entry mode; only the file location
# lagged). A command is invoked deliberately by
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
  grep -qE '^name:[[:space:]]*resolve[[:space:]]*$' <<<"$fm"
  # The description carries the hook's own stderr marker, which is what the
  # agent matches on when a gate yields mid-task.
  grep -qF 'gitlore: memory merge prepared' <<<"$fm"
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
  grep -qE '^name:[[:space:]]*push[[:space:]]*$' <<<"$fm"
  # The script the skill shells out to must ship executable -- a 100644 here
  # makes the skill's one Bash call fail for every installed user.
  [ -x "$PLUGIN_ROOT/scripts/push-memory.sh" ]
  # The skill must reach the script through the plugin's bin/ name (D70), never
  # a hardcoded plugin path: CLAUDE_PLUGIN_ROOT is unset in agent Bash.
  [ -x "$PLUGIN_ROOT/bin/gitlore-push" ]
  grep -qE '(^|[^[:alnum:]:/-])gitlore-push([^[:alnum:]-]|$)' "$skill"
}

# merge is push's other half — take without publishing — and is a skill for the
# same reasons: /gitlore:merge is the front door, but a session start that named
# an upstream-ahead tier has to reach it from context.
@test "distribution: merge is a skill (not a command) and its script is executable" {
  skill="$PLUGIN_ROOT/skills/merge/SKILL.md"
  [ -f "$skill" ]
  [ ! -e "$PLUGIN_ROOT/commands/merge.md" ]
  fm="$(awk 'NR==1&&/^---$/{f=1;next} /^---$/{exit} f' "$skill")"
  grep -qE '^name:[[:space:]]*merge[[:space:]]*$' <<<"$fm"
  [ -x "$PLUGIN_ROOT/scripts/merge-memory.sh" ]
  [ -x "$PLUGIN_ROOT/bin/gitlore-merge" ]
  grep -qE '(^|[^[:alnum:]:/-])gitlore-merge([^[:alnum:]-]|$)' "$skill"
}

# record-rewrite.sh is run by hand by a store's owner after a history rewrite
# (D61), so nothing but its mode makes it reachable from an installed plugin.
@test "distribution: record-rewrite.sh exists and is executable" {
  [ -f "$PLUGIN_ROOT/scripts/record-rewrite.sh" ]
  [ -x "$PLUGIN_ROOT/scripts/record-rewrite.sh" ]
  [ "$(head -1 "$PLUGIN_ROOT/scripts/record-rewrite.sh")" = "#!/usr/bin/env bash" ]
}

# cross-rewrite.sh is run by hand to cross a store onto rewritten history (D62),
# the script the refusal names, so nothing but its mode makes it reachable.
@test "distribution: cross-rewrite.sh exists and is executable" {
  [ -f "$PLUGIN_ROOT/scripts/cross-rewrite.sh" ]
  [ -x "$PLUGIN_ROOT/scripts/cross-rewrite.sh" ]
  [ "$(head -1 "$PLUGIN_ROOT/scripts/cross-rewrite.sh")" = "#!/usr/bin/env bash" ]
}

# recall's dominant entry is mid-task and mechanical: a tool result surfaces a
# string the agent half-recognises. Only a skill description is matched against
# context, and only if it names that moment -- a description written around the
# user asking to "check memory" would never fire on the trigger the skill
# exists for. `tool result` is the phrase that pins it.
@test "distribution: recall is a skill whose description names the mid-task trigger" {
  skill="$PLUGIN_ROOT/skills/recall/SKILL.md"
  [ -f "$skill" ]
  run head -5 "$skill"
  [[ "$output" == *"name: recall"* ]]
  [[ "$output" == *"tool result"* ]]
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

# D58: a memory commit is the agent's own act, so nothing watches Bash for a
# commit command. The positive half pins that the hooks it sits beside are still
# registered, so a hooks.json that lost every entry does not satisfy the absence.
@test "distribution: hooks.json registers no PostToolUse(Bash) hook" {
  run jq -r '[.hooks.PostToolUse[] | select(.matcher=="Bash")] | length' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  run jq -r '[.hooks.SessionStart[] | select(.matcher=="*") | .hooks[].command | select(test("session-start"))] | length' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

# The nudge markers are re-armed where the context they were given to is
# replaced: a fresh session, /clear and a compaction, all SessionStart sources.
# The `*` group also fires on resume, which keeps its context, so nudge-reset
# sits in its own startup|clear|compact group and nowhere else. The PreCompact
# half uses `(.hooks.PreCompact // [])` so a hooks.json with no such key counts
# 0 rather than a jq error.
@test "distribution: nudge-reset runs on SessionStart(startup|clear|compact) only" {
  local hj="$PLUGIN_ROOT/hooks/hooks.json"
  run jq -r '[.hooks.SessionStart[] | select(.matcher=="startup|clear|compact") | .hooks[].command | select(test("nudge-reset"))] | length' "$hj"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  run jq -r '[.hooks.SessionStart[] | select(.matcher!="startup|clear|compact") | .hooks[].command | select(test("nudge-reset"))] | length' "$hj"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  # session-start.sh stays in the `*` group alone: in the new group it would
  # run twice on startup, clear and compact.
  run jq -r '[.hooks.SessionStart[] | select(.matcher!="*") | .hooks[].command | select(test("session-start"))] | length' "$hj"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
  run jq -r '[(.hooks.PreCompact // [])[].hooks[].command | select(test("nudge-reset"))] | length' "$hj"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# D51: relay-drain.sh is the ONE drainer of the relay, so an entry
# missing from hooks.json — or a duplicate one, which would relay every report
# twice — silences or doubles every subagent report across every installed
# repo, with no error, since hooks.json invokes by path. `length` is 1, not
# `>= 1`, for the duplicate half.
#
@test "distribution: relay-drain hook is wired on PostToolBatch and executable" {
  run jq -r '[.hooks.PostToolBatch[].hooks[].command | select(test("relay-drain"))] | length' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
  [ -x "$PLUGIN_ROOT/scripts/cc-hooks/relay-drain.sh" ]
  # Recorded mode, not the local filesystem mode: a marketplace clone reproduces
  # git's mode, and a local chmod would mask the bug.
  run git -C "$PLUGIN_ROOT" ls-files -s scripts/cc-hooks/relay-drain.sh
  [ "$status" -eq 0 ]
  [[ "$output" == 100755* ]]
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

# The committed dogfood shim is a byte copy of launcher-shim (emit-launcher.sh
# `cp`s it), and both headers say so. emit_launcher.bats only diffs a FRESH
# emission; this pins the copy this repo actually ships.
@test "distribution: the committed .gitlore/bin/claude is the current launcher-shim" {
  cmp "$PLUGIN_ROOT/.gitlore/bin/claude" "$PLUGIN_ROOT/scripts/install/launcher-shim"
}

# D60: a PostToolBatch hook that dies must report instead of ending the turn,
# and the report is the shared guard. The list is read from hooks.json, so a
# seventh hook is covered the day it is registered; the call must open a line
# (command position), so neither a comment nor a quoted name satisfies it. The
# bound: this proves the call opens a line of its own, not that the line runs
# or runs early; each hook's death test is what proves that.
@test "distribution: every PostToolBatch script calls gitlore_batch_hook_guard" {
  count=0
  missing=""
  while IFS= read -r script || [ -n "$script" ]; do
    count=$((count + 1))
    [ -f "$script" ] || { missing="$missing${missing:+, }$script (absent)"; continue; }
    if ! grep -Eq '^[[:space:]]*gitlore_batch_hook_guard([[:space:]]|$)' "$script"; then
      missing="$missing${missing:+, }$script"
    fi
  done < <(jq -r --arg root "$PLUGIN_ROOT" \
    '.hooks.PostToolBatch[].hooks[].command | gsub("\""; "") | sub("^\\$\\{CLAUDE_PLUGIN_ROOT\\}"; $root)' \
    "$PLUGIN_ROOT/hooks/hooks.json")
  [ "$count" -gt 0 ]
  if [ -n "$missing" ]; then
    echo "no gitlore_batch_hook_guard call in: $missing" >&2
    return 1
  fi
}

# A plugin installed under a path with a space must still run its hooks: the hook
# shell word-splits an unquoted ${CLAUDE_PLUGIN_ROOT}, and the hook fails with no
# visible error. Every command is exactly one double-quoted script path.
@test "distribution: every hooks.json command double-quotes its plugin-root path" {
  run jq -r '[.hooks[][].hooks[].command | select(test("^\"\\$\\{CLAUDE_PLUGIN_ROOT\\}/[^\" ]+\"$") | not)] | length' "$PLUGIN_ROOT/hooks/hooks.json"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# The commit skill is self-triggering: a pending memory change at the end of a
# task, or a request to commit memory, must reach it from context alone.
@test "distribution: commit skill ships with a self-trigger description and Bash+Skill tools" {
  skill="$PLUGIN_ROOT/skills/commit/SKILL.md"
  [ -f "$skill" ]
  fm="$(awk 'NR==1&&/^---$/{f=1;next} /^---$/{exit} f' "$skill")"
  grep -qE '^name:[[:space:]]*commit[[:space:]]*$' <<<"$fm"
  grep -E '^allowed-tools:' <<<"$fm" | grep -q 'Bash'
  grep -E '^allowed-tools:' <<<"$fm" | grep -q 'Skill'
  desc="$(grep -E '^description:' <<<"$fm")"
  grep -qi 'pending' <<<"$desc"
  grep -qi 'memory' <<<"$desc"
  grep -qi 'commit' <<<"$desc"
}

@test "distribution: commit skill body carries the review directive, section format and call" {
  skill="$PLUGIN_ROOT/skills/commit/SKILL.md"
  [ -f "$skill" ]
  # shellcheck disable=SC2016 # literal backticks
  grep -qF 'invoke the `gitlore:memory-writing` skill' "$skill"
  grep -qxF '== memory ==' "$skill"
  grep -qF '== <tier> ==' "$skill"
  grep -qxF "gitlore-commit <<'EOF'" "$skill"
  run grep -F 'gitlore-commit-memory' "$skill"
  [ "$status" -eq 1 ]
  grep -qF "<<'EOF'" "$skill"
}
