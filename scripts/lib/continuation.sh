#!/usr/bin/env bash
# The continuation-after-merge functions dispatched by
# `resolve.sh continue-after-merge`: load the prepared merge state, compose
# and adopt it into the root index, rest a tier the root could not adopt,
# and push-with-divergence-routing. Sourced by scripts/resolve.sh only; its
# functions set that script's globals (mempath, memroot, statefile, flavor,
# publish, merged_tier, tier_unadopted) and exit on its behalf.
# Part of scripts/resolve.sh; source that, not this file.

# Load shared continuation state: require an installed submodule and exactly one
# prepared merge, then set mempath/statefile/flavor/publish for the caller.
#
# The store is FOUND, not derived. Memory and every tier share one merge policy
# and one state-file name resolved inside their own gitdirs, so a continuation
# that assumed `gitlore_memory_path` would commit in memory while the prepared
# merge sat in a tier. The search walks the same store list the gates do, and
# `mempath` comes from the state file's own `store` field — absolute, so it does
# not depend on where the continuation was invoked from.
load_continuation_state() {
  gitlore_has_submodule || { echo "gitlore: not installed" >&2; exit 1; }
  local found
  # The memory ROOT, kept apart from `mempath`: composition spans the whole
  # memory tree, so it is anchored here even when the merge sits in a tier.
  memroot=$(gitlore_memory_path)
  found=$(gitlore_stores_with_merge_state "$memroot")
  if [ -z "$found" ]; then
    echo "gitlore: no merge state file in memory or any tier" >&2
    exit 1
  fi
  # A gate yields on the first divergence and stops, so two prepared merges mean
  # the state is not what any continuation assumes. Refusing beats guessing which
  # one this invocation meant.
  if [ "$(printf '%s\n' "$found" | wc -l)" -gt 1 ]; then
    echo "gitlore: merges are prepared in more than one store, which should not happen:" >&2
    printf '%s\n' "$found" | sed 's/^/gitlore:   /' >&2
    echo "gitlore: land or abort one of them before continuing." >&2
    exit 1
  fi
  statefile=$(gitlore_merge_state_file "$found")
  mempath=$(jq -r '.store // ""' "$statefile")
  if [ -z "$mempath" ] || [ ! -e "$mempath/.git" ]; then
    echo "gitlore: merge state at $statefile does not name a usable store." >&2
    exit 1
  fi
  flavor=$(jq -r .flavor "$statefile")
  # `// ""` covers a state file written before the field existed, and jq's own
  # `null` for a key present but empty: both mean "publish", the gate default.
  publish=$(jq -r '.publish // ""' "$statefile")
}

