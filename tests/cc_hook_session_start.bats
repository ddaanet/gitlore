#!/usr/bin/env bats
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures

SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

@test "no-op when gitlore.enabled is missing" {
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -f .claude/settings.local.json ]
}

@test "no-op when .gitmodules has no gitlore-memory entry" {
  mkdir .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -f .claude/settings.local.json ]
}

@test "does not write settings.local.json (D10); sets hooksDir and emits wrappers" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ ! -f .claude/settings.local.json ]
  [ "$(git config gitlore.hooksDir)" = "$CLAUDE_PLUGIN_ROOT/scripts/git-hooks" ]
  [ "$(git config gitlore.commitCommand)" = "$CLAUDE_PLUGIN_ROOT/scripts/commit-memory.sh" ]
  [ -x .git/gitlore-pre-commit ]
  [ -x .git/gitlore-pre-push ]
}

@test "emits launcher-guard JSON on stdout when GITLORE_LAUNCHED is unset" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  unset GITLORE_LAUNCHED
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("direnv allow")'
  echo "$output" | jq -e '.hookSpecificOutput.hookEventName == "SessionStart"'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("GITLORE_LAUNCHED")'
}

@test "clean launched session: success confirmation on systemMessage, no launcher warning (D14)" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # D14 always-confirm: a clean start rides a success confirmation on systemMessage...
  echo "$output" | jq -e '.systemMessage | test("ready")'
  echo "$output" | jq -e '.systemMessage | test("synced with live")'
  # ...and it is NOT the launcher warning (shim ran).
  echo "$output" | jq -e '.systemMessage | test("direnv allow") | not'
  # The standing commit-protocol orientation (Fix B) is always present.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("memory submodule")'
}

@test "emits standing commit-protocol additionalContext every gitlore session" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  # The prohibition (the one piece that must precede any action) is present...
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("never commit"; "i")'
  # ...along with the one-line seamless happy path (commit the parent; hook handles it).
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("PARENT repo"; "i")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("seamless"; "i")'
  # ...but the four-step persist *procedure* is NOT front-loaded — it is surfaced
  # just-in-time by the pre-commit hook / gitlore:resolve, not the always-on context.
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("explicit user approval"; "i") | not'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("rev-parse --git-path gitlore-commit-msg"; "i") | not'
}

@test "wires the submodule commit gate (memory-pre-commit) into the submodule hooks dir" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  hookfile="$(git -C memory rev-parse --git-path hooks)/pre-commit"
  [ -x "$hookfile" ]
  # And it must actually block a naked direct commit.
  echo dirty > memory/notes.md
  git -C memory add -A
  CLAUDECODE=1 run --separate-stderr git -C memory commit -m "direct"
  [ "$status" -ne 0 ]
  [[ "${output}${stderr}" == *"blocked"* ]]
}

@test "rejects parent branch named 'live' via systemMessage, exit 0 (D14)" {
  make_parent_with_memory
  git checkout -q -b live
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  # D14: non-blocking exit, user-visible notice on systemMessage (not stderr+exit 1).
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("live")'
  echo "$output" | jq -e '.systemMessage | test("collides|reserved|rename"; "i")'
}

@test "creates worktree branch matching parent branch name from live" {
  make_parent_with_memory
  git checkout -q -b feat-x
  (cd memory && git checkout -q live)  # leave memory on live so SessionStart needs to act
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  run git -C memory branch --list feat-x
  [[ "$output" == *feat-x* ]]
}

@test "ff-merges memory branch to live when clean" {
  make_parent_with_memory
  # Advance live ahead of worktree branch.
  (
    cd memory
    git checkout -q live
    echo extra > MEMORY.md
    git commit -aq -m "Advance live"
    git checkout -q worktree
  )
  git checkout -q -b worktree  # parent branch mirrors memory's worktree branch
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  bash "$SESSION_START"
  # After SessionStart, memory worktree branch should equal live tip.
  livesha=$(git -C memory rev-parse live)
  wtsha=$(git -C memory rev-parse worktree)
  [ "$livesha" = "$wtsha" ]
}

@test "warns and skips ff when memory is dirty via systemMessage (D14)" {
  make_parent_with_memory
  echo dirty > memory/scratch.md
  git checkout -q -b worktree
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("uncommitted")'
}

@test "diverged memory branch reports via systemMessage, exit 0 (D14)" {
  make_parent_with_memory
  make_diverged_branch_vs_live
  git checkout -q -b worktree   # parent branch mirrors memory's diverged 'worktree'
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.systemMessage | test("diverged")'
  echo "$output" | jq -e '.systemMessage | test("resolve")'
}

@test "sentinel 'direct' re-applies direct wiring" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  printf 'direct\n' > .claude/gitlore-hook-setup
  bash "$SESSION_START"
  grep -q '# gitlore: managed' .git/hooks/pre-commit
}

@test "sentinel 'manual' emits a reminder to stderr" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  printf 'manual\n' > .claude/gitlore-hook-setup
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [[ "$stderr$output" == *"manual"* ]]
}

@test "arbitrary sentinel is executed as a shell command" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  printf 'touch SENTINEL_RAN\n' > .claude/gitlore-hook-setup
  bash "$SESSION_START"
  [ -f SENTINEL_RAN ]
}

@test "creates the memory worktree in a linked (CC-created) worktree on the parent-named branch" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
  # git populates the gitlink dir but does not check out the submodule:
  [ ! -e "$WT/memory/.git" ]
  mkdir -p "$WT/.claude"
  printf '{"gitlore":{"enabled":true}}\n' > "$WT/.claude/settings.json"

  CLAUDE_PROJECT_DIR="$WT" GITLORE_LAUNCHED=1 run bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ -e "$WT/memory/.git" ]
  run git -C "$WT/memory" rev-parse --abbrev-ref HEAD
  [ "$output" = "feat-x" ]
}
