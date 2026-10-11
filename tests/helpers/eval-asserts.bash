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
  GITLORE_MEMORY_COMMIT=1 git -C "$EVAL_REPO/memory" add -A
  GITLORE_MEMORY_COMMIT=1 git -C "$EVAL_REPO/memory" commit -q -m "index"
  git -C "$EVAL_REPO/memory" branch -f live HEAD
  git -C "$EVAL_REPO/memory" rev-parse HEAD > "$EVAL_OUT_DIR/memory-baseline"
}

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
