#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() { teardown_tmp_repo; }

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

@test "no launcher-guard JSON when GITLORE_LAUNCHED is set" {
  make_parent_with_memory
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  GITLORE_LAUNCHED=1 run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "rejects parent branch named 'live'" {
  make_parent_with_memory
  git checkout -q -b live
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 1 ]
  [[ "$output$stderr" == *"reserved"* ]] || [[ "${output}${stderr}" == *"live"* ]]
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

@test "warns and skips ff when memory is dirty" {
  make_parent_with_memory
  echo dirty > memory/scratch.md
  git checkout -q -b worktree
  mkdir -p .claude
  printf '{"gitlore":{"enabled":true}}\n' > .claude/settings.json
  run --separate-stderr bash "$SESSION_START"
  [ "$status" -eq 0 ]
  [[ "$output$stderr" == *"uncommitted"* ]] || [[ "${output}${stderr}" == *"dirty"* ]]
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
