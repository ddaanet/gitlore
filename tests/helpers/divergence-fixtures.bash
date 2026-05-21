#!/usr/bin/env bash
# Factories for divergence scenarios. Caller is responsible for
# setup_tmp_repo + make_parent_with_memory first.

# Branch-vs-live: worktree branch and live each get one non-overlapping commit.
make_diverged_branch_vs_live() {
  local mempath="${1:-memory}"
  (
    cd "$mempath"
    git checkout -q worktree
    echo "branch-side" > BRANCH.md
    git add BRANCH.md
    git -c user.email=t@t -c user.name=t commit -q -m "Branch commit"
    git checkout -q live
    echo "live-side" > LIVE.md
    git add LIVE.md
    git -c user.email=t@t -c user.name=t commit -q -m "Live commit"
    git checkout -q worktree
  )
}

# Local-vs-remote: local live and the bare remote each get one non-overlapping commit.
make_diverged_local_vs_remote() {
  local mempath="${1:-memory}"
  local bare="${TMP_REPO}/.bare-memory.git"
  local clone_dir
  clone_dir="$(mktemp -d "${TMP_REPO}/clone.XXXXXX")"
  (
    cd "$clone_dir"
    git clone -q "$bare" .
    git checkout -q live
    echo "remote-side" > REMOTE.md
    git add REMOTE.md
    git -c user.email=t@t -c user.name=t commit -q -m "Remote commit"
    git push -q origin live
  )
  rm -rf "$clone_dir"
  (
    cd "$mempath"
    git fetch -q origin
    git checkout -q live
    echo "local-side" > LOCAL.md
    git add LOCAL.md
    git -c user.email=t@t -c user.name=t commit -q -m "Local commit"
  )
}
