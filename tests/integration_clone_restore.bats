#!/usr/bin/env bats
bats_require_minimum_version 1.5.0
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
  bash "$PLUGIN_ROOT/scripts/install/run.sh" memory
  git commit -q -m "Install gitlore"
}

teardown() {
  [ -n "${CLONE:-}" ] && rm -rf "$CLONE"
  teardown_tmp_repo
}

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
  CLAUDE_PROJECT_DIR="$CLONE" run bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"
  [ "$status" -eq 0 ]

  # Working state restored: submodule populated and content present.
  [ -e "$CLONE/memory/.git" ]
  [ -f "$CLONE/memory/MEMORY.md" ]

  # Memory checked out DETACHED at live (D17 branch model), not on a named branch.
  run git -C "$CLONE/memory" symbolic-ref -q HEAD
  [ "$status" -ne 0 ]
  [ "$(git -C "$CLONE/memory" rev-parse HEAD)" = "$(git -C "$CLONE/memory" rev-parse live)" ]

}

@test "fresh clone: live equals the recorded gitlink, and a newer origin/live is reported, not taken (D59)" {
  ORIGIN="$TMP_REPO"

  # Publish a memory commit AFTER the install commit recorded its gitlink, so
  # origin/live in a clone is one commit ahead of what the clone checks out.
  work="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-remote-work.XXXXXX")"
  git clone -q -b live "$GH_MOCK_REMOTE_URL" "$work"
  printf 'later\n' > "$work/LATER.md"
  git -C "$work" add -A
  git -C "$work" -c user.email=t@t -c user.name=t commit -q -m "later fact"
  git -C "$work" push -q origin live
  later=$(git -C "$work" rev-parse HEAD)
  rm -rf "$work"

  CLONE="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-clone.XXXXXX")"
  git clone -q "$ORIGIN" "$CLONE"
  cd "$CLONE"
  git config user.email "test@example.com"
  git config user.name  "Test"
  gitlink=$(git rev-parse HEAD:memory)
  [ "$gitlink" != "$later" ]

  CLAUDE_PROJECT_DIR="$CLONE" GITLORE_LAUNCHED=1 run --separate-stderr bash "$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"
  [ "$status" -eq 0 ]

  # live is the checked-out gitlink commit, not the newer remote tip.
  [ "$(git -C "$CLONE/memory" rev-parse live)" = "$gitlink" ]
  [ "$(git -C "$CLONE/memory" rev-parse HEAD)" = "$gitlink" ]
  [ ! -e "$CLONE/memory/LATER.md" ]
  # The commit waiting upstream is reported, with its count, on both channels.
  echo "$output" | jq -e '.systemMessage | test("1 upstream.*/gitlore:merge")'
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext | test("1 upstream.*/gitlore:merge")'
}
