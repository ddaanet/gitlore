#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures

HOOK="$PLUGIN_ROOT/scripts/cc-hooks/worktree-remove.sh"
SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

setup()    { setup_tmp_repo; export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"; }
teardown() {
  [ -n "${WT:-}" ] && rm -rf "$WT"
  teardown_tmp_repo
}

@test "no-op when no gitlore-memory submodule is registered" {
  run bash "$HOOK" <<<'{"worktree_path":"/tmp/does-not-matter"}'
  [ "$status" -eq 0 ]
}

@test "no-op when worktree_path is missing from input" {
  make_parent_with_memory
  run bash "$HOOK" <<<'{}'
  [ "$status" -eq 0 ]
}

@test "removes the memory worktree SessionStart created for a linked worktree" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
  mkdir -p "$WT/.claude"
  printf '{"gitlore":{"enabled":true}}\n' > "$WT/.claude/settings.json"
  CLAUDE_PROJECT_DIR="$WT" GITLORE_LAUNCHED=1 bash "$SESSION_START"
  [ -e "$WT/memory/.git" ]

  mem_gitdir="$TMP_REPO/.git/modules/gitlore-memory"
  git -C "$mem_gitdir" worktree list --porcelain | grep -qF "$WT/memory"

  run bash "$HOOK" <<<"{\"worktree_path\":\"$WT\"}"
  [ "$status" -eq 0 ]
  ! git -C "$mem_gitdir" worktree list --porcelain | grep -qF "$WT/memory"
}

@test "advisory: a locked memory worktree is not force-removed, hook still exits 0 with a warning" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
  mkdir -p "$WT/.claude"
  printf '{"gitlore":{"enabled":true}}\n' > "$WT/.claude/settings.json"
  CLAUDE_PROJECT_DIR="$WT" GITLORE_LAUNCHED=1 bash "$SESSION_START"
  [ -e "$WT/memory/.git" ]

  mem_gitdir="$TMP_REPO/.git/modules/gitlore-memory"
  # Lock it: `git worktree remove --force` refuses a locked tree (needs -f -f),
  # and `prune` won't reclaim it while its dir exists. The advisory hook must
  # respect the lock — never block CC, never escalate to double-force.
  git -C "$mem_gitdir" worktree lock "$WT/memory"

  run bash "$HOOK" <<<"{\"worktree_path\":\"$WT\"}"
  [ "$status" -eq 0 ]
  [[ "$output" == *"locked"* ]]
  # The locked worktree survives — not force-removed behind the lock.
  git -C "$mem_gitdir" worktree list --porcelain | grep -qF "$WT/memory"

  git -C "$mem_gitdir" worktree unlock "$WT/memory"  # let teardown clean up
}

@test "prunes a dangling memory worktree when the parent dir is already gone" {
  make_parent_with_memory
  WT="$TMP_REPO-wt"
  git worktree add -q -b feat-x "$WT" >/dev/null 2>&1
  mkdir -p "$WT/.claude"
  printf '{"gitlore":{"enabled":true}}\n' > "$WT/.claude/settings.json"
  CLAUDE_PROJECT_DIR="$WT" GITLORE_LAUNCHED=1 bash "$SESSION_START"

  mem_gitdir="$TMP_REPO/.git/modules/gitlore-memory"
  rm -rf "$WT"   # parent worktree dir removed before the hook fires
  run bash "$HOOK" <<<"{\"worktree_path\":\"$WT\"}"
  [ "$status" -eq 0 ]
  ! git -C "$mem_gitdir" worktree list --porcelain | grep -qF "$WT/memory"
  WT=""          # already removed; skip teardown rm
}
