#!/usr/bin/env bats
# The tier-write and memory-commit assertion scripts against end states built by
# hand: the fact routed into the mounted tier, the approved summary, and
# whether the agent committed it. The add-tier and recall assertions are in asserts.bats; both
# suites share tests/helpers/eval-asserts.bash.
#
# An assertion that always passes turns a scenario into an expensive no-op, and
# one that always fails blocks a release for nothing. Neither shows up when the
# eval runs — a green scenario looks the same either way — so each assertion is
# exercised here against a good end state and against the specific breakage it
# exists to catch.

# bats runs each @test in a subshell; with `setup` in the shared helper,
# the linter reports the test-local `run` results as lost modifications.
# shellcheck disable=SC2030,SC2031
# shellcheck source=tests/helpers/eval-asserts.bash
source "$BATS_TEST_DIRNAME/../../helpers/eval-asserts.bash"

# ----------------------------------------------------------------- tier-write

@test "tier-write: fails when the fact went to project memory instead of the tier" {
  _make_memory
  ( cd "$EVAL_REPO" && bash "$SETUPS/tier-remote.sh" ) >/dev/null
  cat > "$EVAL_REPO/.claude/gitlore-add-tier" <<EOF
mode=mount
name=acme
url=$EVAL_REPO/.tier-remote.git
EOF
  ( cd "$EVAL_REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/add-tier.sh" ) >/dev/null
  rm -f "$EVAL_REPO/.claude/gitlore-add-tier"

  printf -- '---\nname: x\n---\n\nbody\n' > "$EVAL_REPO/memory/reference_sentry_dsn.md"
  _run_assert tier-write
  # The report must name where it went, or the reader has to go dig.
  assert_fails "was not routed to acme/" "reference_sentry_dsn.md"
}

@test "tier-write: fails when the tier is not mounted" {
  _make_memory
  _run_assert tier-write
  assert_fails "fixture did not hold"
}

@test "tier-write: fails when the memory pointer is not staged in the parent" {
  _make_tier_write_end_state
  _commit_approved
  git -C "$EVAL_REPO" reset -q -- memory
  _run_assert tier-write
  assert_fails "does not have 'memory' staged"
}

# The agent may also commit the pointer in the parent itself; the gitlink is
# then recorded at HEAD and the index is clean.
@test "tier-write: passes when the agent also committed the pointer in the parent" {
  _make_tier_write_end_state
  _commit_approved
  git -C "$EVAL_REPO" commit -q -m "record memory pointer"
  [ -z "$(git -C "$EVAL_REPO" diff --cached --name-only)" ]   # nothing left staged
  [ "$(git -C "$EVAL_REPO" rev-parse HEAD:memory)" = "$(git -C "$EVAL_REPO/memory" rev-parse HEAD)" ]
  _run_assert tier-write
  assert_ok
}

# memory-after-turn1 is where the runner saw memory between the turns; a store
# that already moved then was committed before the user approved anything.
@test "tier-write: fails when memory was committed before approval" {
  _make_tier_write_end_state
  git -C "$EVAL_REPO/memory" rev-parse HEAD~1 > "$EVAL_OUT_DIR/memory-after-turn1"
  [ -s "$EVAL_OUT_DIR/memory-after-turn1" ]   # a real sha of the fixture's memory repo...
  [ "$(cat "$EVAL_OUT_DIR/memory-after-turn1")" != "$(cat "$EVAL_OUT_DIR/memory-baseline")" ]   # ...that is not the baseline
  _run_assert tier-write
  assert_fails "before approval"
}

@test "tier-write: passes when memory had not moved by the end of turn 1" {
  _make_tier_write_end_state
  _commit_approved
  cp "$EVAL_OUT_DIR/memory-baseline" "$EVAL_OUT_DIR/memory-after-turn1"
  _run_assert tier-write
  assert_ok
}

# An empty snapshot is a runner that had nothing to record, not a memory that
# moved: it is read as absent.
@test "tier-write: an empty memory-after-turn1 is ignored" {
  _make_tier_write_end_state
  _commit_approved
  : > "$EVAL_OUT_DIR/memory-after-turn1"
  _run_assert tier-write
  assert_ok
}

