#!/usr/bin/env bats
# FR7: after `git clone`, the first SessionStart restores working state
# automatically — no second `/gitlore:install`. Exercises the fresh-clone
# branch of session-start.sh (`git submodule update --init`), which the
# happy-path integration test never reaches (it starts post-install with the
# submodule already populated).
#
# Faithfulness: the origin is built by the real install flow (init-submodule +
# create-remote against a gh-mock + local bare), so the memory remote carries
# `live` as its only/default branch — exactly the layout `create-remote.sh`
# produces (`push -u origin live`). A real clone's `submodule update --init`
# therefore yields a local `live`, which SessionStart's `checkout -b <branch>
# live` and `merge --ff-only live` depend on.

load helpers/setup
load helpers/gh-mock

# Local file:// submodule fetches need protocol.file.allow; inject it for every
# git invocation in this process, including session-start.sh's child gits.
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=protocol.file.allow
export GIT_CONFIG_VALUE_0=always

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  export CLAUDECODE=1
  install_gh_mock
  export GH_MOCK_STDOUT_API_USER="alice"
  export GH_MOCK_REMOTE_URL="$TMP_REPO/.fake-gh-remote.git"
  git init -q --bare "$GH_MOCK_REMOTE_URL"

  # Build the "origin" by running the real install, then commit the staged
  # artifacts so a clone receives the full committed wiring (.gitmodules,
  # gitlink, settings, sentinel).
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory "echo precommit"
  git commit -q -m "Install gitlore"
}

teardown() { teardown_tmp_repo; }

@test "fresh clone + SessionStart restores memory working tree without re-install" {
  ORIGIN="$TMP_REPO"

  # Clone WITHOUT --recurse-submodules: the true post-clone state where the
  # submodule is registered in .gitmodules but not yet checked out.
  CLONE="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-clone.XXXXXX")"
  git clone -q "$ORIGIN" "$CLONE"
  cd "$CLONE"
  git config user.email "test@example.com"
  git config user.name  "Test"

  # Precondition: memory tree absent in the fresh clone.
  [ ! -e "$CLONE/memory/.git" ]

  # First SessionStart in the clone — the only thing we run. No /gitlore:install.
  export CLAUDE_PROJECT_DIR="$CLONE"
  run bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"
  [ "$status" -eq 0 ]

  # Working state restored: submodule populated and content present.
  [ -e "$CLONE/memory/.git" ]
  [ -f "$CLONE/memory/MEMORY.md" ]

  # Memory checked out on a branch matching the parent (main), forked from live,
  # and fast-forwarded clean (live is an ancestor of HEAD).
  run git -C "$CLONE/memory" symbolic-ref --short HEAD
  [ "$status" -eq 0 ]
  [ "$output" = "main" ]
  [ "$(git -C "$CLONE/memory" rev-parse main)" = "$(git -C "$CLONE/memory" rev-parse live)" ]

  rm -rf "$CLONE"
}
