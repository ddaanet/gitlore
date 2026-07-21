#!/usr/bin/env bash
# Factories for divergence scenarios. Caller is responsible for
# setup_tmp_repo + make_parent_with_memory first.

# Add a commit on top of a ref WITHOUT checking it out. The branch model is
# detached-at-live (D17), so `live` is never checked out and the porcelain route
# (checkout, edit, commit, checkout back) is unavailable — these fixtures build
# the commit with plumbing against a scratch index instead.
# Args: $1=mempath  $2=branch  $3=filename  $4=content  $5=commit message
#       $6=base ref to build on (default: the branch itself — pass e.g. `live^`
#          to move the branch sideways instead of forward, which is what makes a
#          divergence rather than a fast-forward).
advance_branch_with_file() {
  local mempath="$1" branch="$2" file="$3" content="$4" msg="$5" base="${6:-$2}"
  local blob tree commit idx
  idx=$(mktemp "${TMPDIR:-/tmp}/gitlore-idx.XXXXXX")
  rm -f "$idx"   # read-tree creates it; mktemp only reserves the name
  blob=$(printf '%s\n' "$content" | git -C "$mempath" hash-object -w --stdin)
  tree=$(
    GIT_INDEX_FILE="$idx" git -C "$mempath" read-tree "$base" &&
    GIT_INDEX_FILE="$idx" git -C "$mempath" update-index --add \
      --cacheinfo "100644,$blob,$file" &&
    GIT_INDEX_FILE="$idx" git -C "$mempath" write-tree
  )
  rm -f "$idx"
  commit=$(git -C "$mempath" -c user.email=t@t -c user.name=t \
    commit-tree "$tree" -p "$(git -C "$mempath" rev-parse "$base")" -m "$msg")
  git -C "$mempath" update-ref "refs/heads/$branch" "$commit"
}

# HEAD-vs-live: the detached worktree and `live` each get one non-overlapping
# commit. Mirrors the real shape — a memory commit lands while another worktree
# (or a resolve) advances `live` underneath it.
make_diverged_head_vs_live() {
  local mempath="${1:-memory}"
  (
    cd "$mempath" || exit 1
    echo "head-side" > HEAD_SIDE.md
    git add HEAD_SIDE.md
    git -c user.email=t@t -c user.name=t commit -q -m "Pending commit"
  )
  advance_branch_with_file "$mempath" live LIVE.md "live-side" "Live commit"
}

# HEAD-vs-remote: local (HEAD and `live` together, as the commit path leaves
# them) and the bare remote each get one non-overlapping commit.
make_diverged_head_vs_remote() {
  local mempath="${1:-memory}"
  local bare="${TMP_REPO}/.bare-memory.git"
  # Ensure live exists in the bare (make_parent_with_memory only creates it locally).
  git -C "$mempath" push -q origin live || true
  local clone_dir
  clone_dir="$(mktemp -d "${TMP_REPO}/clone.XXXXXX")"
  (
    cd "$clone_dir" || exit 1
    git clone -q "$bare" .
    git checkout -q live
    echo "remote-side" > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "Remote commit"
    git push -q origin live
  )
  rm -rf "$clone_dir"
  (
    cd "$mempath" || exit 1
    git fetch -q origin
    echo "local-side" > LOCAL.md
    git add LOCAL.md
    git -c user.email=t@t -c user.name=t commit -q -m "Local commit"
    # The commit path advances local `live` immediately; mirror that here so the
    # divergence is genuinely local `live` vs `origin/live`.
    git push -q . HEAD:live
  )
}
