#!/usr/bin/env bash
# Diagnose and repair gitlore remote state. Detection order matches
# Section 6.2 of the spec. Idempotent: a healthy state produces no changes.
#
# The continue-after-merge functions live in lib/continuation.sh, sourced
# below; they set this script's own globals and exit on its behalf.
set -euo pipefail
unset CDPATH   # else `cd` may echo its target into the $(cd … && pwd) capture below

# The plugin root is the tree this script ships in, never a CLAUDE_PLUGIN_ROOT
# that may name another: a continuation invocation dispatched from a sub-agent
# is reached by path, and its shell may carry the variable of an older session.
PLUGIN_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PLUGIN_ROOT
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/continuation.sh"

# Subcommand dispatch (Plan 03 continuations).
if [ $# -ge 1 ]; then
  subcmd="$1"
  shift
  case "$subcmd" in
    continue-after-merge)
      load_continuation_state
      # A state file with no MERGE_HEAD is a merge a checkout cleared, or one
      # never run: a commit here has one parent and drops the pending side. The
      # guard's repair belongs to a run that re-briefs the merger: the default
      # run or /gitlore:merge's rerun. The directive printed here would read as
      # a merge landed and re-prepared.
      if ! git -C "$mempath" rev-parse -q --verify MERGE_HEAD >/dev/null; then
        echo "gitlore: $mempath holds a merge state file but no MERGE_HEAD, so nothing was committed and nothing was changed. Run /gitlore:resolve, which repairs the merge state." >&2
        exit 1
      fi
      # Compose before committing, so what lands is composed: a merge is the one
      # write path into a memory store that no compose trigger sees.
      compose_merged_indexes "$memroot" "$mempath"
      # Commit the merge. The authority is HEAD, so it is the first parent (D6),
      # and the message is canned rather than git's MERGE_MSG: a merge whose two
      # sides both passed an approval gate needs no prompt, and the subject that
      # serves every consumer of a shared store names the repos rather than the
      # refs (D49). The message goes in a file so `git commit -F` reads it.
      merge_msgfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-merge-msg.XXXXXX") \
        || {
          echo "gitlore: the merge message file could not be created, so the merge was not committed; the merge stays prepared." >&2
          exit 1
        }
      # Each failure exit here keeps MERGE_HEAD and the merge state, so a rerun
      # lands it; only the message file is this run's to remove, and a failed
      # mktemp above created none. Each `||` group below removes it first:
      # errexit stays armed there, so a failing write to stderr would skip
      # whatever follows it and leave the scratch file behind.
      gitlore_merge_commit_message "$memroot" "$mempath" > "$merge_msgfile" \
        || {
          rm -f "$merge_msgfile"
          echo "gitlore: the merge message could not be built, so the merge was not committed; the merge stays prepared." >&2
          exit 1
        }
      gitlore_git -C "$mempath" commit -q -F "$merge_msgfile" \
        || {
          rm -f "$merge_msgfile"
          echo "gitlore: the merge commit was refused, so the merge was not committed; the merge stays prepared." >&2
          exit 1
        }
      rm -f "$merge_msgfile"
      gitlore_clear_merge_state "$mempath"
      gitlore_git -C "$mempath" update-ref -d "$GITLORE_PENDING_REF"
      # Restore the invariant: fast-forward local `live` onto the merge commit.
      # It can lose a race with a concurrent advance; re-prepare against `live`
      # and yield again. The merge reaches a remote only through /gitlore:push.
      rc=0; push_or_report "$mempath" . HEAD:live || rc=$?
      if [ "$rc" -eq 1 ]; then
        gitlore_yield_merge "$mempath" live head-vs-live HEAD || :
      fi
      [ "$rc" -eq 0 ] || exit 1
      echo "gitlore: merged without publishing. Run /gitlore:push to publish." >&2
      exit 0
      ;;
    abort-merge)
      # The memory root's prepared merge, as SessionStart's mid-merge report
      # names it: back to the commit the preparation started from.
      gitlore_has_submodule || { echo "gitlore: not installed in this repo." >&2; exit 1; }
      gitlore_abort_prepared_merge "$(gitlore_memory_path)" || exit 1
      exit 0
      ;;
    revert-pin)
      # A tier gitlink no repository holds, as the default run below names it.
      [ $# -eq 1 ] || { echo "gitlore: revert-pin takes one tier path." >&2; exit 2; }
      gitlore_has_submodule || { echo "gitlore: not installed in this repo." >&2; exit 1; }
      gitlore_revert_lost_pin "$(gitlore_memory_path)" "$1" || exit 1
      exit 0
      ;;
    *)
      echo "gitlore: unknown resolve subcommand: $subcmd" >&2
      exit 2
      ;;
  esac
