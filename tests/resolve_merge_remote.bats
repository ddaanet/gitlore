#!/usr/bin/env bats

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

PRE_PUSH="$PLUGIN_ROOT/scripts/git-hooks/pre-push"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  make_diverged_local_vs_remote memory
}
teardown() { teardown_tmp_repo; }

@test "local-vs-remote: pre-push yields directive on ff-push failure" {
  run --separate-stderr bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  [[ "$output$stderr" == *"memory merge prepared"* ]]
  [[ "$output$stderr" == *"flavor=local-vs-remote"* ]]
  [[ "$output$stderr" == *"continue-after-remote-merge"* ]]
  [[ "$output$stderr" == *"cd \"$TMP_REPO\" && bash \"$PLUGIN_ROOT/scripts/resolve.sh\""* ]]
  [[ "$output$stderr" != *'$CLAUDE_PLUGIN_ROOT'* ]]
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "local-vs-remote" ]
  # changed_files must include both sides: REMOTE.md (target, from origin advance)
  # AND LOCAL.md (source, from local-only commit).
  changed=$(jq -r '.changed_files[]' "$statefile" | sort | paste -sd, -)
  [ "$changed" = "LOCAL.md,REMOTE.md" ]
}

@test "local-vs-remote: stub-synth continuation commits + pushes to origin" {
  run bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  run_stub_synth memory
  # After continuation: local live matches origin/live, return_branch is checked out.
  local_live=$(git -C memory rev-parse live)
  remote_live=$(git --git-dir="$TMP_REPO/.bare-memory.git" rev-parse live)
  [ "$local_live" = "$remote_live" ]
  branch=$(git -C memory symbolic-ref --short HEAD)
  [ "$branch" = "live" ] || [ "$branch" = "worktree" ]  # whichever return_branch recorded
  [ ! -f "$(git -C memory rev-parse --git-path gitlore-merge-state)" ]
}

@test "local-vs-remote loop: continuation yields again if retry-push fails" {
  run bash "$PRE_PUSH"
  [ "$status" -ne 0 ]
  # Simulate another machine pushing to origin during synthesis.
  (
    cd "$(mktemp -d "$TMP_REPO/concurrent.XXXXXX")"
    git clone -q "$TMP_REPO/.bare-memory.git" .
    git checkout -q live
    echo "concurrent" > CONCURRENT.md
    git add CONCURRENT.md
    git -c user.email=t@t -c user.name=t commit -q -m "Concurrent remote commit"
    git push -q origin live
  )
  run_stub_synth memory || true
  statefile=$(git -C memory rev-parse --git-path gitlore-merge-state)
  [ -f "$statefile" ]
  [ "$(jq -r .flavor "$statefile")" = "local-vs-remote" ]
}
