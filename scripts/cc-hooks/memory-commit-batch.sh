#!/usr/bin/env bash
set -euo pipefail

# PostToolBatch: commit memory WITHOUT the agent ever running git.
#
# The agent writes two ordinary files — the approved summary
# (gitlore-memory-message) and a trigger (gitlore-commit-memory) — and this hook
# runs commit-memory.sh on its behalf. Because the agent makes no Bash call and
# never touches the submodule gitdir, this sidesteps the sandbox and the
# auto-mode classifier entirely; that is precisely why file-trigger + hook beats
# agent-runs-git for the standalone/handoff memory commit (which must land before
# any parent commit, whether or not the agent stops).
#
# The trigger file IS the signal; the batch payload carries no request.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"

# The trigger file, not the payload, drives us — but `cwd` is read out of it for
# the stranded-trigger check below, so the payload is captured rather than dropped.
payload=$(cat) || payload=''

# $1 = systemMessage (user), $2 = additionalContext (model). Both, always.
#
# systemMessage is user-only (D14), so a hook that emits it alone leaves the
# agent blind to the outcome of a commit it requested — and it then goes
# looking. Measured over every landing in the transcript corpus: on this
# trigger-file path the agent re-checks the IPC files or the memory log after
# 62 of 68 successful commits, a mean of 1.97 extra assistant messages and a
# median 6.4 s each. On the parent-commit path, where the outcome comes back in
# a Bash tool result the model can read, the same check happens 5 times in 14.
# Every other batch hook here already pairs the two channels.
emit() {
  jq -n --arg s "$1" --arg c "$2" \
    '{systemMessage: $s, suppressOutput: true,
      hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
}

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
# From here a death reports to the user and the agent instead of ending the turn (D60).
gitlore_batch_hook_guard "memory-commit-batch" "$mempath" "The outcome of the memory commit is unknown, and the two IPC files (the trigger and the summary) may still be in place: check the memory store's log and status before running the commit command again."
[ -e "$mempath/.git" ] || exit 0          # session-less worktree: no memory to commit

trigger=$(gitlore_commit_trigger_file "$mempath")
msgfile=$(gitlore_commit_msg_file "$mempath")
if [ ! -f "$trigger" ]; then
  # Usually: no request this batch, nothing to do, stay silent.
  #
  # But a request written against a DIFFERENT root is invisible from here, and
  # exiting 0 on it loses an approval the user already gave. The handoff probe
  # resolves the IPC dir from `git rev-parse --show-toplevel` of the session
  # cwd; this hook resolves it from CLAUDE_PROJECT_DIR. A linked worktree makes
  # those disagree — CC chdirs into the worktree and leaves CLAUDE_PROJECT_DIR
  # at the launch repo — so the agent writes the summary and trigger into the
  # worktree's .claude/ and memory never commits, with nothing said.
  #
  # Reported, not adopted: cwd may be another repository entirely (`/add-dir`),
  # and a trigger from one working tree is not authority to commit another's
  # memory. The paths are absolute in both messages so the agent can move the
  # files without deriving anything.
  cwd=$(printf '%s' "$payload" | jq -r '.cwd // empty') || cwd=''
  if [ -n "$cwd" ] && [ -d "$cwd" ]; then
    # cwd need not be a repository at all, which is why the failure is captured
    # rather than shown: the empty result IS the "nothing stranded here" answer.
    other_root=$(git -C "$cwd" rev-parse --show-toplevel 2>&1) || other_root=''
    other_trigger="$other_root/.claude/gitlore-commit-memory"
    if [ -n "$other_root" ] && [ "$other_trigger" != "$trigger" ] && [ -f "$other_trigger" ]; then
      emit "gitlore: a commit-memory request is sitting at $other_trigger, outside this project root ($PWD) — it was written against a different working tree, so nothing was committed and your approved summary has not landed." \
        "gitlore: a commit-memory trigger exists at $other_trigger, but this hook only reads $trigger — the session cwd and CLAUDE_PROJECT_DIR resolve to different roots, so the memory commit did not run. Move the approved summary to $msgfile and the trigger to $trigger to commit the memory at $PWD; if the memory you meant to commit is the other working tree's, commit it from a session rooted there instead."
    fi
  fi
  exit 0
fi

if [ "$(gitlore_memory_dirty "$mempath")" = "0" ]; then
  # Nothing to commit: the request is satisfied (or was spurious). Both IPC files
  # go, which is what makes the message below true — a summary left behind covers
  # a store with nothing pending, and the next dirty episode needs its own
  # approval anyway, so keeping it only leaves the agent something to find.
  rm -f "$trigger" "$msgfile"
  emit "gitlore: commit-memory trigger cleared — memory was already clean, nothing to commit." \
    "gitlore: memory was already clean, so there was nothing to commit; both IPC files have been removed. Do not check for them and do not re-trigger."
  exit 0
fi

# A prepared merge outranks the approval screen below. The landed-then-failed
# arm at the foot of this file leaves one, with the approval already consumed by
# the commit that did land, and the merge's checkout makes memory dirty by
# construction — so the very next batch arrives here with nothing approved.
# Asking for a summary then puts in front of the user a merge both of whose sides
# they already approved (D49), in place of the directive /gitlore:resolve acts
# on. Skipping the screen lets the run below re-emit that directive from the
# store, where the same guard reads it.
mid_merge=0
if gitlore_any_store_mid_merge "$mempath"; then mid_merge=1; fi
approved_before=0
if gitlore_approval_present "$msgfile"; then approved_before=1; fi

