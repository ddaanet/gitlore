#!/usr/bin/env bats
# While a rebase, cherry-pick or revert is replaying, the parent pre-commit hook
# must leave memory alone entirely.
#
# The hook commits dirty memory and stages the resulting gitlink (see
# integration_gitlink_staging.bats). That is right for a commit being authored
# now and wrong for one being replayed: the memory worktree does not move when
# the parent's HEAD does, so a replayed commit would be re-pinned to memory's
# CURRENT SHA instead of the one it originally recorded, and today's memory
# content would be attributed to a historical commit.
#
# The guard covers the whole sync, not just the staging. A replay that trips the
# FR11 approval gate exits non-zero from pre-commit, which does not abort a
# commit — it aborts the REBASE, mid-sequence, leaving a half-replayed history
# to clean up by hand.
#
# MERGE_HEAD is deliberately NOT a replay marker: a merge commit is authored now
# and must pin current memory. Same for a plain `--amend` on the tip.
#
# Driven through real git commands, not by invoking the hook directly: whether
# the replay state directory exists at hook time is the behaviour under test.
#
# The rebase cases commit by hand at the conflict/edit stop rather than through
# `git rebase --continue`, because `--continue` does not run pre-commit at all
# (probed, git 2.47.3) — a `--continue`-driven test would pass without a guard
# and assert nothing. Committing by hand at the stop is both the path that does
# reach the hook and the one that motivated the guard.

load helpers/setup
load helpers/gh-mock

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export CLAUDECODE=1
  export GIT_EDITOR=true
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory "echo precommit"
  bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"
}
teardown() { teardown_tmp_repo; }

# Dirty memory plus an approved summary, so the hook WOULD commit it.
arm_memory_commit() {
  echo "fact from this session" >> memory/MEMORY.md
  printf 'memory: record a fact\n' > "$(gitlore_commit_msg_file memory)"
}

# Two branches whose tips conflict, so replaying one onto the other stops and
# hands the resolution commit to the pre-commit hook.
setup_conflicting_history() {
  echo base > f.txt
  git add f.txt
  git commit -q -m "base"
  git checkout -q -b topic
  echo topic > f.txt
  git commit -q -a -m "topic change"
  git checkout -q main
  echo main > f.txt
  git commit -q -a -m "main change"
}

resolve_conflict() {
  echo resolved > f.txt
  git add f.txt
}

# Stop an interactive rebase on the given commit, so the test can commit or
# amend by hand while `.git/rebase-merge` exists. `rebase -i` replays what
# comes AFTER its argument, so edit the target by rebasing from its parent.
stop_rebase_editing() {
  cat > "$TMP_REPO/seq-editor.sh" <<'EOF'
#!/usr/bin/env bash
todo="$1"
sed '1s/^pick/edit/' "$todo" > "$todo.new"
mv "$todo.new" "$todo"
EOF
  chmod +x "$TMP_REPO/seq-editor.sh"
  GIT_SEQUENCE_EDITOR="$TMP_REPO/seq-editor.sh" git rebase -q -i "$1^"
}

@test "a commit made while a rebase is stopped leaves memory alone" {
  setup_conflicting_history
  git checkout -q topic
  recorded_before=$(git rev-parse HEAD:memory)
  memory_before=$(git -C memory rev-parse HEAD)

  run git rebase main
  arm_memory_commit
  resolve_conflict
  git commit -q -m "replayed topic change"

  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git rev-parse HEAD:memory)" = "$recorded_before" ]
}

@test "an --amend while a rebase is stopped does not re-pin the gitlink" {
  # The headline hazard: the edited commit recorded an OLDER memory SHA, and
  # the memory worktree does not move when the parent's HEAD does. Amending
  # must preserve what the commit recorded, not stamp memory's current SHA.
  # A root commit first, so the commit being edited has a parent to rebase from.
  echo seed > tracked.txt
  git add tracked.txt
  git commit -q -m "root"
  echo first >> tracked.txt
  git commit -q -a -m "first"
  target=$(git rev-parse HEAD)
  recorded_before=$(git rev-parse HEAD:memory)

  # Move memory on a later commit, so current memory differs from what the
  # commit being edited recorded.
  arm_memory_commit
  echo more >> tracked.txt
  git commit -q -a -m "second"
  memory_now=$(git -C memory rev-parse HEAD)
  [ "$memory_now" != "$recorded_before" ]

  stop_rebase_editing "$target"
  arm_memory_commit
  git commit -q --amend --no-edit

  [ "$(git rev-parse HEAD:memory)" = "$recorded_before" ]
  [ "$(git -C memory rev-parse HEAD)" = "$memory_now" ]
}

@test "a rebase in progress announces that the memory sync was skipped" {
  setup_conflicting_history
  git checkout -q topic
  run git rebase main
  arm_memory_commit
  resolve_conflict

  run git commit -m "replayed topic change"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitlore"* ]]
  [[ "$output" == *"rebase"* ]]
}

@test "a conflicted cherry-pick leaves memory uncommitted and the gitlink unmoved" {
  setup_conflicting_history
  recorded_before=$(git rev-parse HEAD:memory)
  memory_before=$(git -C memory rev-parse HEAD)

  run git cherry-pick topic
  arm_memory_commit
  resolve_conflict
  run git cherry-pick --continue
  [ "$status" -eq 0 ]

  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git rev-parse HEAD:memory)" = "$recorded_before" ]
}

@test "a conflicted revert leaves memory uncommitted and the gitlink unmoved" {
  setup_conflicting_history
  echo later > f.txt
  git commit -q -a -m "later change"
  recorded_before=$(git rev-parse HEAD:memory)
  memory_before=$(git -C memory rev-parse HEAD)

  run git revert HEAD~1
  arm_memory_commit
  resolve_conflict
  run git revert --continue
  [ "$status" -eq 0 ]

  [ "$(git -C memory rev-parse HEAD)" = "$memory_before" ]
  [ "$(git rev-parse HEAD:memory)" = "$recorded_before" ]
}

@test "a conflicted merge is authored now, so it still pins current memory" {
  # MERGE_HEAD is present but this is not a replay: the commit is new.
  setup_conflicting_history
  run git merge topic
  arm_memory_commit
  resolve_conflict

  git commit -q -m "merge topic"
  [ "$(git rev-parse HEAD:memory)" = "$(git -C memory rev-parse HEAD)" ]
}

@test "a plain --amend on the tip still pins current memory" {
  echo seed > tracked.txt
  git add tracked.txt
  git commit -q -m "seed"
  arm_memory_commit

  git commit -q --amend -m "seed, amended"
  [ "$(git rev-parse HEAD:memory)" = "$(git -C memory rev-parse HEAD)" ]
}
