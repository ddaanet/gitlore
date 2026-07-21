#!/usr/bin/env bats
# The parent commit must record the memory pointer that its own pre-commit hook
# just created.
#
# The hook commits memory and advances `live`, but the parent's index was read
# before the hook ran, so without staging the gitlink the parent records the
# PRE-hook memory SHA — every commit lags one memory commit behind, and a fresh
# clone at any commit restores stale memory. A follow-up "pin the pointer"
# commit was the manual workaround.
#
# Driven through a real `git commit`, not by invoking the hook directly: the
# staging only works if git picks the change up from the index it is about to
# write, so the invocation IS the behaviour under test. All three commit modes
# are covered because they hand the hook a DIFFERENT index — `.git/index` for a
# plain commit, `.git/index.lock` under `-a`, and a `.git/next-index-*.lock`
# temp index for a pathspec commit. A hook that ignores GIT_INDEX_FILE and runs
# a bare `git add` dies on "Unable to create '.git/index.lock': File exists"
# for the latter two, which under `set -e` blocks the commit outright.

load helpers/setup
load helpers/gh-mock

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export CLAUDECODE=1
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory "echo precommit"
  bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"
}
teardown() { teardown_tmp_repo; }

# Dirty memory plus an approved summary, so the hook will commit it.
arm_memory_commit() {
  echo "fact from this session" >> memory/MEMORY.md
  printf 'memory: record a fact\n' > "$(gitlore_commit_msg_file memory)"
}

# The parent's recorded gitlink must equal memory's post-hook HEAD.
assert_pointer_pinned() {
  local recorded memory_head
  recorded=$(git rev-parse HEAD:memory)
  memory_head=$(git -C memory rev-parse HEAD)
  [ "$recorded" = "$memory_head" ] || {
    echo "parent recorded $recorded but memory HEAD is $memory_head" >&2
    return 1
  }
}

@test "a plain commit records the memory pointer the hook created" {
  arm_memory_commit
  echo change > tracked.txt
  git add tracked.txt
  git commit -q -m "parent change"
  assert_pointer_pinned
}

@test "'commit -a' records the memory pointer the hook created" {
  echo seed > tracked.txt
  git add tracked.txt
  git commit -q -m "seed tracked file"
  arm_memory_commit
  echo change > tracked.txt
  git commit -q -a -m "parent change"
  assert_pointer_pinned
}

@test "a pathspec commit records the memory pointer the hook created" {
  echo seed > tracked.txt
  git add tracked.txt
  git commit -q -m "seed tracked file"
  arm_memory_commit
  echo change > tracked.txt
  git add tracked.txt
  git commit -q -m "parent change" -- tracked.txt
  assert_pointer_pinned
}

@test "a commit with nothing but memory to record still pins the pointer" {
  # No other staged change: the gitlink the hook stages is the whole commit.
  arm_memory_commit
  git commit -q -m "record memory only"
  assert_pointer_pinned
}
