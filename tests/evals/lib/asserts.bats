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
  [ "$status" -eq 0 ]
}

@test "add-tier: fails when the intent file was never consumed" {
  _make_add_tier_end_state
  printf 'mode=mount\n' > "$EVAL_REPO/.claude/gitlore-add-tier"
  _run_assert add-tier
  [ "$status" -ne 0 ]
  [[ "$output" =~ "never consumed it" ]]
}

@test "add-tier: fails when the tier is mounted but not activated" {
  _make_add_tier_end_state
  : > "$EVAL_REPO/memory/.gitlore-tiers"
  _run_assert add-tier
  [ "$status" -ne 0 ]
  [[ "$output" =~ "mounted but inactive" ]]
}

@test "add-tier: fails when activation did not recompose the root index" {
  _make_add_tier_end_state
  printf '# Memory Index\n' > "$EVAL_REPO/memory/MEMORY.md"
  _run_assert add-tier
  [ "$status" -ne 0 ]
  [[ "$output" =~ "composition did not run" ]]
}

@test "add-tier: fails when the tier is left on a branch instead of detached at live" {
  _make_add_tier_end_state
  git -C "$EVAL_REPO/memory/acme" checkout -q -B main
  _run_assert add-tier
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not detached at live" ]]
}

# The FR11 gate is the sole committer. A tier flow that commits inside memory
# would slip a change past the approval gate entirely.
@test "add-tier: fails when something committed inside the memory store" {
  _make_add_tier_end_state
  GITLORE_MEMORY_COMMIT=1 git -C "$EVAL_REPO/memory" commit -q -m "snuck in"
  _run_assert add-tier
  [ "$status" -ne 0 ]
  [[ "$output" =~ "bypassing the FR11 gate" ]]
}

@test "add-tier: fails when the tier was never mounted at all" {
  _make_memory
  printf 'acme\n' > "$EVAL_REPO/memory/.gitlore-tiers"
  _run_assert add-tier
  [ "$status" -ne 0 ]
  [[ "$output" =~ "not checked out" ]]
}

# --------------------------------------------------------------------- recall

_make_recall_end_state() {
  _make_memory
  ( cd "$EVAL_REPO" && bash "$SETUPS/recall-corpus.sh" ) >/dev/null

  printf 'sid-recall-1\n' > "$EVAL_OUT_DIR/session-id"
  printf 'Run svc-unlock --force --token ORBITAL-PANGOLIN-4471\n' > "$EVAL_OUT_DIR/turn1.txt"

  local ledger hash
  ledger=$(git -C "$EVAL_REPO/memory" rev-parse --git-path "gitlore-recall-sid-recall-1")
  hash=$(git -C "$EVAL_REPO/memory" hash-object -- reference_deploy_lock.md)
  printf '%s %s\n' "$hash" "reference_deploy_lock.md" > "$ledger"
  LEDGER="$ledger"

  cat > "$EVAL_OUT_DIR/transcript.jsonl" <<EOF
{"message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"$EVAL_REPO/.claude/gitlore-recall"}}]}}
{"message":{"content":[{"type":"text","text":"answering"}]}}
EOF
}

@test "recall: passes when the body was injected and used" {
  _make_recall_end_state
  _run_assert recall
  [ "$status" -eq 0 ]
}

@test "recall: fails when the request file was never consumed" {
  _make_recall_end_state
  printf 'reference_deploy_lock.md\n' > "$EVAL_REPO/.claude/gitlore-recall"
  _run_assert recall
  [ "$status" -ne 0 ]
  [[ "$output" =~ "never consumed it" ]]
}

@test "recall: fails when the canary never reached the answer" {
  _make_recall_end_state
  printf 'Just delete the lock file.\n' > "$EVAL_OUT_DIR/turn1.txt"
  _run_assert recall
  [ "$status" -ne 0 ]
  [[ "$output" =~ "does not carry the canary" ]]
}

# The hole this closes: reading the file directly leaves an identical repo, an
# identical ledger record and an identical answer. Only the tool calls differ.
@test "recall: fails when the agent Read the body instead of requesting it" {
  _make_recall_end_state
  cat > "$EVAL_OUT_DIR/transcript.jsonl" <<EOF
{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"$EVAL_REPO/memory/reference_deploy_lock.md"}}]}}
EOF
  _run_assert recall
  [ "$status" -ne 0 ]
  [[ "$output" == *"never wrote .claude/gitlore-recall"* ]]
}

@test "recall: fails when the agent both requested and Read the body" {
  _make_recall_end_state
  cat >> "$EVAL_OUT_DIR/transcript.jsonl" <<EOF
{"message":{"content":[{"type":"tool_use","name":"Read","input":{"file_path":"$EVAL_REPO/memory/reference_deploy_lock.md"}}]}}
EOF
  _run_assert recall
  [ "$status" -ne 0 ]
  [[ "$output" == *"Read reference_deploy_lock.md itself"* ]]
}

@test "recall: fails when the ledger recorded nothing" {
  _make_recall_end_state
  : > "$LEDGER"
  _run_assert recall
  [ "$status" -ne 0 ]
  [[ "$output" =~ "does not record" ]]
}

@test "recall: fails when no transcript was captured" {
  _make_recall_end_state
  rm -f "$EVAL_OUT_DIR/transcript.jsonl"
  _run_assert recall
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no session transcript" ]]
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
  [ "$status" -ne 0 ]
  [[ "$output" == *"was not routed to acme/"* ]]
  # The report must name where it went, or the reader has to go dig.
  [[ "$output" == *"reference_sentry_dsn.md"* ]]
}

@test "tier-write: fails when the tier is not mounted" {
  _make_memory
  _run_assert tier-write
  [ "$status" -ne 0 ]
  [[ "$output" =~ "fixture did not hold" ]]
}

# ------------------------------------------------------------- memory-commit

# The extraction out of run-evals.sh must not have changed what this grades.
@test "memory-commit: fails when the agent wrote no approved summary" {
  _make_memory
  _run_assert memory-commit
  [ "$status" -ne 0 ]
  [[ "$output" =~ "no commit-msg file" ]]
}

@test "memory-commit: on the precommit_failure path, a leftover commit-msg fails" {
  _make_memory
  export EVAL_TRIGGER=precommit_failure
  printf 'summary\n' > "$EVAL_REPO/.claude/gitlore-memory-message"
  _run_assert memory-commit
  [ "$status" -ne 0 ]
  [[ "$output" =~ "did not retry the commit" ]]
}