fi

# Default mode: detect. The head-vs-live gate publishes HEAD to the store's own
# local `live`; the remote gate only compares `live` with the remote's and
# reports. Publishing to a remote is /gitlore:push's business. Yield on the
# first divergence; continuations re-enter from the hook (commit/push retries),
# not from here.

gitlore_has_submodule || {
  gitlore_say_for_agent_or_user \
    "gitlore: not installed in this repo. Run /gitlore:install." \
    "gitlore: not installed in this repo. Open this project in Claude Code and run /gitlore:install." >&2
  exit 1
}
mempath=$(gitlore_memory_path)
any_report=""

# Existing Plan 02 simple repairs (remote.origin.url, ls-remote, push live)
# happen first — they precede semantic-merge detection.
remote_url=$(git -C "$mempath" config --get remote.origin.url || true)
if [ -z "$remote_url" ] || gitlore_is_placeholder_url "$remote_url"; then
  echo "gitlore: no memory remote configured. Creating one." >&2
  bash "$PLUGIN_ROOT/scripts/install/create-remote.sh" "$mempath"
  echo "gitlore: memory remote created and live pushed." >&2
  # Fall through rather than exiting: a repair to memory says nothing about the
  # tiers, and stopping here would leave a diverged tier undetected.
fi
if ! ls_remote_err=$(git -C "$mempath" ls-remote origin 2>&1 >/dev/null); then
  printf '%s\n' "$ls_remote_err" >&2
  gitlore_say_for_agent_or_user \
    "gitlore: memory remote unreachable. $(gitlore_push_credentials_hint "$mempath")" \
    "gitlore: memory remote unreachable. $(gitlore_push_credentials_hint "$mempath")" >&2
  exit 1
fi

