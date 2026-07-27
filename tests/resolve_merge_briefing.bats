#!/usr/bin/env bats
# The merger sub-agent's briefing: the two side diffs and the store's file tree,
# written at prepare time, named in the state file, and removed with it.
#
# The merged worktree shows the OUTCOME. It does not show which side introduced
# a line and which merely carried it, and that is the judgement the merge asks
# for — hence a diff per side rather than a re-derivation the agent would have
# to run itself.
#
# $stderr is populated by bats `run --separate-stderr`; shellcheck cannot see it.
# shellcheck disable=SC2154
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures
load helpers/divergence-fixtures
load helpers/stub-synth

PRE_COMMIT="$PLUGIN_ROOT/scripts/git-hooks/pre-commit"
RESOLVE="$PLUGIN_ROOT/scripts/resolve.sh"

setup() {
  setup_tmp_repo
  export CLAUDE_PLUGIN_ROOT="$PLUGIN_ROOT"
  make_parent_with_memory
  git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
  echo parent > parent-file
  git add parent-file
}
teardown() { teardown_tmp_repo; }

artifact() { git -C memory rev-parse --git-path "gitlore-merge-$1"; }
statefile() { git -C memory rev-parse --git-path gitlore-merge-state; }

@test "the state file names all three briefing artifacts and they exist" {
  make_diverged_head_vs_live memory
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]

  local sf; sf=$(statefile)
  [ "$(jq -r .mine_diff "$sf")" = "$(artifact mine.diff)" ]
  [ "$(jq -r .theirs_diff "$sf")" = "$(artifact theirs.diff)" ]
  [ "$(jq -r .tree "$sf")" = "$(artifact tree)" ]
  [ -f "$(artifact mine.diff)" ]
  [ -f "$(artifact theirs.diff)" ]
  [ -f "$(artifact tree)" ]
}

@test "MINE is the authority's diff and THEIRS the pending commit's" {
  make_diverged_head_vs_live memory
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]

  # `live` is the authority (first parent), so MINE carries the live-side file
  # and THEIRS the file the blocked commit introduced. Getting this backwards
  # would invert every attribution the agent makes.
  grep -qF 'LIVE.md' "$(artifact mine.diff)"
  run ! grep -qF 'HEAD_SIDE.md' "$(artifact mine.diff)"
  grep -qF 'HEAD_SIDE.md' "$(artifact theirs.diff)"
  run ! grep -qF 'LIVE.md' "$(artifact theirs.diff)"
}

@test "the tree artifact lists the store's tracked files" {
  make_diverged_head_vs_live memory
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  grep -qxF 'MEMORY.md' "$(artifact tree)"
}

@test "continue-after-merge removes the artifacts along with the state file" {
  make_diverged_head_vs_live memory
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  run --separate-stderr run_stub_synth memory
  [ "$status" -eq 0 ]

  [ ! -f "$(statefile)" ]
  # A briefing outliving its merge would be read against the NEXT one.
  [ ! -f "$(artifact mine.diff)" ]
  [ ! -f "$(artifact theirs.diff)" ]
  [ ! -f "$(artifact tree)" ]
}

@test "one remover drops the state file and every artifact with it" {
  make_diverged_head_vs_live memory
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  [ -f "$(statefile)" ]

  gitlore_clear_merge_state memory
  # Both continuations go through this one function precisely so a briefing
  # cannot outlive its merge and be read against the next one.
  [ ! -f "$(statefile)" ]
  [ ! -f "$(artifact mine.diff)" ]
  [ ! -f "$(artifact theirs.diff)" ]
  [ ! -f "$(artifact tree)" ]
}

@test "abort-then-retry leaves the re-prepared merge's own briefing, not the old one" {
  make_diverged_head_vs_live memory
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]
  printf 'stale marker\n' >> "$(artifact tree)"

  # The abort re-enters the default mode, which finds the same divergence and
  # prepares a fresh merge — so the assertion is that nothing of the aborted
  # one survives into it, not that the files are gone.
  run --separate-stderr bash "$RESOLVE" abort-then-retry
  [ -f "$(statefile)" ]
  [ "$(jq -r .tree "$(statefile)")" = "$(artifact tree)" ]
  run ! grep -qF 'stale marker' "$(artifact tree)"
}

