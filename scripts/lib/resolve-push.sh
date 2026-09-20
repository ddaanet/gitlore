#!/usr/bin/env bash
# Publish every store to its own remote: each mounted tier's `live` first,
# then memory's — the shared implementation behind pre-push and
# push-memory.sh (D20).
# Part of lib/resolve.sh; source that, not this file.

# Report the abort an unreadable index status forces, on both channels. That
# read decides whether a composition problem is in a file this commit changes,
# i.e. whether committing would publish it, so a failure there leaves the
# question open and the commit stops on it — with the compose refusal that sent
# the run to the read, which is the list a retry has to fix. The approval is
# restamped by the caller, as after every failure that prepared no merge, so the
# retry reuses the summary as it stands.
# Args: $1 = the index file whose status could not be read, $2 = that refusal.
gitlore_say_unreadable_index_status() {
  local file="$1" refusal="$2"
  gitlore_say_for_agent_or_user \
    "$refusal
gitlore: the commit was aborted because git could not read the status of $file, so whether this commit changes that index is unknown. Establish why \`git status\` fails in the store holding it, then retry the commit — the approved summary is still in place." \
    "$refusal
gitlore: the commit was aborted because git could not read the status of $file. Open this project in Claude Code and ask it to repair the memory store, then retry the commit." >&2
}

# Stage the gitlink of each tier whose HEAD is the commit gitlore_sync_tiers_to_live
# made and a stopped run never recorded: memory's `add -A` failed after it (a
# transient index.lock) or the run died between the two. That tier sits ahead of
# its pin, the shape gitlore_compose_check_pins refuses for a tier moved behind
# gitlore's back, so without this the retry memory-commit-batch.sh promises is
# refused for good. Staging it overwrites nothing: the commit path composed that
# carrier from the root index just before committing it.
#
# Recognised by the landing record written just before that commit — HEAD's
# parent must be the commit the record names, and memory's index must still pin
# it. Not by the commit's message: a session that edits memory before the retry
# lands approves a new summary, and the old commit no longer matches it.
# Residual: a run killed after writing the record and before its commit failed
# leaves the record behind, and a commit later made on that same pin by other
# means would be adopted.
# Returns 1, after git's own message, when a gitlink cannot be staged.
# Args: $1 = memory worktree path.
gitlore_stage_landed_tiers() {
  local mempath="$1" tier tierpath landing recorded pinned parent
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # `git -C` into an unmaterialized submodule walks up to the enclosing repo.
    [ -e "$tierpath/.git" ] || continue
    landing=$(gitlore_tier_landing_file "$tierpath") || continue
    [ -f "$landing" ] || continue
    recorded=""
    IFS= read -r recorded < "$landing" || [ -n "$recorded" ] || continue
    # `-q --verify` is silent on the expected misses: no gitlink in the index
    # (mid-mount), and a HEAD that is a root commit.
    pinned=$(git -C "$mempath" rev-parse -q --verify ":$tier") || continue
    parent=$(git -C "$tierpath" rev-parse -q --verify "HEAD^") || continue
    [ "$recorded" = "$pinned" ] || continue
    [ "$parent" = "$recorded" ] || continue
    gitlore_git -C "$mempath" add -- "$tier" || return 1
    rm -f "$landing"
  done < <(gitlore_tier_paths "$mempath")
  return 0
}

# Publish every store to its own remote: each tier's `live` first, then memory's.
# Assumes the memory worktree exists (caller guards `[ -e "$mempath/.git" ]`).
# Returns 0 when everything is published (already-up-to-date included, and a
# memory store that has no remote of its own once its tiers are out). Returns 1
# after emitting a message when a tier has no remote, a stale merge state is
# present, a push is refused, or the remote is unreachable; a refusal that git
# attributes to divergence yields a prepared merge for `/gitlore:resolve`.
#
# Shared by `pre-push` (publishing alongside the parent) and `push-memory.sh`
# (publishing on its own, with no parent push — D20). One implementation, so the
# ordering guarantee below cannot drift between the two entry points.
# Args: $1 = memory worktree path.
gitlore_push_stores() {
  local mempath="$1" remote_url tier tierpath tier_err push_err

  # Never publish on top of a half-finished merge, at any level.
  gitlore_guard_stale_merge_state "$mempath" || return 1

  # Resolved here but acted on AFTER the tiers: memory having no remote says
  # nothing about theirs. A repo whose memory is deliberately local can still
  # mount a shared tier, and that tier is the part other repositories read.
  remote_url=$(git -C "$mempath" config --get remote.origin.url || true)
  # A `git submodule sync` on a local-only install copies the placeholder out of
  # `.gitmodules` into origin, where it names no repository. Same state as an
  # unset remote, and diagnosing it as an unreachable host would send the user
  # after a network problem they do not have.
  if gitlore_is_placeholder_url "$remote_url"; then
    remote_url=""
  fi

  # Tier push lockstep (D17). Each tier is an independent repo with its own remote,
  # and the memory commit about to be published records its gitlink — so every tier
  # commit must reach its remote BEFORE that pointer goes out, or a colleague
  # fetches memory and cannot resolve the tier. Driver-side, like memory's own
  # push: the memory store gets no recursing pre-push.
  # Failure here is fatal. A tier that silently stops publishing is indistinguish-
  # able from one with nothing to say, which is exactly how shared memory rots.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # Unchecked-out tier: `git -C` escapes to the enclosing repo, which would push
    # MEMORY's live to memory's origin under the tier's name.
    [ -e "$tierpath/.git" ] || continue
    # `-q --verify` is silent on the expected miss: a tier never fetched has no
    # local `live` and so has nothing of its own to publish.
    git -C "$tierpath" rev-parse -q --verify live >/dev/null || continue
    if [ -z "$(git -C "$tierpath" config --get remote.origin.url || true)" ]; then
      gitlore_say_for_agent_or_user \
        "gitlore: tier '$tier' has no remote configured, so nothing written there is being shared. Mount it against a remote or unmount it." \
        "gitlore: tier '$tier' has no remote configured, so nothing written there is being shared." >&2
      return 1
    fi
    # Never push on top of a half-finished merge, at any level.
    gitlore_guard_stale_merge_state "$tierpath" || return 1
    # Before anything is published: what goes out is `live`, what the memory
    # commit records is HEAD. A store whose refs disagree publishes something
    # other than the commit its pointer names. One of the two disagreements is
    # not a decision — a `live` behind a HEAD containing it is repaired here
    # rather than reported, and the check then sees two refs that agree.
    gitlore_repair_stranded_live "$tierpath" "tier '$tier'" || return 1
    # The other direction is not a repair but a take: a `live` ahead of a HEAD
    # sitting at the pin holds approved commits the memory store never recorded,
    # and moving HEAD onto it alone would take the tier off that pin (D43), which
    # is what the next composition refuses. The whole take pass, not this tier
    # alone, and for the reason the behind-tier branch below gives: it runs
    # root-first, and a tier take writes a bookkeeping commit that would meet an
    # equally-behind root's upstream one as a divergence. No `continue` after it
    # — unlike a take from the remote, what was adopted here has never been
    # published, so this tier's push is exactly what has to happen next.
    #
    # This take and the behind arm's run marked as inside a push, so a repair
    # names this push as what publishes it rather than /gitlore:push — also
    # when the repair lands on a different tier than this iteration's: a later
    # tier goes out with its own iteration's push, and one whose iteration
    # already finished with the post-loop pass below.
    if gitlore_live_ahead_of_head "$tierpath"; then
      GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores "$mempath" || return 1
    fi
    gitlore_check_head_live_agree "$tierpath" "tier '$tier'" "$tier" || return 1
    # `origin/live` has to be current before it can serve as the merge authority.
    # Non-fatal, exactly as memory's is: the push below is what decides.
    git -C "$tierpath" fetch -q origin live || true
    if ! tier_err=$(gitlore_git -C "$tierpath" push -q origin live 2>&1); then
      # Same discriminator as memory's push below: git's parenthesized reason
      # separates divergence from policy/credential/quota refusals, and ancestry
      # then separates the two states that share the divergence reason.
      case "$tier_err" in
        *"(fetch first)"*|*"(non-fast-forward)"*)
          case "$(gitlore_classify_refusal "$tierpath" live origin/live)" in
            behind)
              # Nothing of ours to publish, and the remote holds facts this repo
              # does not. A push is attempt → take → attempt again (D49), so the
              # take happens here rather than being handed back as an errand:
              # the fast-forward is exactly what /gitlore:merge would do, and the
              # commits it takes are already on this remote, so the lockstep this
              # loop guarantees is untouched. A take that cannot fast-forward
              # yields a prepared merge and returns non-zero, as everywhere else.
              #
              # The whole take pass, not this tier alone: it runs root-first, and
              # a tier take writes a bookkeeping commit that would meet an
              # equally-behind root's upstream one as a divergence.
              GITLORE_TAKE_IN_PUSH=1 gitlore_merge_stores "$mempath" || return 1
              # The take can repair a defective arrival, committing on top of
              # what it fetched, and memory's push below records that commit —
              # so a `live` the remote does not already hold goes out now, for
              # the lockstep above (D17), and before a later tier's failure can
              # return 1 from the loop. A repair the same take made to a tier
              # whose iteration already finished is left to the post-loop pass
              # below; one to a later tier goes out with that tier's own push.
              if ! git -C "$tierpath" merge-base --is-ancestor live origin/live; then
                if ! tier_err=$(gitlore_git -C "$tierpath" push -q origin live 2>&1); then
                  gitlore_report_tier_push_failure "$tier" "$tier_err"
                  return 1
                fi
              fi
              continue
              ;;
            diverged)
              # One merge policy at every level: prepare against the tier's own
              # `origin/live` and yield, exactly as memory does below.
              gitlore_yield_merge "$tierpath" origin/live head-vs-remote live || return 1
              return 1
              ;;
            *)
              # Refused as non-fast-forward while `live` already contains
              # origin/live, or with a ref that could not be read. Nothing here
              # is a merge: preparing one against a stale authority would send
              # out a merge missing the work that caused the refusal.
              gitlore_report_tier_push_failure "$tier" "$tier_err"
              return 1
              ;;
          esac
          ;;
        *)
          gitlore_report_tier_push_failure "$tier" "$tier_err"
          ;;
      esac
      return 1
    fi
  done < <(gitlore_tier_paths "$mempath")

  # A take run mid-loop, while a different tier's own iteration was being
  # processed, can fetch and repair a tier whose iteration already finished —
  # committing on top of what it fetched, entirely in that tier's local
  # `live`, with no push of its own to send it out. One more pass over every
  # tier, before memory's remote is even considered (a memory kept local still
  # publishes every tier), catches anything left behind this way. The loop
  # above's own pushes already moved each tier's `origin/live`, so a tier
  # already out is not pushed again here.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    [ -e "$tierpath/.git" ] || continue
    git -C "$tierpath" rev-parse -q --verify live >/dev/null || continue
    if ! git -C "$tierpath" merge-base --is-ancestor live origin/live; then
      if ! tier_err=$(gitlore_git -C "$tierpath" push -q origin live 2>&1); then
        gitlore_report_tier_push_failure "$tier" "$tier_err"
        return 1
      fi
    fi
  done < <(gitlore_tier_paths "$mempath")

  # A memory store with no remote of its own is a supported end state, not a
  # broken install: `/gitlore:install` keeps the placeholder when no provider is
  # available, and a repo can share its tiers while keeping its project facts
  # local. Say so and stop, having published what there was to publish. Failing
  # instead would make memory's local-only-ness withhold the tiers — the one part
  # other repositories actually read.
  if [ -z "$remote_url" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory has no remote of its own, so it stays local; every mounted tier was published. Run /gitlore:resolve to give memory a remote if it is meant to be shared." \
      "gitlore: memory has no remote of its own, so it stays local; every mounted tier was published." >&2
    return 0
  fi

  # The same pre-publish invariant the tiers get, repaired the same way where it
  # is unambiguous: `live` is what goes out, HEAD is what the parent's gitlink
  # records.
  gitlore_repair_stranded_live "$mempath" "memory" || return 1
  gitlore_check_head_live_agree "$mempath" "memory" || return 1

  # No redirect: `-q` already silences progress, so anything fetch writes here is a
  # real problem. Non-fatal (`|| true`) — the push below is the operation that counts.
  git -C "$mempath" fetch -q origin live || true

  # Capture rather than discard the push error: the two branches below diagnose
  # only "unreachable" and "divergence", and a push can fail for neither reason
  # (protected branch, pre-receive rejection, bad credentials on a reachable host,
  # quota). Those used to land in the divergence branch and start a bogus merge
  # resolution with git's actual explanation thrown away. Keeping the text lets the
  # fall-through report the real cause.
  push_err=""
  if push_err=$(gitlore_git -C "$mempath" push -q origin live 2>&1); then
    return 0
  fi

  # Push failed. Distinguish unreachable from divergence. Provoking the error IS
  # the mechanism here — the question is only whether the remote answers at all —
  # so the redirect is the point rather than a swallowed message.
  if ! git -C "$mempath" ls-remote origin >/dev/null 2>&1; then
    gitlore_say_for_agent_or_user \
      "gitlore: memory remote unreachable. Check network or 'gh auth status'." \
      "gitlore: memory remote unreachable. Check network or 'gh auth status'." >&2
    return 1
  fi

  # Reachable, and the push was refused. Divergence is the only cause a merge can
  # fix; anything else (policy hook, protected branch, quota, credentials) is not,
  # and used to be misdiagnosed as divergence with git's explanation discarded.
  # The discriminator is git's parenthesized reason, verified against real output:
  #   divergence → " ! [rejected]        HEAD -> live (fetch first)"
  #                (or "(non-fast-forward)")
  #   policy     → " ! [remote rejected] HEAD -> live (pre-receive hook declined)"
  case "$push_err" in
    *"(fetch first)"*|*"(non-fast-forward)"*) ;;
    *)
      if [ -n "$push_err" ]; then
        gitlore_say_for_agent_or_user \
          "gitlore: pushing memory to its remote failed, and not because of divergence. git said:
$push_err" \
          "gitlore: pushing memory to its remote failed, and not because of divergence. git said:
$push_err" >&2
        return 1
      fi
      ;;
  esac

  # Reachable, and refused for an ancestry reason. Which one decides everything:
  # only divergence has a merge to prepare.
  case "$(gitlore_classify_refusal "$mempath" live origin/live)" in
    behind)
      # Every tier is published and memory has nothing of its own to send, while
      # the remote holds facts this clone lacks. Take them here rather than
      # reporting an errand (D49): the same fast-forward /gitlore:merge performs,
      # publishing nothing that was not already published. Every tier is already
      # reconciled by the loop above, so the root is all that is left to take.
      gitlore_merge_one_store "$mempath" "$mempath" "" || return 1
      return 0
      ;;
    diverged) ;;
    *)
      gitlore_say_for_agent_or_user \
        "gitlore: pushing memory was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$push_err" \
        "gitlore: pushing memory was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$push_err" >&2
      return 1
      ;;
  esac

  # HEAD-vs-remote divergence. Prepare and yield.
  gitlore_yield_merge "$mempath" origin/live head-vs-remote live || return 1
  return 1
}

# Words a failed tier push by git's parenthesized reason, the discriminator
# gitlore_push_stores applies to its own pushes. A refusal shaped like
# divergence (fetch first / non-fast-forward) reaches here only once ancestry
# has left nothing to merge, so it means the remote moved during the push, or
# the fetch before it failed; anything else is not divergence.
# Args: $1 = tier name, $2 = git's stderr from the failed push.
gitlore_report_tier_push_failure() {
  local tier="$1" tier_err="$2"
  case "$tier_err" in
    *"(fetch first)"*|*"(non-fast-forward)"*)
      gitlore_say_for_agent_or_user \
        "gitlore: pushing tier '$tier' was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$tier_err" \
        "gitlore: pushing tier '$tier' was refused as a non-fast-forward, but its local 'live' already contains the remote's. The remote moved during the push, or the fetch before it failed. git said:
$tier_err" >&2
      ;;
    *)
      gitlore_say_for_agent_or_user \
        "gitlore: pushing tier '$tier' failed, and not because of divergence. git said:
$tier_err" \
        "gitlore: pushing tier '$tier' failed, and not because of divergence. git said:
$tier_err" >&2
      ;;
  esac
}