# Both gates for one store: local `live` first (cheaper, local-only), then the
# remote's. No branch guard is needed at either level — every store is checked
# out detached, so `HEAD:live` is always the right question and is a silent
# no-op when HEAD is already there. Yields and exits on the first divergence;
# `commands/resolve.md` re-runs this script until it exits 0, which is what
# walks the remaining gates and stores. A store whose `live` is ahead of or
# behind its remote is reported and the run goes on; the report sets
# `any_report`, which keeps the healthy line from following it.
check_store_gates() {
  # `tier` is the store's tier name, empty for the memory root: the head-vs-live
  # gate's remedy differs by store kind, because a tier is pinned at the gitlink
  # the memory store records (D43) and the root is not.
  local store="$1" tier="${2-}" rc fetch_err remote_live local_live absent=""
  local name="memory"
  [ -z "$tier" ] || name="tier '$tier'"
  rc=0; push_or_report "$store" . HEAD:live || rc=$?
  if [ "$rc" -eq 2 ]; then
    exit 1
  elif [ "$rc" -eq 1 ]; then
    # git refuses a merely-BEHIND ref with the same wording as a genuinely
    # diverged one; only ancestry tells them apart. Same discriminator every
    # other yield site applies (gitlore_sync_tiers_to_live et al.) — this was
    # the one call site that skipped it and routed straight into a merge
    # prepare against a store with nothing to merge.
    if [ "$(gitlore_classify_refusal "$store" HEAD live)" = "diverged" ]; then
      gitlore_yield_merge "$store" live head-vs-live HEAD || exit 1
      exit 1
    elif gitlore_check_head_live_agree "$store" "$store" "$tier"; then
      gitlore_say_for_agent_or_user \
        "gitlore: pushing HEAD to $store's local 'live' was refused, though HEAD and 'live' agree and neither has diverged." \
        "gitlore: pushing HEAD to $store's local 'live' was refused, though HEAD and 'live' agree and neither has diverged." >&2
      exit 1
    else
      exit 1
    fi
  fi
  # The remote gate, after the local one: this store's unreachable remote does
  # not hide its own local divergence, which the local gate prepares without
  # it. (Memory's reachability probe above, and an earlier store's failed fetch,
  # still end the run before a later store's local gate.) A remote with no `live`
  # yet is the expected first-publish state: the fetch says so, and that line
  # is matched here rather than shown. Any other fetch failure leaves the
  # remote's state unknown, so the run stops on git's reason rather than
  # compare against a stale tracking ref.
  if ! fetch_err=$(gitlore_git -C "$store" fetch -q --no-recurse-submodules origin live 2>&1); then
    case "$fetch_err" in
      *"couldn't find remote ref"*) absent=yes ;;
      *)
        printf '%s\n' "$fetch_err" >&2
        gitlore_say_for_agent_or_user \
          "gitlore: fetching $name's remote 'live' failed, and not because the remote has none, so its state is unknown. git said it above." \
          "gitlore: fetching $name's remote 'live' failed, and not because the remote has none, so its state is unknown. git said it above." >&2
        exit 1
        ;;
    esac
  fi
  # A remote with no `live` holds nothing the local one lacks.
  # Otherwise equality is checked first: the refusal classifier reads equal as
  # behind.
  if [ -n "$absent" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: $name is ahead of its remote. Run /gitlore:push to publish it." \
      "gitlore: $name is ahead of its remote. Run /gitlore:push to publish it." >&2
    any_report=yes
    return 0
  fi
  remote_live=$(git -C "$store" rev-parse -q --verify refs/remotes/origin/live || true)
  local_live=$(git -C "$store" rev-parse -q --verify refs/heads/live || true)
  if [ -n "$remote_live" ] && [ "$remote_live" = "$local_live" ]; then
    return 0
  fi
  case "$(gitlore_classify_refusal "$store" refs/heads/live refs/remotes/origin/live)" in
    ahead)
      gitlore_say_for_agent_or_user \
        "gitlore: $name is ahead of its remote. Run /gitlore:push to publish it." \
        "gitlore: $name is ahead of its remote. Run /gitlore:push to publish it." >&2
      any_report=yes
      ;;
    behind)
      # Nothing of ours to publish — the remote is ahead, which is
      # /gitlore:merge's business.
      gitlore_say_for_agent_or_user \
        "gitlore: $name has nothing to publish — its remote 'live' is ahead of the local one. Run /gitlore:merge to take those facts." \
        "gitlore: $name has nothing to publish — its remote 'live' is ahead of the local one. Run /gitlore:merge to take those facts." >&2
      any_report=yes
      ;;
    diverged)
      gitlore_yield_merge "$store" origin/live head-vs-remote live || exit 1
      exit 1
      ;;
    *)
      # A ref that cannot be read is no classification; a merge prepared on
      # it would be a guess.
      gitlore_say_for_agent_or_user \
        "gitlore: could not tell how $name's 'live' relates to its remote's: one of the two refs cannot be read. No merge was prepared." \
        "gitlore: could not tell how $name's 'live' relates to its remote's: one of the two refs cannot be read. No merge was prepared." >&2
      exit 1
      ;;
  esac
}

# A half-finished merge anywhere is the first thing to report: pushing on top of
# one is exactly what the guard exists to prevent.
while IFS= read -r store; do
  gitlore_guard_stale_merge_state "$store" || exit 1
done < <(gitlore_memory_stores "$mempath")

# A recorded commit no repository holds is an integrity error, not a state to
# call healthy, and it goes before the gates so no push publishes past it.
gitlore_resolve_check_pins "$mempath" || exit 1

# Every mounted tier, through the identical pair of gates — one merge policy at
# every level — and before memory's: detection keeps the order
# gitlore_push_stores publishes in, so the divergence it yields is the one a
# push would meet first (D17: memory's commit records each tier's). A tier with
# no remote has nothing to reconcile yet; `pre-push` is where a missing tier
# remote is fatal, because that is the point at which its absence starts losing
# writes. A tier this checkout did not mount has no local `live`, yet its HEAD
# can hold commits memory records: `gitlore_ensure_live` gives it one from HEAD.
while IFS= read -r store; do
  if [ "$store" = "$mempath" ]; then continue; fi
  [ -n "$(git -C "$store" config --get remote.origin.url || true)" ] || continue
  gitlore_ensure_live "$store" || exit 1
  # Every store under `$mempath` is a tier; the root is handled below.
  check_store_gates "$store" "${store##*/}"
done < <(gitlore_memory_stores "$mempath")

check_store_gates "$mempath"

[ -n "$any_report" ] || echo "gitlore: state is healthy. Nothing to do." >&2
exit 0