if [ "$approved_before" = "0" ] && [ "$mid_merge" = "0" ]; then
  # An all-whitespace file is no approval either, and it must be caught here
  # rather than passed on: `git commit -F` rejects it as an empty message and
  # that arm restamps $msgfile, so the run below would fail identically on every
  # later batch. commit-memory.sh screens with this same predicate.
  #
  # Keep the trigger: the moment the approved summary lands, the next
  # PostToolBatch commits transparently — the agent need not re-trigger.
  # The clause is a multi-line block and goes last in each message; emit() builds
  # the JSON with --arg, so the newlines survive escaping.
  clause=$(gitlore_memory_approval_clause)
  emit "$(printf '%s\n\n%s\n' \
      "gitlore: commit-memory is pending but no approved summary exists yet at $msgfile. Summarize the pending memory changes, present the summary to the user as a markdown blockquote (\`> …\`) rather than a code fence, get their approval, and write the summary to $msgfile — the commit then completes on its own." \
      "$clause")" \
    "$(printf '%s\n\n%s\n' \
      "gitlore: a memory commit is pending, but no approved summary exists yet. Summarize the pending memory changes as a commit message, present it to the user as a markdown blockquote (\`> …\`) rather than a code fence, and once they approve write it to $msgfile. The commit then completes on its own — do not re-trigger it." \
      "$clause")"
  exit 0
fi

# commit-memory.sh runs bare: the approval already on disk is judged by its own
# freshness and only a fresh one commits. It never makes a parent commit (D16),
# and a failure before the commit consumes neither IPC file — that is what lets
# the next PostToolBatch retry.
#
# Which failure message goes out is read off the store and the IPC file the run
# left behind, never off a status the run reports about itself (D53). Four
# states, in the order tested below.
if out=$(bash "$PLUGIN_ROOT/scripts/commit-memory.sh" 2>&1); then
  rm -f "$trigger"
  # The agent's own next move, handed to it: this is the value 62 of 68 landings
  # went and fetched with `git -C memory log --oneline -1`.
  memhead=$(git -C "$mempath" log -1 --format='%h %s') || memhead='(unavailable)'
  emit "gitlore: memory committed and local live advanced." \
    "gitlore: the memory commit you requested has landed. Memory HEAD is now $memhead, local live is advanced, and both IPC files have been removed. This is the authoritative outcome — do not run git status, git log, or ls to confirm it."
else
  # An approval that was there and non-blank before the run and is gone now means
  # the commit landed and a step after it failed — the `HEAD:live` fast-forward,
  # which removes $msgfile before it runs. Nothing is waiting on approval and no
  # later batch repeats the failed step, so the reason is the whole message; it
  # carries the prepared-merge directive on the divergence arm. The pre-run state
  # is what makes the absence mean this: the screen above admits a run with no
  # approval at all when the store is mid-merge.
  if [ "$approved_before" = "1" ] && ! gitlore_approval_present "$msgfile"; then
    emit "gitlore: memory committed, but the step after it did not finish. $out" \
      "gitlore: the memory commit landed, and its approved summary has been consumed — nothing is waiting on approval and the commit will not be made again. Act on the reason below. Reason: $out"
  # The store still holds the merge the run refused to commit on top of, so the
  # guard's directive IS the message — the freshness arm below would drop it and
  # ask for a summary instead, which is the ask D49 keeps off a merge. Nothing was
  # committed and no approval was consumed: the report-only guard arms do not
  # restamp (D53). Re-approval follows the merge rather than preceding it, because
  # landing it writes content into the store no summary has covered.
  elif gitlore_any_store_mid_merge "$mempath"; then
    emit "gitlore: memory commit deferred — the memory store or a mounted tier holds a prepared merge. $out" \
      "gitlore: the memory commit did not run: the memory store or a mounted tier holds a prepared merge, which is answered before any commit. Nothing was committed and no approved summary was consumed. Act on the directive below; once the merge is landed the commit retries by itself on a later tool batch, and asks for approval then, because landing the merge writes content into the store no summary has covered. Reason: $out"
  # Something newer than the approval is in the store: the agent's own edit, a
  # checkout, a take, a resolved merge. The summary on disk is the text to amend
  # and re-present. The script's reason is dropped — it is the sync's "no
  # approved commit summary", which reads wrong next to a file that exists.
  #
  # Substituted inside the test rather than assigned: an assignment whose last
  # command returns non-zero aborts the hook under `set -e` and emits nothing at
  # all, while here the test's own status governs, so an unreadable freshness
  # falls through to the deferred arm and still hands over $out.
  elif [ "$(gitlore_commit_msg_freshness "$mempath")" = "no" ]; then
    clause=$(gitlore_memory_approval_clause)
    emit "gitlore: memory commit deferred — the approved summary no longer covers the store, approval needed again" \
      "$(printf '%s\n\n%s\n' \
          "gitlore: the approved summary at $msgfile no longer covers the memory store. Present it to the user again as a markdown blockquote (\`> …\`) rather than a code fence, amended for what changed, and once they approve write it to $msgfile — the commit then completes on its own." \
          "$clause")"
  # The approval still covers the store: a locked repo, an in-flight merge, a
  # refusal naming an edit the agent has not made yet. Both IPC files stand and
  # the next batch retries on its own.
  else
    emit "gitlore: memory commit deferred, will retry automatically. $out" \
      "gitlore: the memory commit did not run and has been deferred; it retries by itself on a later tool batch, with the approved summary preserved, and re-triggering will not help. When the reason below names a fix, make it and the retry picks it up; otherwise no action is needed from you. Reason: $out"
  fi
fi
exit 0
