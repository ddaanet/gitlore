#!/usr/bin/env bash
# Shared functions for memory divergence detection, state-file IO, and
# directive emission. Source; do not exec.

# Detect whether a stale merge-state file + MERGE_HEAD exists.
# Stdout: "clean" | "stale-with-merge-head" | "stale-no-merge-head".
gitlore_detect_stale_merge_state() {
  local mempath="$1"
  local statefile
  statefile=$(gitlore_merge_state_file "$mempath")
  if [ ! -f "$statefile" ]; then
    printf 'clean\n'
    return 0
  fi
  local gitdir
  gitdir=$(git -C "$mempath" rev-parse --git-dir)
  if [ -f "$gitdir/MERGE_HEAD" ]; then
    printf 'stale-with-merge-head\n'
  else
    printf 'stale-no-merge-head\n'
  fi
}

# Write a JSON merge-state file. All args required.
# Args: $1=mempath  $2=flavor  $3=base_sha  $4=source_ref  $5=target_ref
#       $6=return_branch  $7=continuation_subcommand
gitlore_write_merge_state() {
  local mempath="$1" flavor="$2" base="$3" source="$4" target="$5" return_branch="$6" cont="$7"
  local statefile
  statefile=$(gitlore_merge_state_file "$mempath")
  local changed conflicted
  # Union of files changed on either side of the merge — target_ref (HEAD post-checkout)
  # AND source_ref (the incoming branch). diff base...HEAD alone misses source-side files.
  changed=$({ git -C "$mempath" diff --name-only "$base...$target"; \
              git -C "$mempath" diff --name-only "$base...$source"; } \
    | sort -u | jq -R . | jq -s . || echo '[]')
  conflicted=$(git -C "$mempath" diff --name-only --diff-filter=U \
    | jq -R . | jq -s . || echo '[]')
  cat > "$statefile" <<EOF
{
  "flavor": "$flavor",
  "base": "$base",
  "source_ref": "$source",
  "target_ref": "$target",
  "return_branch": "$return_branch",
  "changed_files": $changed,
  "conflicted_files": $conflicted,
  "continuation": "$cont"
}
EOF
}

# Emit the structured directive on stderr.
# Args: $1=statefile_path  $2=flavor  $3=continuation_subcommand
# Emits absolute paths for both the parent repo root (cd target — needed because
# the continuation invokes git plumbing that reads .gitmodules from CWD) and
# the plugin's resolve.sh. Sub-agent runs the command verbatim; no env vars or
# CWD assumptions required.
gitlore_emit_merge_directive() {
  local statefile="$1" flavor="$2" cont="$3"
  local root="${PLUGIN_ROOT:-${CLAUDE_PLUGIN_ROOT:-}}"
  local repo
  repo=$(git rev-parse --show-toplevel)
  cat >&2 <<EOF
gitlore: memory merge prepared (flavor=$flavor).
gitlore: dispatch the memory-merger sub-agent with state file:
gitlore:   $statefile
gitlore: on approval, the sub-agent must run:
gitlore:   cd "$repo" && bash "$root/scripts/resolve.sh" $cont
EOF
}

# Prepare branch-vs-live merge. Caller must already know it's needed.
# Stdout: `<branch>:<base_sha>`.  Exit 2 on concurrent-checkout (live already checked out).
gitlore_prepare_branch_vs_live() {
  local mempath="$1"
  local branch base
  branch=$(git -C "$mempath" symbolic-ref --short -q HEAD || git -C "$mempath" rev-parse HEAD)
  base=$(git -C "$mempath" merge-base "$branch" live)
  git -C "$mempath" checkout -q live || return 2
  git -C "$mempath" merge --no-commit --no-ff "$branch" >/dev/null 2>&1 || true
  printf '%s:%s\n' "$branch" "$base"
}

# Prepare local-vs-remote merge.
# Stdout: `<return_branch>:<base_sha>:<old_local_sha>`.  Exit 2 on concurrent-checkout.
gitlore_prepare_local_vs_remote() {
  local mempath="$1"
  local return_branch old_local base
  return_branch=$(git -C "$mempath" symbolic-ref --short -q HEAD || git -C "$mempath" rev-parse HEAD)
  old_local=$(git -C "$mempath" rev-parse live)
  git -C "$mempath" checkout -q live || return 2
  git -C "$mempath" reset --hard -q origin/live
  base=$(git -C "$mempath" merge-base "$old_local" origin/live)
  git -C "$mempath" merge --no-commit --no-ff "$old_local" >/dev/null 2>&1 || true
  printf '%s:%s:%s\n' "$return_branch" "$base" "$old_local"
}
