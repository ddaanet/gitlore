#!/usr/bin/env bats
# The assertion scripts themselves, against end states built by hand.
#
# An assertion that always passes turns a scenario into an expensive no-op, and
# one that always fails blocks a release for nothing. Neither shows up when the
# eval runs — a green scenario looks the same either way — so each assertion is
# exercised here against a good end state and against the specific breakage it
# exists to catch.

# shellcheck disable=SC1091  # bats resolves the helper at runtime
source "$BATS_TEST_DIRNAME/../../helpers/fixtures.bash"
# shellcheck source=tests/helpers/run-asserts.bash
source "$BATS_TEST_DIRNAME/../../helpers/run-asserts.bash"

ASSERTS="$BATS_TEST_DIRNAME/../asserts"
SETUPS="$BATS_TEST_DIRNAME/../setups"
PLUGIN_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

setup() {
  EVAL_REPO="$BATS_TEST_TMPDIR/repo"
  EVAL_OUT_DIR="$BATS_TEST_TMPDIR/out"
  mkdir -p "$EVAL_REPO/.claude" "$EVAL_OUT_DIR"
  export EVAL_REPO EVAL_OUT_DIR PLUGIN_ROOT
  export EVAL_RUBRIC="" EVAL_TRIGGER="ptu" LIB_DIR="$BATS_TEST_DIRNAME"
  # Local bare remotes are the only kind an eval can reach; `submodule add`
  # refuses the file transport without this, and repo config does not reach the
  # clone that performs it.
  export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always
}

_run_assert() { run bash "$ASSERTS/$1.sh"; }

# A parent repo with memory mounted as the gitlore-memory submodule, detached at
# live. The real registration matters: gitlore_has_submodule reads the parent's
# .gitmodules, and a plain nested git repo would make every production script
# under test bail with "this repo has no gitlore memory submodule".
_make_memory() {
  TMP_REPO="$EVAL_REPO"
  export TMP_REPO
  git init -q -b main "$EVAL_REPO"
  git -C "$EVAL_REPO" config user.email e@x.com
  git -C "$EVAL_REPO" config user.name E
  ( cd "$EVAL_REPO" && make_parent_with_memory )
  printf '# Memory Index\n' > "$EVAL_REPO/memory/MEMORY.md"
  GITLORE_MEMORY_COMMIT=1 git -C "$EVAL_REPO/memory" add -A
  GITLORE_MEMORY_COMMIT=1 git -C "$EVAL_REPO/memory" commit -q -m "index"
  git -C "$EVAL_REPO/memory" branch -f live HEAD
  git -C "$EVAL_REPO/memory" rev-parse HEAD > "$EVAL_OUT_DIR/memory-baseline"
}

# ------------------------------------------------------------------- add-tier

# The end state /gitlore:add-tier is supposed to reach, built with the production
# scripts: the real mount, the real compose. A hand-rolled imitation would drift
# from what the flow actually produces, and then this suite would be testing the
# imitation.
_make_add_tier_end_state() {
  _make_memory
  ( cd "$EVAL_REPO" && bash "$SETUPS/tier-remote.sh" ) >/dev/null

  cat > "$EVAL_REPO/.claude/gitlore-add-tier" <<EOF
mode=mount
name=acme
url=$EVAL_REPO/.tier-remote.git
EOF
  ( cd "$EVAL_REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/add-tier.sh" ) >/dev/null
  rm -f "$EVAL_REPO/.claude/gitlore-add-tier"

  printf 'acme\n' > "$EVAL_REPO/memory/.gitlore-tiers"
  # shellcheck disable=SC1091  # dynamic plugin-root paths, resolved at runtime
  ( cd "$EVAL_REPO" \
    && source "$PLUGIN_ROOT/scripts/lib/util.sh" \
    && source "$PLUGIN_ROOT/scripts/lib/index-compose.sh" \
    && gitlore_compose memory ) >/dev/null
  # The baseline is taken before the flow; the mount must not have moved HEAD.
  git -C "$EVAL_REPO/memory" rev-parse HEAD > "$EVAL_OUT_DIR/memory-baseline"
}

@test "add-tier: passes on a mounted, activated, composed tier" {
  _make_add_tier_end_state
  _run_assert add-tier
  assert_ok
}

@test "add-tier: fails when the intent file was never consumed" {
  _make_add_tier_end_state
  printf 'mode=mount\n' > "$EVAL_REPO/.claude/gitlore-add-tier"
  _run_assert add-tier
  assert_fails "never consumed it"
}

@test "add-tier: fails when the tier is mounted but not activated" {
  _make_add_tier_end_state
  : > "$EVAL_REPO/memory/.gitlore-tiers"
  _run_assert add-tier
  assert_fails "mounted but inactive"
}