# Adopt a merged tier into the root index: project the merged carrier UP, so
# root's block for that tier becomes what the merge produced.
#
# This is the step that makes a tier merge reach the surface CC recalls from. A
# tier is pinned at its gitlink and composition projects the ROOT down, so
# nothing else would ever move the merged lines into root — the in-session pass
# would read them as carrier lines root chose not to carry, keep them where they
# are, and report them. The adoption is also the one moment a carrier outranks
# root's text: it is the artifact the user just approved, line by line.
#
# Once, here, and in this direction only. Projecting down would write a carrier
# the user never reviewed as a side effect of approving this merge.
#
# A memory-store merge adopts nothing: root's own `MEMORY.md` is one of the files
# git merged, so the propagation is already in the merged content. The pass still
# runs, with no tier named — the merge produced whatever order the two sides
# implied, and the layout, the four validations and the dangling report all still
# have something to say about it.
#
# A refusal blocks the merge only when it targets the index the merge is about
# to publish: a problem gitlore_compose_check attributes to the merged carrier
# (tier merge) or to root's own MEMORY.md under rules 1, 4 and 6 (memory-root
# merge) means that text fails its own check, so nothing is staged and the
# merge stays prepared for a new synthesis. Every other refusal still lands:
# compose is fail-safe (it writes nothing), and the merge is synthesized and
# approved by this point — stranding it half-landed over a problem elsewhere in
# the store is the worse outcome. Report, then commit what the merger produced.
# A tier the root could not adopt is the one case the report is not the whole
# answer: the root must then record nothing of the merge, so this sets
# `tier_unadopted` and stages nothing in the root.
# Sets two variables for the caller. `merged_tier`: the store's path relative to
# the memory root, or empty when the merge is memory's own; the continuation
# needs it after the commit to stage the moved gitlink, and this is where it is
# already derived. `tier_unadopted`: 1 when a tier merge's up projection failed,
# after emitting, and empty otherwise.
# EXITS 1, before staging anything, when the merge fails its own check (see
# above; a store with no root index runs no check), with the merge state kept
# for a new synthesis — an exit rather than a
# return, because the caller cannot check a status without an `||` on the call.
# Returns 0 otherwise. A failed staging command aborts the continuation under
# errexit, before the merge commit, which keeps the merge state for a rerun —
# with git's own text on stderr and no `gitlore:` line of its own. The caller
# calls it bare: an `||` on the call would suspend errexit across the whole
# body, and a failed `add` would then read as a tier the root could not adopt.
# Args: $1 = memory root worktree path, $2 = the store being committed.
compose_merged_indexes() {
  local memroot="$1" store="$2" memroot_abs composed dangling merged_index index_problems rc=0
  merged_tier=""
  tier_unadopted=""
  # The state file records an absolute store path while `memroot` is the
  # submodule path as `.gitmodules` spells it, so the two are compared in one
  # form. `-ef` rather than string equality: this decides whether a tier is
  # adopted at all, and a path spelled two ways would adopt a tier named after
  # the memory root itself.
  memroot_abs=$(CDPATH='' cd -- "$memroot" && pwd) || memroot_abs="$memroot"
  if ! [ "$store" -ef "$memroot" ]; then
    merged_tier=${store#"$memroot_abs"/}
    if [ "$merged_tier" = "$store" ]; then
      merged_tier=""
      echo "gitlore: the merged store $store is not inside the memory root $memroot_abs; the root index was left uncomposed." >&2
      gitlore_git -C "$store" add -A
      return 0
    fi
  fi

  composed=$(gitlore_compose_up "$memroot" "$merged_tier") || rc=$?
  index_problems=""
  if [ "$rc" -eq 1 ]; then
    merged_index="$memroot/MEMORY.md"
    [ -n "$merged_tier" ] && merged_index="$memroot/$merged_tier/MEMORY.md"
    index_problems=$(gitlore_compose_problems_in "$merged_index" <<<"$composed") \
      || index_problems=""
  fi
  # What the gate just read, into the merge state, on every run of it — the
  # empty answer included. The lines below reach only whoever ran this
  # continuation, and a merge is routinely met again by a session that never saw
  # them; recorded, every later directive emits them. Recording the empty answer
  # is what keeps a merge kept prepared for some other reason from briefing the
  # next sub-agent against an objection a synthesis has already cleared.
  gitlore_record_merge_index_problems "$store" "$index_problems" \
    || echo "gitlore: the merged-index check could not be written into the merge state in $store, so a directive emitted for this merge later will not carry its lines. Read them below instead." >&2
  if [ -n "$index_problems" ]; then
    echo "gitlore: the merged index fails the check, so the merge was not committed; the merge stays prepared for a new synthesis:" >&2
    printf '%s\n' "$index_problems" | sed 's/^/gitlore:   /' >&2
    exit 1
  fi
  if [ "$rc" -eq 0 ]; then
    [ -n "$composed" ] && printf '%s\n' "$composed" | sed 's/^/gitlore: /' >&2
    # The dangling pass reports rather than refuses, so it runs on the composed
    # store and speaks whether or not composition wrote anything.
    dangling=$(gitlore_compose_dangling "$memroot")
    if [ -n "$dangling" ]; then
      echo "gitlore: these index lines name files that are not there. Nothing was rewritten or deleted:" >&2
      printf '%s\n' "$dangling" | sed 's/^/gitlore:   /' >&2
    fi
  elif [ -n "$merged_tier" ]; then
    # A tier the root index could not adopt: the merge still lands, but the root
    # records none of it — see rest_unadopted_tier for why, and for the remedy
    # printed once the merge has landed.
    echo "gitlore: the root index could not take tier '$merged_tier''s lines — the merge is being committed in the tier, and the memory store will record none of it:" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
    gitlore_git -C "$store" add -A
    tier_unadopted=1
    return 0
  elif [ "$rc" -eq 2 ]; then
    echo "gitlore: the root index could not be written — the merge is being committed uncomposed. Investigate the path named below, then edit MEMORY.md to retrigger composition:" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
  else
    echo "gitlore: tier composition refused — the merge is being committed uncomposed. Fix the store by hand, then edit MEMORY.md to retrigger it:" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
  fi
  # The merger already ran `git add -A` in the store being committed; re-running
  # it is how anything written there joins the same commit. Then the root index,
  # which for a tier merge lives in a DIFFERENT store: staging it there is what
  # puts it in the next FR11 commit rather than leaving it as an unexplained
  # working-tree change. For a memory merge the two calls are the same repo, and
  # the second is what stages the compose write the first ran too early to see.
  gitlore_git -C "$store" add -A
  # A store with no root index — migrated from an auto-memory dir that held no
  # MEMORY.md, or one whose index was deleted by hand — has nothing to stage;
  # gitlore_compose_up returned 0 for it above without running the check, so
  # the gate that keeps a failing merged index unlanded never ran either, and
  # the merge must not be blocked on it. Say so: nothing composes up into a
  # root index that does not exist, and that is the store's defect, not the
  # merge's.
  if [ -f "$memroot/MEMORY.md" ]; then
    gitlore_git -C "$memroot" add -- MEMORY.md
  else
    echo "gitlore: the memory root $memroot_abs has no MEMORY.md, so no tier lines can compose into it. The merge is committed regardless; create the root index (\`# Memory Index\`) and edit it to trigger composition." >&2
  fi
}

# Rest a landed tier merge the root index could not adopt: the tier back on the
# commit the memory store records, the merge kept in its local `live`.
#
# The same resting state a failed take leaves (gitlore_adopt_tier_into_root),
# for the same reasons. Staging the moved gitlink alone puts the tier on its pin
# while root still holds the older block, so the next compose writes that older
# text over the merged carrier and reports success (D50). Leaving the tier on
# the merge commit ahead of an unstaged pin has the pin guard refuse every
# memory commit. On the pin with `live` ahead is the shape
# gitlore_adopt_advanced_live adopts, so fixing the store and running the take
# retries the adoption. The checkout loses nothing: the merge commit holds
# everything the merger staged, and the up projection writes no carrier.
#
# Only onto a pin the merge contains. A pin off to the side is not this merge's
# base, and checking it out would put the tier on history the merge never built
# on; the tier stays on the merge, and the pin guard names that case's remedy.
#
# Only when the tier's local `live` already holds the merge. A refused local
# `HEAD:live` push reaches here with `live` still short of HEAD; checking out
# the pin then would strand the merge reachable only through the reflog, so
# this leaves the tier on the merge commit instead and prints the two commands
# that push `live` up to it and then repeat this rest by hand. The second one
# re-asks the same ancestry question, so run after a push refused again it
# leaves the tier where it is.
#
# Exit status stays the caller's either way: the merge landed, which is what
# the continuation reports, and the next take or resolve run fails on this
# state with the remedy printed here.
# Args: $1 = memory root worktree path, $2 = tier name.
rest_unadopted_tier() {
  local memroot="$1" tier="$2" tierpath pin merged err abs
  tierpath="$memroot/$tier"
  abs=$(CDPATH='' cd -- "$tierpath" && pwd) || abs="$tierpath"
  merged=$(git -C "$tierpath" rev-parse HEAD)
  # `-q --verify` on both reads: no gitlink in the index at all, or a pin that is
  # no object in this tier's database, are the expected misses, and each means
  # the pin is not an ancestor.
  if ! pin=$(git -C "$memroot" rev-parse -q --verify ":$tier") \
     || ! git -C "$tierpath" rev-parse -q --verify "${pin}^{commit}" >/dev/null \
     || ! git -C "$tierpath" merge-base --is-ancestor "$pin" "$merged"; then
    echo "gitlore: tier '$tier' stays on the merge commit: the commit the memory store records for it is not one the merge contains. The next memory commit refuses that pin and names the remedy." >&2
    return 0
  fi
  if ! git -C "$tierpath" rev-parse -q --verify live >/dev/null \
     || ! git -C "$tierpath" merge-base --is-ancestor HEAD live; then
    printf 'gitlore: tier '\''%s'\'' stays on the merge commit because its local '\''live'\'' does not hold it. Run:\ngitlore:   git -C "%s" push . HEAD:live\ngitlore:   git -C "%s" merge-base --is-ancestor HEAD live && git -C "%s" checkout --detach %s\ngitlore: then fix the problems listed above and run /gitlore:merge.\n' \
      "$tier" "$abs" "$abs" "$abs" "$pin" >&2
    return 0
  fi
  if ! err=$(gitlore_git -C "$tierpath" checkout -q --detach "$pin" 2>&1); then
    # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
    printf 'gitlore: tier '\''%s'\'' could not be returned to the commit the memory store records. git said:\n%s\ngitlore: run `git -C "%s" checkout --detach %s`, fix the store, then run /gitlore:merge to adopt the merge into the root index.\n' \
      "$tier" "$err" "$abs" "$pin" >&2
    return 0
  fi
  echo "gitlore: tier '$tier' is back on the commit the memory store records; its local 'live' keeps the merge. Fix the store, then run /gitlore:merge to adopt the merge into the root index." >&2
}

# Fast-forward a ref with `push`, routing a refusal by its cause. Returns 0 on
# success; returns 1 when git's parenthesized reason says the ref diverged,
# which is the caller's cue to prepare a merge; reports git's own explanation
# and returns 2 on any other refusal — a protected branch, a pre-receive
# decline, a bad credential, a full quota. Never exits, so a caller holding a
# landed tier merge can rest that tier before it exits on a status-2 refusal.
#
# The same discriminator `pre-push` and `gitlore_sync_memory_to_live` apply, and
# for the same reason: only divergence is something a merge can fix. Without it
# a policy refusal prepares a merge that cannot help — and this script is where
# the user lands *after* pre-push has correctly told them the push failed for a
# reason other than divergence, so it is the last place that should re-diagnose
# it as one.
#
# An empty message is treated as divergence, matching the memory gate: `push -q`
# names its rejection reason, so silence here means the refusal carried no text
# to route on and the local `HEAD:live` case is the only cause left.
# Args: $1 = store worktree, $2… = push arguments (remote and refspec).
push_or_report() {
  local store="$1"; shift
  local push_err
  if push_err=$(gitlore_git -C "$store" push -q "$@" 2>&1); then
    return 0
  fi
  case "$push_err" in
    *"(fetch first)"*|*"(non-fast-forward)"*) return 1 ;;
    *) [ -n "$push_err" ] || return 1 ;;
  esac
  gitlore_say_for_agent_or_user \
    "gitlore: pushing '$*' in $store failed, and not because of divergence — no merge can fix this. git said:
$push_err" \
    "gitlore: pushing '$*' in $store failed, and not because of divergence — no merge can fix this. git said:
$push_err" >&2
  return 2
}
