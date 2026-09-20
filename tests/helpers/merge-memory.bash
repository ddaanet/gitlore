#!/usr/bin/env bash
# Shared setup and fixtures for the merge_memory* suites (/gitlore:merge).

# shellcheck disable=SC2034   # used by callers' @test bodies
CMD="$PLUGIN_ROOT/scripts/merge-memory.sh"
# shellcheck disable=SC2034   # used by callers' @test bodies
SESSION_START="$PLUGIN_ROOT/scripts/cc-hooks/session-start.sh"

# /gitlore:merge is the half of /gitlore:push that takes without publishing, and
# under pinned tiers it is the only path by which a tier advances at all. What is
# pinned here is that direction: what each store ends up holding, what reaches
# the root index, and that nothing of this repo's leaves it.
setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  MEMORY_REMOTE="$TMP_REPO/.memory-remote.git"
  export MEMORY_REMOTE
}
teardown() { teardown_tmp_repo; }

wire_memory_remote() {
  git init -q --bare "$MEMORY_REMOTE"
  make_parent_with_memory
  git -C memory remote remove origin || true
  git -C memory remote add origin "$MEMORY_REMOTE"
  git -C memory push -q origin live
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
}

# Publish a commit to the memory remote that this clone does not have.
push_memory_fact() {
  local work
  work="$(mktemp -d "$TMP_REPO/clone.XXXXXX")"
  (
    cd "$work" || exit 1
    git clone -q "$MEMORY_REMOTE" .
    git checkout -q live
    printf 'remote-only\n' > REMOTE.md
    git add -A
    git -c user.email=t@t -c user.name=t commit -q -m "remote fact"
    git push -q origin live
  )
  rm -rf "$work"
}

# The files under a tier's gitdir outside what git itself keeps moving —
# objects, logs, refs, FETCH_HEAD, ORIG_HEAD — one per line, sorted. A take's
# scratch copy or temporary index left behind shows up as a difference.
tier_gitdir_files() {
  local gitdir
  gitdir=$(git -C "memory/$1" rev-parse --absolute-git-dir) || return 1
  (
    cd "$gitdir" || exit 1
    find . -type f ! -path './objects/*' ! -path './logs/*' ! -path './refs/*' \
      ! -name FETCH_HEAD ! -name ORIG_HEAD | LC_ALL=C sort
  )
}

# The repair scratch directories left directly under $1, one per line.
repair_scratch_dirs() {
  find "$1" -mindepth 1 -maxdepth 1 -name 'gitlore-repair.*' -print
}
