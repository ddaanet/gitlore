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

# Guard against a stale merge-state file before committing or pushing memory:
# never operate on top of a half-finished merge. On a clean state, return 0
# silently. Otherwise emit the appropriate directive/message on stderr and
# return 1, so callers can `|| return 1` / `|| exit 1`.
#   stale-with-merge-head → emit the abort-then-retry merge directive
#   stale-no-merge-head    → emit a fatal manual-intervention message
# Args: $1 = memory worktree path.
gitlore_guard_stale_merge_state() {
  local mempath="$1"
  local state_status statefile flavor
  state_status=$(gitlore_detect_stale_merge_state "$mempath")
  case "$state_status" in
    stale-with-merge-head)
      statefile=$(gitlore_merge_state_file "$mempath")
      flavor=$(jq -r .flavor "$statefile")
      gitlore_emit_merge_directive "$statefile" "$flavor" "abort-then-retry"
      return 1
      ;;
    stale-no-merge-head)
      statefile=$(gitlore_merge_state_file "$mempath")
      echo "gitlore: merge state file present without MERGE_HEAD — manual intervention required. Inspect $statefile and the memory worktree." >&2
      return 1
      ;;
  esac
  return 0
}

# Write a JSON merge-state file. All args required.
# Args: $1=mempath  $2=flavor  $3=base_sha  $4=source_ref  $5=target_ref
#       $6=continuation_subcommand
gitlore_write_merge_state() {
  local mempath="$1" flavor="$2" base="$3" source="$4" target="$5" cont="$6"
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

# Prepare a merge of the pending commit into the more authoritative side. One
# shape serves both flavors (D17 unified branch model): memory is detached at
# `live`, so the authority is reached with `checkout --detach` — no named branch
# is ever checked out, so the one-checkout-per-branch contention that used to
# make this fail (D3) cannot arise, and there is no branch to return to.
# The authority becomes the merge's FIRST parent (D6); the pending commit is
# merged in as the second. The pending commit is pinned at
# `$GITLORE_PENDING_REF` before HEAD moves — nothing else references it once
# `merge --abort` drops MERGE_HEAD.
# Args: $1 = memory worktree path, $2 = authority ref (`live` or `origin/live`).
# Stdout: `<base_sha>:<pending_sha>`.
gitlore_prepare_merge() {
  local mempath="$1" authority="$2"
  local pending base
  pending=$(git -C "$mempath" rev-parse HEAD)
  base=$(git -C "$mempath" merge-base "$pending" "$authority")
  gitlore_git -C "$mempath" update-ref "$GITLORE_PENDING_REF" "$pending"
  gitlore_git -C "$mempath" checkout -q --detach "$authority"
  gitlore_git -C "$mempath" merge --no-commit --no-ff "$pending" >/dev/null 2>&1 || true
  printf '%s:%s\n' "$base" "$pending"
}

# Prepare the merge, record its state file, and emit the sub-agent directive.
# The caller yields (return/exit 1) immediately afterwards. Returns 1 without
# emitting if the merge could not be prepared at all.
# Args: $1 = memory worktree path, $2 = authority ref, $3 = flavor label.
gitlore_yield_merge() {
  local mempath="$1" authority="$2" flavor="$3"
  local prep base pending statefile
  if ! prep=$(gitlore_prepare_merge "$mempath" "$authority"); then
    gitlore_say_for_agent_or_user \
      "gitlore: could not prepare the memory merge against '$authority'. Inspect the memory worktree at $mempath." \
      "gitlore: could not prepare the memory merge against '$authority'. Inspect the memory worktree at $mempath." >&2
    return 1
  fi
  base="${prep%%:*}"
  pending="${prep#*:}"
  gitlore_write_merge_state "$mempath" "$flavor" "$base" "$pending" "$authority" "continue-after-merge"
  statefile=$(gitlore_merge_state_file "$mempath")
  gitlore_emit_merge_directive "$statefile" "$flavor" "continue-after-merge"
  return 0
}

# Commit dirty memory with the blessed sentinel and fast-forward local `live`.
# Assumes the memory worktree exists (caller guards `[ -e "$mempath/.git" ]`).
# Returns 0 on success or no-op. Returns 1 after emitting a directive when:
#   a stale merge state is present, memory is dirty without a fresh approved
#   commit-msg file, or the `HEAD:live` fast-forward fails (the pending commit
#   diverged from `live`). Source the util/log/resolve libs before calling.
# Args: $1 = memory worktree path.
gitlore_sync_memory_to_live() {
  local mempath="$1"

  # Stale merge-state precheck: never commit on top of a half-finished merge.
  gitlore_guard_stale_merge_state "$mempath" || return 1

  local msgfile dirty live_sha head_sha
  msgfile=$(gitlore_commit_msg_file "$mempath")
  dirty=$(gitlore_memory_dirty "$mempath")
  # `-q --verify` is silent when `live` does not exist (the expected miss), so no
  # redirect is needed and a real rev-parse failure is no longer swallowed.
  live_sha=$(git -C "$mempath" rev-parse -q --verify live || echo "")
  head_sha=$(git -C "$mempath" rev-parse HEAD)

  if [ "$dirty" = "0" ] && [ "$head_sha" = "$live_sha" ]; then
    return 0
  fi

  if [ "$dirty" = "1" ]; then
    local fresh
    fresh=$(gitlore_commit_msg_freshness "$mempath")
    if [ "$fresh" != "yes" ]; then
      gitlore_say_for_agent_or_user \
        "gitlore: memory is dirty and has no approved commit summary. Prepare a summary and present it to the user as a markdown blockquote (\`> …\`), not a code fence, for confirmation; treat only a clear, un-negated affirmative as approval (a hedge, a question, or any negation is a rejection). Only once approved, write it to $msgfile, then retry." \
        "gitlore: memory has uncommitted changes with no approved commit summary. Open this project in Claude Code and ask it to commit memory, then retry." >&2
      return 1
    fi
    gitlore_git -C "$mempath" add -A
    # Blessed commit: carry the sentinel so the submodule gate (memory-pre-commit)
    # admits it. A naked commit never sets this and is blocked (FR11/D12).
    GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$msgfile"
    rm -f "$msgfile"
    # The dirty episode is over: clear the once-per-episode nudge marker so the
    # next round of uncommitted memory can be surfaced again (post-tool-use.sh).
    rm -f "$(gitlore_commit_notified_file "$mempath")"
  fi

  if [ -n "$live_sha" ]; then
    # Capture, don't discard: this push is to the local repo (`.`), where a
    # non-fast-forward genuinely does mean HEAD-vs-live divergence — but a
    # failure for any OTHER reason (a ref lock, a corrupt object) would have been
    # read as divergence too, sending the user into a merge that cannot help.
    local push_err=""
    if ! push_err=$(gitlore_git -C "$mempath" push -q . HEAD:live 2>&1); then
      case "$push_err" in
        *"(fetch first)"*|*"(non-fast-forward)"*) ;;
        *)
          if [ -n "$push_err" ]; then
            gitlore_say_for_agent_or_user \
              "gitlore: updating the local 'live' ref failed, and not because of divergence. git said:
$push_err" \
              "gitlore: updating the local 'live' ref failed, and not because of divergence. git said:
$push_err" >&2
            return 1
          fi
          ;;
      esac
      # ff-push failed → the pending commit has diverged from local `live`.
      gitlore_yield_merge "$mempath" live head-vs-live || return 1
      return 1
    fi
  fi

  return 0
}