# The parent recorded memory's previous commit; memory then moved again, so the
# recorded gitlink is stale and the user's next parent commit would move it.
@test "tier-write: fails when memory moved again after the parent recorded the pointer" {
  _make_tier_write_end_state
  _commit_approved
  git -C "$EVAL_REPO" commit -q -m "record memory pointer"
  git -C "$EVAL_REPO/memory" commit -q --allow-empty -m "later"
  git -C "$EVAL_REPO/memory" branch -f live HEAD
  [ "$(git -C "$EVAL_REPO" rev-parse HEAD:memory)" != "$(git -C "$EVAL_REPO/memory" rev-parse HEAD)" ]
  _run_assert tier-write
  assert_fails "does not have 'memory' staged"
}

# Staging the path is not enough: the gitlink must be memory's current HEAD.
@test "tier-write: fails when the index records memory at a stale sha" {
  _make_tier_write_end_state
  _commit_approved
  git -C "$EVAL_REPO" update-index --cacheinfo "160000,$(cat "$EVAL_OUT_DIR/memory-baseline"),memory"
  # Memory is staged (so the path-name check is satisfied) but at the old sha,
  # and the parent's HEAD does not record the current one either.
  git -C "$EVAL_REPO" diff --cached --name-only | grep -qxF memory
  [ "$(git -C "$EVAL_REPO" rev-parse HEAD:memory)" != "$(git -C "$EVAL_REPO/memory" rev-parse HEAD)" ]
  _run_assert tier-write
  assert_fails "does not have 'memory' staged"
}

@test "tier-write: fails when only an unrelated path is staged" {
  _make_tier_write_end_state
  _commit_approved
  git -C "$EVAL_REPO" reset -q -- memory
  printf 'x\n' > "$EVAL_REPO/unrelated.txt"
  git -C "$EVAL_REPO" add unrelated.txt
  git -C "$EVAL_REPO" diff --cached --name-only | grep -qxF unrelated.txt
  _run_assert tier-write
  assert_fails "does not have 'memory' staged"
}

@test "tier-write: fails when the agent never committed and memory never moved" {
  _make_tier_write_end_state
  _run_assert tier-write
  assert_fails "memory never moved"
}

@test "tier-write: fails on the one-behind gitlink lag" {
  _make_tier_write_end_state
  _commit_approved
  # The tier moves after memory recorded it — exactly what committing memory
  # before the tier would leave behind, and invisible in both working trees.
  git -C "$EVAL_REPO/memory/acme" \
    commit -q --allow-empty -m "later"
  git -C "$EVAL_REPO/memory/acme" branch -f live HEAD
  _run_assert tier-write
  assert_fails "stale gitlink"
}

@test "tier-write: fails when the commit message misses the rubric" {
  _make_tier_write_end_state
  _commit_approved
  printf '#!/usr/bin/env bash\nprintf "fail says nothing about Sentry\\n"\n' > "$MOCK_BIN/claude"
  _run_assert tier-write
  assert_fails "failed judge rubric"
}

# ------------------------------------------------------------- memory-commit

# The extraction out of run-evals.sh must not have changed what this grades.
@test "memory-commit: fails when the agent never committed" {
  _make_memory
  _run_assert memory-commit
  assert_fails "memory never moved"
}

@test "memory-commit: passes when the agent committed memory itself" {
  _make_dirty_approved_memory
  _commit_approved
  _run_assert memory-commit
  assert_ok
}

@test "memory-commit: fails when the memory pointer is not staged in the parent" {
  _make_dirty_approved_memory
  _commit_approved
  git -C "$EVAL_REPO" reset -q -- memory
  _run_assert memory-commit
  assert_fails "does not have 'memory' staged"
}