@test "add-tier: fails when activation did not recompose the root index" {
  _make_add_tier_end_state
  printf '# Memory Index\n' > "$EVAL_REPO/memory/MEMORY.md"
  _run_assert add-tier
  assert_fails "composition did not run"
}

@test "add-tier: fails when the tier is left on a branch instead of detached at live" {
  _make_add_tier_end_state
  git -C "$EVAL_REPO/memory/acme" checkout -q -B main
  _run_assert add-tier
  assert_fails "not detached at live"
}

# The FR11 gate is the sole committer. A tier flow that commits inside memory
# would slip a change past the approval gate entirely.
@test "add-tier: fails when something committed inside the memory store" {
  _make_add_tier_end_state
  GITLORE_MEMORY_COMMIT=1 git -C "$EVAL_REPO/memory" commit -q -m "snuck in"
  _run_assert add-tier
  assert_fails "bypassing the FR11 gate"
}

@test "add-tier: fails when the tier was never mounted at all" {
  _make_memory
  printf 'acme\n' > "$EVAL_REPO/memory/.gitlore-tiers"
  _run_assert add-tier
  assert_fails "not checked out"
}

# --------------------------------------------------------------------- recall

_PROBE_CALL='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"./nightly-retry.sh"}}]}}'
_SKILL_CALL='{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"gitlore:recall"}}]}}'

_read_call() {
  printf '{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"%s/memory/reference_deploy_lock.md"}}]}}\n' \
    "$EVAL_REPO"
}

_make_recall_end_state() {
  _make_memory
  ( cd "$EVAL_REPO" && bash "$SETUPS/recall-corpus.sh" ) >/dev/null

  printf 'sid-recall-1\n' > "$EVAL_OUT_DIR/session-id"
  printf 'Run svc-unlock --force --token ORBITAL-PANGOLIN-4471\n' > "$EVAL_OUT_DIR/turn1.txt"

  # The passing shape: probe, then the skill, then the body read.
  { printf '%s\n%s\n' "$_PROBE_CALL" "$_SKILL_CALL"; _read_call; } > "$EVAL_OUT_DIR/transcript.jsonl"
}

@test "recall: passes when the body was read after the mid-task trigger" {
  _make_recall_end_state
  _run_assert recall
  assert_ok
}

@test "recall: fails when the canary never reached the answer" {
  _make_recall_end_state
  printf 'Just delete the lock file.\n' > "$EVAL_OUT_DIR/turn1.txt"
  _run_assert recall
  assert_fails "does not carry the canary"
}

@test "recall: fails when the agent answered without reading the body" {
  _make_recall_end_state
  printf '%s\n%s\n' "$_PROBE_CALL" "$_SKILL_CALL" > "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "never Read reference_deploy_lock.md"
}

# Without this the scenario grades the model's common sense: an agent that opens
# the file on the user's say-so leaves the same answer and the same trace.
@test "recall: fails when the body was read without the skill being invoked" {
  _make_recall_end_state
  { printf '%s\n' "$_PROBE_CALL"; _read_call; } > "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "recall skill was never invoked"
}

# The hole this closes: prompt-time recall delivers the same body, leaves the
# same answer and the same repo. Only the ORDER tells them apart, and grading a
# prompt-time fetch as a pass would grade CC's harness instead of this skill.
@test "recall: fails when the body was read before the trigger surfaced" {
  _make_recall_end_state
  # Native recall's shape: the body is already in context when the probe runs,
  # so invoking the skill afterwards changes nothing it could have fetched.
  { _read_call; printf '%s\n%s\n' "$_PROBE_CALL" "$_SKILL_CALL"; } > "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "that is prompt-time recall"
}

@test "recall: fails when the agent never ran the probe" {
  _make_recall_end_state
  _read_call > "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "never ran nightly-retry.sh"
}

@test "recall: fails when no transcript was captured" {
  _make_recall_end_state
  rm -f "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  assert_fails "no session transcript"
}

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

# The state the agent leaves behind once the user has approved: the fact in the
# tier, the prefixed pointer in the root index, composition run, and the
# approved summary on disk. Nothing is committed yet — which of the two FR11
# finishes happens next is what the tests below vary.
FACT=reference_sentry_dsn.md