# --- the conflict git does not see -------------------------------------------

# Both sides add the SAME pointer path at DIFFERENT offsets: git's line-wise
# merge sees two insertions in non-overlapping line ranges and calls it clean,
# producing a duplicate pointer. The entry-wise pass keys on the path, so it
# sees one entry two sides disagree about.
diverge_index_same_path_different_offsets() {
  printf '# Memory Index\n\n- [Z](z.md) — z\n' > memory/MEMORY.md
  printf 'z\n' > memory/z.md
  (
    cd memory || exit 1
    git add -A
    GITLORE_MEMORY_COMMIT=1 git -c user.email=t@t -c user.name=t commit -q -m "Base index"
    git push -q . HEAD:live
  )
  # theirs — the pending commit, adding A after Z.
  printf '# Memory Index\n\n- [Z](z.md) — z\n- [A](a.md) — theirs\n' > memory/MEMORY.md
  printf 'a\n' > memory/a.md
  (
    cd memory || exit 1
    git add -A
    GITLORE_MEMORY_COMMIT=1 git -c user.email=t@t -c user.name=t commit -q -m "Pending index"
  )
  # ours — `live` moves sideways, adding A before Z with different text.
  local blob tree commit idx
  idx=$(mktemp "${TMPDIR:-/tmp}/gitlore-idx.XXXXXX"); rm -f "$idx"
  blob=$(printf '# Memory Index\n\n- [A](a.md) — mine\n- [Z](z.md) — z\n' \
    | git -C memory hash-object -w --stdin)
  local ablob; ablob=$(printf 'a\n' | git -C memory hash-object -w --stdin)
  tree=$(
    GIT_INDEX_FILE="$idx" git -C memory read-tree live &&
    GIT_INDEX_FILE="$idx" git -C memory update-index --add --cacheinfo "100644,$blob,MEMORY.md" &&
    GIT_INDEX_FILE="$idx" git -C memory update-index --add --cacheinfo "100644,$ablob,a.md" &&
    GIT_INDEX_FILE="$idx" git -C memory write-tree
  )
  rm -f "$idx"
  commit=$(git -C memory -c user.email=t@t -c user.name=t \
    commit-tree "$tree" -p "$(git -C memory rev-parse live)" -m "Live index")
  git -C memory update-ref refs/heads/live "$commit"
}

@test "an index conflict is labelled in git's vocabulary, not a second one" {
  # Prose memory files in the same merge are marked by git itself, as
  # `<<<<<<< HEAD` … `>>>>>>> <sha>`. The entry-wise pass writes its own chunks,
  # so if it named the same two sides differently the sub-agent would face two
  # vocabularies for one merge and the agent doc would have to reconcile them.
  diverge_index_same_path_different_offsets
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]

  grep -q '^<<<<<<< HEAD$' memory/MEMORY.md
  grep -qE '^>>>>>>> [0-9a-f]{40}$' memory/MEMORY.md
  run ! grep -q '^<<<<<<< MINE' memory/MEMORY.md
  run ! grep -q '^>>>>>>> THEIRS' memory/MEMORY.md
}

@test "conflicted_files names an index only the entry-wise pass found" {
  diverge_index_same_path_different_offsets
  run bash "$PRE_COMMIT"
  [ "$status" -ne 0 ]

  # Git itself merged it clean — no unmerged entry anywhere.
  run git -C memory diff --name-only --diff-filter=U
  [ -z "$output" ]
  # The state file still sends the sub-agent to it.
  [ "$(jq -r '.conflicted_files[]' "$(statefile)")" = "MEMORY.md" ]
  # And the file on disk carries a diff3 chunk for the one disputed path,
  # instead of two bullets naming a.md.
  grep -q '^<<<<<<< ' memory/MEMORY.md
  grep -q '^||||||| ' memory/MEMORY.md
  run -0 grep -c -- '](a.md)' memory/MEMORY.md
  [ "$output" = "2" ]   # one per side of the chunk, never a third
}