# The agent may also commit the pointer in the parent itself; the gitlink is
# then recorded at HEAD and the index is clean.
@test "memory-commit: passes when the agent also committed the pointer in the parent" {
  _make_dirty_approved_memory
  _commit_approved
  git -C "$EVAL_REPO" commit -q -m "record memory pointer"
  [ -z "$(git -C "$EVAL_REPO" diff --cached --name-only)" ]   # nothing left staged
  [ "$(git -C "$EVAL_REPO" rev-parse HEAD:memory)" = "$(git -C "$EVAL_REPO/memory" rev-parse HEAD)" ]
  _run_assert memory-commit
  assert_ok
}

# memory-after-turn1 is where the runner saw memory between the turns; a store
# that already moved then was committed before the user approved anything.
@test "memory-commit: fails when memory was committed before approval" {
  _make_dirty_approved_memory
  git -C "$EVAL_REPO/memory" rev-parse HEAD~1 > "$EVAL_OUT_DIR/memory-after-turn1"
  [ -s "$EVAL_OUT_DIR/memory-after-turn1" ]   # a real sha of the fixture's memory repo...
  [ "$(cat "$EVAL_OUT_DIR/memory-after-turn1")" != "$(cat "$EVAL_OUT_DIR/memory-baseline")" ]   # ...that is not the baseline
  _run_assert memory-commit
  assert_fails "before approval"
}

@test "memory-commit: passes when memory had not moved by the end of turn 1" {
  _make_dirty_approved_memory
  _commit_approved
  cp "$EVAL_OUT_DIR/memory-baseline" "$EVAL_OUT_DIR/memory-after-turn1"
  _run_assert memory-commit
  assert_ok
}

# An empty snapshot is a runner that had nothing to record, not a memory that
# moved: it is read as absent.
@test "memory-commit: an empty memory-after-turn1 is ignored" {
  _make_dirty_approved_memory
  _commit_approved
  : > "$EVAL_OUT_DIR/memory-after-turn1"
  _run_assert memory-commit
  assert_ok
}

# The parent recorded memory's previous commit; memory then moved again, so the
# recorded gitlink is stale and the user's next parent commit would move it.
@test "memory-commit: fails when memory moved again after the parent recorded the pointer" {
  _make_dirty_approved_memory
  _commit_approved
  git -C "$EVAL_REPO" commit -q -m "record memory pointer"
  git -C "$EVAL_REPO/memory" commit -q --allow-empty -m "later"
  git -C "$EVAL_REPO/memory" branch -f live HEAD
  [ "$(git -C "$EVAL_REPO" rev-parse HEAD:memory)" != "$(git -C "$EVAL_REPO/memory" rev-parse HEAD)" ]
  _run_assert memory-commit
  assert_fails "does not have 'memory' staged"
}

# Staging the path is not enough: the gitlink must be memory's current HEAD.
@test "memory-commit: fails when the index records memory at a stale sha" {
  _make_dirty_approved_memory
  _commit_approved
  git -C "$EVAL_REPO" update-index --cacheinfo "160000,$(cat "$EVAL_OUT_DIR/memory-baseline"),memory"
  # Memory is staged (so the path-name check is satisfied) but at the old sha,
  # and the parent's HEAD does not record the current one either.
  git -C "$EVAL_REPO" diff --cached --name-only | grep -qxF memory
  [ "$(git -C "$EVAL_REPO" rev-parse HEAD:memory)" != "$(git -C "$EVAL_REPO/memory" rev-parse HEAD)" ]
  _run_assert memory-commit
  assert_fails "does not have 'memory' staged"
}

@test "memory-commit: fails when only an unrelated path is staged" {
  _make_dirty_approved_memory
  _commit_approved
  git -C "$EVAL_REPO" reset -q -- memory
  printf 'x\n' > "$EVAL_REPO/unrelated.txt"
  git -C "$EVAL_REPO" add unrelated.txt
  git -C "$EVAL_REPO" diff --cached --name-only | grep -qxF unrelated.txt
  _run_assert memory-commit
  assert_fails "does not have 'memory' staged"
}

@test "memory-commit: fails when the commit message misses the rubric" {
  _make_dirty_approved_memory
  _commit_approved
  printf '#!/usr/bin/env bash\nprintf "fail generic message\\n"\n' > "$MOCK_BIN/claude"
  _run_assert memory-commit
  assert_fails "failed judge rubric"
}
