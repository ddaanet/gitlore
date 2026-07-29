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
# The trigger file IS the signal, so the batch payload is unused.

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
  # Nothing to commit: the request is satisfied (or was spurious). Clear it.
  rm -f "$trigger"
  emit "gitlore: commit-memory trigger cleared — memory was already clean, nothing to commit." \
    "gitlore: memory was already clean, so there was nothing to commit; the trigger file has been removed. Both IPC files are gone. Do not check for them and do not re-trigger."
  exit 0
fi

if [ ! -s "$msgfile" ]; then
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

# commit-memory.sh reads the summary from the message file, commits the memory
# submodule with the blessed sentinel, advances local `live`, and consumes the
# message file — all ONLY on success. It never makes a parent commit (D16).
#
# Remove the trigger only when the commit is COMPLETE. A locked repo (index.lock,
# or `live` checked out by another session) and an in-flight merge are expected
# transient conditions: on failure we leave the trigger AND the message file in
# place, so the next PostToolBatch retries transparently — no agent action, no
# lost approval.
if out=$(bash "$PLUGIN_ROOT/scripts/commit-memory.sh" -F "$msgfile" 2>&1); then
  rm -f "$trigger"
  # The agent's own next move, handed to it: this is the value 62 of 68 landings
  # went and fetched with `git -C memory log --oneline -1`.
  memhead=$(git -C "$mempath" log -1 --format='%h %s') || memhead='(unavailable)'
  emit "gitlore: memory committed and local live advanced." \
    "gitlore: the memory commit you requested has landed. Memory HEAD is now $memhead, local live is advanced, and both IPC files have been removed. This is the authoritative outcome — do not run git status, git log, or ls to confirm it."
else
  emit "gitlore: memory commit deferred, will retry automatically. $out" \
    "gitlore: the memory commit did not run and has been deferred; it retries by itself on a later tool batch, with the approved summary preserved. No action is needed from you and re-triggering will not help. Reason: $out"
fi
exit 0