_make_tier_write_end_state() {
  _make_add_tier_end_state

  printf -- '---\nname: reference-sentry-dsn\ndescription: one shared DSN across acme services\n---\n\nEvery acme service shares one Sentry DSN; rotating it takes a coordinated deploy.\n' \
    > "$EVAL_REPO/memory/acme/$FACT"
  printf -- '- [shared sentry dsn](acme/%s) — rotating it needs a coordinated deploy\n' "$FACT" \
    >> "$EVAL_REPO/memory/MEMORY.md"
  # shellcheck disable=SC1091  # dynamic plugin-root paths, resolved at runtime
  ( cd "$EVAL_REPO" \
    && source "$PLUGIN_ROOT/scripts/lib/util.sh" \
    && source "$PLUGIN_ROOT/scripts/lib/index-compose.sh" \
    && gitlore_compose memory ) >/dev/null

  printf 'memory: record the shared acme Sentry DSN and its rotation cost\n' \
    > "$EVAL_REPO/.claude/gitlore-memory-message"

  # The stop path is finished by the parent's pre-commit hook, so the fixture
  # needs it wired — _make_memory builds the submodule but no hooks, and without
  # this the assertion's `git commit` is inert and every stop-path test fails
  # for a reason that has nothing to do with what it grades.
  ( cd "$EVAL_REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$PLUGIN_ROOT/scripts/emit-wrappers.sh" ) >/dev/null
  # The wrapper resolves the real hook through this config key and exits 0 with
  # a "hooks not installed" notice when it is unset — which is silent enough to
  # look like a passing commit that simply did nothing.
  git -C "$EVAL_REPO" config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  cat > "$EVAL_REPO/.git/hooks/pre-commit" <<'HOOK'
#!/usr/bin/env bash
exec "$(git rev-parse --git-common-dir)/gitlore-pre-commit" "$@"
HOOK
  chmod +x "$EVAL_REPO/.git/hooks/pre-commit"

  # The judge is the last assertion and it shells out to `claude`. Stub it, or
  # every test here would spend a real API call to grade a fixture.
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  printf '#!/usr/bin/env bash\nprintf "pass fixture\\n"\n' > "$MOCK_BIN/claude"
  chmod +x "$MOCK_BIN/claude"
  PATH="$MOCK_BIN:$PATH"
  export PATH
}

# The second FR11 finish: the agent wrote the trigger too, so the batch hook
# committed before the assertion ever ran. commit-memory.sh IS what that hook
# invokes, so calling it here reproduces the end state rather than imitating it.
_commit_via_batch_path() {
  ( cd "$EVAL_REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    bash "$PLUGIN_ROOT/scripts/commit-memory.sh" \
      -F "$EVAL_REPO/.claude/gitlore-memory-message" ) >/dev/null
}

@test "tier-write: passes when the agent stopped after writing the summary" {
  _make_tier_write_end_state
  _run_assert tier-write
  assert_ok
}

@test "tier-write: passes when the batch hook already committed (summary consumed)" {
  _make_tier_write_end_state
  _commit_via_batch_path
  [ ! -f "$EVAL_REPO/.claude/gitlore-memory-message" ]   # the flow consumed it
  _run_assert tier-write
  assert_ok
}

@test "tier-write: fails when the trigger is present but no summary was written" {
  _make_tier_write_end_state
  rm -f "$EVAL_REPO/.claude/gitlore-memory-message"
  : > "$EVAL_REPO/.claude/gitlore-commit-memory"
  _run_assert tier-write
  assert_fails "trigger IS present"
}

@test "tier-write: fails when neither summary nor trigger exists and memory never moved" {
  _make_tier_write_end_state
  rm -f "$EVAL_REPO/.claude/gitlore-memory-message"
  _run_assert tier-write
  assert_fails "did not write the approved summary"
}

@test "tier-write: fails on the one-behind gitlink lag" {
  _make_tier_write_end_state
  _commit_via_batch_path
  # The tier moves after memory recorded it — exactly what committing memory
  # before the tier would leave behind, and invisible in both working trees.
  GITLORE_MEMORY_COMMIT=1 git -C "$EVAL_REPO/memory/acme" \
    commit -q --allow-empty -m "later"
  git -C "$EVAL_REPO/memory/acme" branch -f live HEAD
  _run_assert tier-write
  assert_fails "stale gitlink"
}

@test "tier-write: fails when the commit message misses the rubric" {
  _make_tier_write_end_state
  printf '#!/usr/bin/env bash\nprintf "fail says nothing about Sentry\\n"\n' > "$MOCK_BIN/claude"
  _run_assert tier-write
  assert_fails "failed judge rubric"
}

# ------------------------------------------------------------- memory-commit

# The extraction out of run-evals.sh must not have changed what this grades.
@test "memory-commit: fails when the agent wrote no approved summary" {
  _make_memory
  _run_assert memory-commit
  assert_fails "no commit-msg file"
}

@test "memory-commit: on the precommit_failure path, a leftover commit-msg fails" {
  _make_memory
  export EVAL_TRIGGER=precommit_failure
  printf 'summary\n' > "$EVAL_REPO/.claude/gitlore-memory-message"
  _run_assert memory-commit
  assert_fails "did not retry the commit"
}
