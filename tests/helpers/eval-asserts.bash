#!/usr/bin/env bash
# Shared fixtures for the eval-assertion suites (tests/evals/lib/asserts*.bats):
# the per-test environment, the memory-submodule parent repo and the mounted-tier
# end state that the add-tier and tier-write suites both start from. Sourced by
# each suite; `setup` here is what bats runs for every test in them.

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
  export EVAL_RUBRIC="" LIB_DIR="$BATS_TEST_DIRNAME"
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
  git -C "$EVAL_REPO/memory" add -A
  git -C "$EVAL_REPO/memory" commit -q -m "index"
  git -C "$EVAL_REPO/memory" branch -f live HEAD
  git -C "$EVAL_REPO/memory" rev-parse HEAD > "$EVAL_OUT_DIR/memory-baseline"
}

# The end state /gitlore:add-tier is supposed to reach, built with the production
# scripts: the real mount, the real compose. A hand-rolled imitation would drift
# from what the flow actually produces, and then this suite would be testing the
# imitation.
#
# The baseline is taken before the mount, where the graded flow starts; the
# script mounts, activates, composes and commits on the clean store itself.
_make_add_tier_end_state() {
  _make_memory
  ( cd "$EVAL_REPO" && bash "$SETUPS/tier-remote.sh" ) >/dev/null

  ( cd "$EVAL_REPO" && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" bash "$PLUGIN_ROOT/scripts/add-tier.sh" ) >/dev/null <<EOF
mode=mount
name=acme
url=$EVAL_REPO/.tier-remote.git
EOF
}

# Session-transcript fixtures for the commit assertions: one jsonl line per
# tool_use, in the shape the recall suite uses.
_SKILL_COMMIT='{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"gitlore:commit"}}]}}'
_SKILL_COMMIT_PROJECT='{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"commit"}}]}}'
_SKILL_WRITING='{"message":{"content":[{"type":"tool_use","name":"Skill","input":{"skill":"gitlore:memory-writing"}}]}}'
_BASH_COMMIT='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"gitlore-commit <<'"'"'EOF'"'"'\n== memory ==\nmemory: note\nEOF"}}]}}'
_BASH_PROBE='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"command -v gitlore-commit"}}]}}'
_BASH_RAW='{"message":{"content":[{"type":"tool_use","name":"Bash","input":{"command":"git -C memory commit -am note"}}]}}'

# _write_commit_transcript <line>... : the transcript, one line per argument in
# order; an empty argument is skipped.
_write_commit_transcript() {
  : > "$EVAL_OUT_DIR/transcript.jsonl"
  local line
  for line in "$@"; do
    [ -z "$line" ] || printf '%s\n' "$line" >> "$EVAL_OUT_DIR/transcript.jsonl"
  done
}

# The agent-side finish: the agent piped the approved summary to `gitlore-commit`,
# so memory committed before the assertion ran. Calling the same entry point here
# reproduces the end state rather than imitating it.
_commit_approved() {
  # A caller's CLAUDE_PROJECT_DIR would send the commit to its own project.
  ( cd "$EVAL_REPO" && unset CLAUDE_PROJECT_DIR && CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT" \
    "$PLUGIN_ROOT/bin/gitlore-commit" <<<"$SUMMARY" ) >/dev/null
  _write_commit_transcript "$_SKILL_COMMIT" "$_BASH_COMMIT"
}

# A dirty memory store plus the approved summary: the state the agent leaves when
# the user approved and the agent stopped before committing.
_make_dirty_approved_memory() {
  _make_memory
  printf -- '- [eval suite](project_evals.md) — we are building an eval suite\n' \
    >> "$EVAL_REPO/memory/MEMORY.md"
  SUMMARY='== memory ==
memory: note that we are building an eval suite'
  _stub_judge
}

# The judge is the last assertion and it shells out to `claude`. Stub it, or
# every test here would spend a real API call to grade a fixture.
_stub_judge() {
  MOCK_BIN="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$MOCK_BIN"
  printf '#!/usr/bin/env bash\nprintf "pass fixture\\n"\n' > "$MOCK_BIN/claude"
  chmod +x "$MOCK_BIN/claude"
  PATH="$MOCK_BIN:$PATH"
  export PATH
}

# The state the agent leaves behind once the user has approved: the fact in the
# tier, the prefixed pointer in the root index, composition run, and the
# approved summary in $SUMMARY. Nothing is committed yet; the tests below commit
# it with _commit_approved or leave memory unmoved.
FACT=reference_sentry_dsn.md

_make_tier_write_end_state() {
  _make_add_tier_end_state
  # This flow starts after the mount.
  git -C "$EVAL_REPO/memory" rev-parse HEAD > "$EVAL_OUT_DIR/memory-baseline"

  printf -- '---\nname: reference-sentry-dsn\ndescription: one shared DSN across acme services\n---\n\nEvery acme service shares one Sentry DSN; rotating it takes a coordinated deploy.\n' \
    > "$EVAL_REPO/memory/acme/$FACT"
  printf -- '- [shared sentry dsn](acme/%s) — rotating it needs a coordinated deploy\n' "$FACT" \
    >> "$EVAL_REPO/memory/MEMORY.md"
  # shellcheck disable=SC1091  # dynamic plugin-root paths, resolved at runtime
  ( cd "$EVAL_REPO" \
    && source "$PLUGIN_ROOT/scripts/lib/util.sh" \
    && source "$PLUGIN_ROOT/scripts/lib/index-compose.sh" \
    && gitlore_compose memory ) >/dev/null

  SUMMARY='== acme ==
memory: record the shared acme Sentry DSN and its rotation cost
== memory ==
memory: record the shared acme Sentry DSN and its rotation cost'

  _stub_judge
}
