#!/usr/bin/env bash
# Commit dirty memory itself with the blessed sentinel and fast-forward its
# local `live`: the FR11 commit path, including tier composition, the pin
# guard, and the commit-message freshness check.
# Part of lib/resolve.sh; source that, not this file.

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
      # A tier holding a prepared merge makes memory dirty by construction — its
      # gitlink has moved — so that merge is answered first: asking for a
      # summary would put a merge in front of the user, which both of its sides
      # already approved (D49), and the retry would stop on the directive anyway.
      # The loop below still guards the fresh path; this one only decides which
      # refusal speaks.
      local stale_tier
      while IFS= read -r stale_tier; do
        [ -n "$stale_tier" ] || continue
        [ -e "$mempath/$stale_tier/.git" ] || continue
        gitlore_guard_stale_merge_state "$mempath/$stale_tier" || return 1
      done < <(gitlore_tier_paths "$mempath")
      # The clause is a multi-line block, so it goes last rather than mid-sentence.
      gitlore_say_for_agent_or_user \
        "$(printf '%s\n\n%s\n' \
          "gitlore: memory is dirty and has no approved commit summary. Prepare a summary and present it to the user as a markdown blockquote (\`> …\`), not a code fence, for confirmation; treat only a clear, un-negated affirmative as approval (a hedge, a question, or any negation is a rejection). Only once approved, write it to $msgfile, then retry." \
          "$(gitlore_memory_approval_clause)")" \
        "gitlore: memory has uncommitted changes with no approved commit summary. Open this project in Claude Code and ask it to commit memory, then retry." >&2
      return 1
    fi
    # Every tier gets memory's own stale-merge precheck here, ahead of the first
    # write into it. It runs over every mounted tier rather than the active
    # subset the compose below touches, because what it orders against is
    # gitlore_sync_tiers_to_live, which commits inside a mounted-but-unlisted
    # tier too — otherwise a run commits tier A and then aborts on tier B's
    # stale merge, under a message stating nothing was changed. The
    # guard inside that loop stays: it is that function's own precondition, and
    # a state this call passes is clean by the time it runs, so the second call
    # costs a rev-parse and a stat.
    #
    #
    # From here on a failure restamps $msgfile before returning, unless it
    # prepared a merge. What this run writes into the store — a recovered
    # merge's up projection in this loop, a composed carrier below — is a
    # projection of index lines the summary already approved, never new content,
    # yet it is newer than $msgfile, so gitlore_commit_msg_freshness would read
    # the approval stale on the retry and refuse it. Only commit-memory.sh
    # rewrites the file; the pre-commit path retries on it as it stands. A merge
    # preparation is the exception: it checks merged content out into the
    # worktree, which the summary never covered, so a stale approval is the
    # right answer after it — the merge yields inside gitlore_sync_tiers_to_live
    # return without one. The stale-merge guard in this loop returns without
    # one on every arm, because it does not tell its caller which arm failed,
    # and several prepare nothing: a merge gitlore did not prepare, a merge
    # state nothing can classify, a recovery whose checkout failed. When an
    # earlier tier's recovery has already composed up, the retry after one of
    # those reads the approval stale. Reaching here means $fresh was "yes", so
    # the file exists and a restamp cannot create an empty one, and the memory
    # commit that consumes it is the last step that can fail.
    local tier
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      # `git -C` into an unmaterialized submodule walks up to the enclosing
      # repo, which would answer for memory's own state under the tier's name.
      [ -e "$mempath/$tier/.git" ] || continue
      gitlore_guard_stale_merge_state "$mempath/$tier" || return 1
    done < <(gitlore_tier_paths "$mempath")
    # A previous run that committed inside a tier and stopped before memory's
    # `add -A` recorded it left that tier ahead of its pin — the shape the pin
    # guard below refuses — so it is adopted first.
    gitlore_stage_landed_tiers "$mempath" || { touch "$msgfile"; return 1; }
    # A tier off its pin refuses composition itself (D31, D36), but leaving that
    # refusal to gitlore_compose's own rc-1 arm would let this function's `add -A`
    # below stage the moved gitlink anyway — adopting the move silently in the
    # very commit that reported it as a problem. Checked here, ahead of compose,
    # so an off-pin tier aborts instead.
    # The declaration stays on its own line: folded into `local pin_problems=$(…)`
    # the status read is `local`'s, always 0, and the refusal is swallowed.
    local pin_problems
    if ! pin_problems=$(gitlore_compose_check_pins "$mempath"); then
      local pin_header="gitlore: a tier was moved off the commit the memory store records for it, so the commit was aborted rather than adopt the move:
$pin_problems"
      # The agent arm names no remedy of its own. Every branch of
      # gitlore_compose_check_pins already printed the one its cause takes —
      # /gitlore:resolve mid-merge, the return-to-the-pin checkout sideways or
      # diverged, /gitlore:merge for a tier ahead of its pin, from the pin the
      # guard put it back on or once its commits reach its local `live` — and
      # $pin_problems can carry several tiers with different causes in one
      # abort, so no single remedy named here is right for all of them, and
      # choosing per tier would re-derive a cause that function already
      # decided.
      gitlore_say_for_agent_or_user \
        "$pin_header
gitlore: composing would have overwritten what that tier holds, and committing would have adopted the move silently. Follow the remedy on each line above, then retry the commit. Every remedy writes into the memory store, so the summary has to be approved again before the retry." \
        "$pin_header
gitlore: composing would have overwritten what that tier holds. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
      touch "$msgfile"
      return 1
    fi
    # Compose before the tier commit below: composition writes carrier files
    # inside the tiers, so it must land before gitlore_sync_tiers_to_live moves
    # their gitlinks, or the gitlink pins the pre-compose content — the same
    # one-behind lag the tier-first ordering already exists to prevent.
    local compose_result compose_rc=0
    compose_result=$(gitlore_compose "$mempath") || compose_rc=$?
    case "$compose_rc" in
      0) ;;
      1)
        # A refusal writes nothing (D31, D36): projecting root's older text over
        # an unadopted carrier would destroy approved upstream facts. The commit
        # aborts only on a problem it would publish: a rule 1, 4 or 6 problem —
        # the kinds that name their index file — in root's MEMORY.md or a tier
        # carrier, when that file has uncommitted changes. The same problems in
        # a file with none, a tier dirty only outside its carrier included, and
        # rules 2 and 3, which name no index file, report and let the commit go
        # ahead. The pin guard above aborts on any gitlore_compose_check_pins
        # refusal, so rc 1 reaches here only from gitlore_compose_check: no
        # rule 7 line needs attributing, and the advisory remedy has no pin
        # figure to call stale. The header is gitlore_compose_and_report's own,
        # held in one variable so the arms cannot drift apart.
        local refusal="gitlore: tier composition refused — the memory indexes were left untouched:
$compose_result"
        # A status read that fails aborts rather than reading as a clean index:
        # the pre-commit hook's `|| exit $?` suspends errexit here, so an
        # unchecked failure would publish the problem. Every changed file with
        # a problem is collected, so one abort names all of them.
        local abort_files="" index_status
        if printf '%s\n' "$compose_result" \
          | gitlore_compose_problems_in "$mempath/MEMORY.md" >/dev/null; then
          index_status=$(git -C "$mempath" status --porcelain -- MEMORY.md) \
            || { gitlore_say_unreadable_index_status "$mempath/MEMORY.md" "$refusal"
                 touch "$msgfile"; return 1; }
          [ -z "$index_status" ] || abort_files="$mempath/MEMORY.md"
        fi
        while IFS= read -r tier; do
          [ -n "$tier" ] || continue
          [ -e "$mempath/$tier/.git" ] || continue
          printf '%s\n' "$compose_result" \
            | gitlore_compose_problems_in "$mempath/$tier/MEMORY.md" >/dev/null \
            || continue
          index_status=$(git -C "$mempath/$tier" status --porcelain -- MEMORY.md) \
            || { gitlore_say_unreadable_index_status "$mempath/$tier/MEMORY.md" "$refusal"
                 touch "$msgfile"; return 1; }
          [ -z "$index_status" ] \
            || abort_files="${abort_files:+$abort_files
}$mempath/$tier/MEMORY.md"
        done < <(gitlore_tier_paths "$mempath")
        if [ -n "$abort_files" ]; then
          gitlore_say_for_agent_or_user \
            "$refusal
gitlore: the commit was aborted because a problem is in an index file this commit changes — committing would publish it. The changed index files with problems:
$abort_files
Fix them by editing the lines above that name those files, then retry; the summary needs approval again." \
            "$refusal
gitlore: the commit was aborted because a problem is in an index file this commit changes. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
          touch "$msgfile"
          return 1
        fi
        gitlore_say_for_agent_or_user \
          "$refusal
gitlore: the commit went ahead with the memory indexes as they stand. Fix the problems above by hand — composition runs again at the next memory commit. This commit also stages each tier at the commit its worktree is on now." \
          "$refusal
gitlore: the commit went ahead with the memory indexes as they stand. Open this project in Claude Code and ask it to repair the memory store." >&2
        ;;
      2)
        # A write failed partway, leaving a half-written carrier — that must not
        # be committed, so this aborts before gitlore_sync_tiers_to_live and
        # before anything consumes $msgfile.
        local partial="gitlore: tier composition could not write an index — the memory indexes are only partly composed:
$compose_result"
        gitlore_say_for_agent_or_user \
          "$partial
gitlore: the commit was aborted so the half-written carrier is not committed. Investigate that path (permissions, disk space, a read-only worktree), then retry the commit — the approved summary is still in place and the commit path composes again." \
          "$partial
gitlore: the commit was aborted so the half-written carrier is not committed. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
        # The restamp above the tier loop names why.
        touch "$msgfile"
        return 1
        ;;
      *)
        # Unreachable from gitlore_compose, which returns 0, 1 or 2 and nothing
        # else. Kept because a status this call site does not recognise says
        # nothing about what was written, and silently proceeding on a non-zero
        # status is the failure the case exists to remove — so an unknown one is
        # treated as the partial write it might be.
        local unknown="gitlore: tier composition exited with an unrecognised status ($compose_rc), so what it wrote is unknown:
$compose_result"
        gitlore_say_for_agent_or_user \
          "$unknown
gitlore: the commit was aborted rather than commit a memory store in an unknown state. Establish what gitlore_compose did, then retry the commit — the approved summary is still in place." \
          "$unknown
gitlore: the commit was aborted rather than commit a memory store in an unknown state. Open this project in Claude Code and ask it to repair the memory store, then retry." >&2
        # The restamp above the tier loop names why.
        touch "$msgfile"
        return 1
        ;;
    esac
    # Tiers first: a tier commit moves its gitlink, and the `add -A` below is what
    # records that move in the memory commit. Reversing the order would pin the
    # pre-commit tier SHA — the same one-behind lag the parent's gitlink staging
    # exists to prevent.
    # Restamps its own non-merge failures (see above the tier loop).
    gitlore_sync_tiers_to_live "$mempath" "$msgfile" || return 1
    # Checked explicitly, for the same reason as the tier loop above: called
    # via `|| exit $?` at the pre-commit call site, errexit is off here, and an
    # unchecked failure would delete the approved $msgfile below and let the
    # no-op push report success.
    gitlore_git -C "$mempath" add -A || { touch "$msgfile"; return 1; }
    # Every tier gitlink is staged now, so no landing record is left with a
    # commit to vouch for.
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      [ -e "$mempath/$tier/.git" ] || continue
      rm -f "$(gitlore_tier_landing_file "$mempath/$tier")"
    done < <(gitlore_tier_paths "$mempath")
    # Blessed commit: carry the sentinel so the submodule gate (memory-pre-commit)
    # admits it. A naked commit never sets this and is blocked (FR11/D12).
    GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$msgfile" \
      || { touch "$msgfile"; return 1; }
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
      # ff-push failed. Divergence is one of the two ancestries git reports that
      # way; the other is `live` already containing HEAD, where there is nothing
      # to fast-forward and nothing to merge.
      if [ "$(gitlore_classify_refusal "$mempath" HEAD live)" = "diverged" ]; then
        gitlore_yield_merge "$mempath" live head-vs-live HEAD || return 1
      elif gitlore_check_head_live_agree "$mempath" "memory"; then
        # Refused with the two refs in agreement and no divergence: neither
        # diagnosis applies, so git's own words are all there is to go on.
        gitlore_say_for_agent_or_user \
          "gitlore: updating the local 'live' ref failed, though HEAD and 'live' agree and neither has diverged. git said:
$push_err" \
          "gitlore: updating the local 'live' ref failed. git said:
$push_err" >&2
      fi
      return 1
    fi
  fi

  return 0
}
