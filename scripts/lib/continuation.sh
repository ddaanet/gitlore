#!/usr/bin/env bash
# The continuation-after-merge functions dispatched by
# `resolve.sh continue-after-merge`: load the prepared merge state, gate and
# compose what is about to land, and push-with-divergence-routing. Sourced by
# scripts/resolve.sh only; its functions set that script's globals (mempath,
# memroot, statefile, flavor, publish) and exit on its behalf.
# Part of scripts/resolve.sh; source that, not this file.
#
# File-wide: flavor and publish are read by scripts/resolve.sh, which shellcheck
# cannot see from here.
# shellcheck disable=SC2034

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

# Gate and stage what a landing merge commits.
#
# A tier merge composes nothing: its carrier is checked on its own, and the end of
# the gitlore-merge or push run that follows writes root and records the tier. A
# carrier failing its own check is not landed (D52).
#
# A memory-store merge composes up, before its commit, every tier whose HEAD is
# ahead of the gitlink HEAD (OURS) records: root's own `MEMORY.md` is one of the
# files git merged, but a carrier line neither side of root held reaches it only
# here, three-way from that gitlink. The layout, the validations and the
# dangling report all still have something to say about the merged root too. A
# line both the merged root and the tier changed apart takes the tier's, and is
# reported on stderr: the base is read from OURS, which cannot record that root
# has seen the tier's version until the merge commits, so a chunk there would
# recur on every rerun.
#
# A refusal blocks a memory merge only when it targets the index the merge is about
# to publish: a problem gitlore_compose_check attributes to root's own MEMORY.md
# under rules 1, 4 and 6 means that text fails its own check, so nothing is staged
# and the merge stays prepared for a new synthesis. Every other refusal still
# lands: compose is fail-safe (it writes nothing), and the merge is synthesized and
# approved by this point — stranding it half-landed over a problem elsewhere in the
# store is the worse outcome. Report, then commit what the merger produced.
# EXITS 1, before composing or staging anything, in two cases, each with the
# merge state kept for a new synthesis: a file the merge changed still holds
# conflict markers (refuse_leftover_conflict_markers), and the merged index fails
# its own check (see above; a store with no root index runs no check). An exit
# rather than a return, because the caller cannot check a status without an `||`
# on the call.
# Returns 0 otherwise. A failed staging command aborts the continuation under
# errexit, before the merge commit, which keeps the merge state for a rerun —
# with git's own text on stderr and no `gitlore:` line of its own. The caller
# calls it bare, because an `||` on the call would suspend errexit across the
# whole body.
# Args: $1 = memory root worktree path, $2 = the store being committed.
compose_merged_indexes() {
  local memroot="$1" store="$2" memroot_abs merged_tier="" composed dangling index_problems rc=0
  # First, ahead of the compose write and of every `add -A` below: the scan reads
  # the working tree those calls stage, and a refusal must leave root's index as
  # it was.
  refuse_leftover_conflict_markers "$store"
  # The state file records an absolute store path while `memroot` is the
  # submodule path as `.gitmodules` spells it, so the two are compared in one
  # form. `-ef` rather than string equality: this decides whether the merge is a
  # tier's at all, and a path spelled two ways would read the memory root as a
  # tier named after itself.
  memroot_abs=$(CDPATH='' cd -- "$memroot" && pwd) || memroot_abs="$memroot"
  if ! [ "$store" -ef "$memroot" ]; then
    merged_tier=${store#"$memroot_abs"/}
    if [ "$merged_tier" = "$store" ]; then
      echo "gitlore: the merged store $store is not inside the memory root $memroot_abs; the root index was left uncomposed." >&2
      gitlore_git -C "$store" add -A
      return 0
    fi
  fi

  index_problems=""
  if [ -n "$merged_tier" ]; then
    if [ -f "$memroot/$merged_tier/MEMORY.md" ]; then
      index_problems=$(gitlore_compose_check_index "$memroot/$merged_tier/MEMORY.md")
    fi
  else
    # HEAD still records OURS here, and the tiers the prepare staged at their
    # HEADs read as on their pins once the merge commit lands, so the tiers
    # ahead of what OURS records compose now or never.
    composed=$(gitlore_compose_up "$memroot" "$(gitlore_tiers_off_pin "$memroot" HEAD:)" HEAD: tier-wins) || rc=$?
    if [ "$rc" -eq 1 ] || [ "$rc" -eq 3 ]; then
      index_problems=$(gitlore_compose_problems_in "$memroot/MEMORY.md" <<<"$composed") \
        || index_problems=""
    fi
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
  if [ -n "$merged_tier" ]; then
    gitlore_git -C "$store" add -A
    return 0
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
  elif [ "$rc" -eq 2 ]; then
    echo "gitlore: the root index could not be written — the merge is being committed uncomposed. Investigate the path named below, then edit MEMORY.md to retrigger composition:" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
  else
    echo "gitlore: tier composition refused — the merge is being committed uncomposed. Fix the store by hand, then edit MEMORY.md to retrigger it:" >&2
    printf '%s\n' "$composed" | sed 's/^/gitlore:   /' >&2
  fi
  # The merger already ran `git add -A` in this store; re-running it is what stages
  # the compose write it ran too early to see.
  gitlore_git -C "$store" add -A
  # A store with no root index — migrated from an auto-memory dir that held no
  # MEMORY.md, or one whose index was deleted by hand — has nothing to stage;
  # gitlore_compose_up returned 0 for it above without running the check, so
  # the gate that keeps a failing merged index unlanded never ran either, and
  # the merge must not be blocked on it. Say so: nothing composes up into a
  # root index that does not exist, and that is the store's defect, not the
  # merge's.
  if [ ! -f "$memroot/MEMORY.md" ]; then
    echo "gitlore: the memory root $memroot_abs has no MEMORY.md, so no tier lines can compose into it. The merge is committed regardless; create the root index (\`# Memory Index\`) and edit it to trigger composition." >&2
  fi
}

# Refuse to commit a merge whose files still hold conflict markers.
#
# The merger stages by explicit path, so the continuation's own `add -A` is what
# would mark a conflict git left in an unstaged path as resolved, and what would
# commit markers the merger staged. The scan therefore reads the working tree
# against HEAD, plus untracked files, and not the index. Only files the merge
# changed are read: a file both sides carried unchanged may document markers.
# Deleted paths and tier gitlinks are not files and are skipped. A line of
# `<<<<<<<` or `>>>>>>>` followed by a space or the end of the line at column 0
# counts; `=======` is left out because a markdown heading underline is the same
# text. A merge-changed file that documents markers at column 0 is refused too.
#
# EXITS 1 naming each file, with the merge state kept and its recorded index
# problems emptied. The refusal runs before the index gate, so it has no verdict
# on this synthesis; it empties the field so that no earlier verdict is carried
# onto a synthesis nobody checked, and the next run checks the index and records
# what it finds. Empty after this refusal means unchecked, not clean. An exit
# rather than a return, for the reason compose_merged_indexes gives. A failing
# `git` inside the listing is not seen; the scan then covers what it did list.
# Args: $1 = the store being committed.
refuse_leftover_conflict_markers() {
  local store="$1" f marked=""
  while IFS= read -r -d '' f; do
    [ -f "$store/$f" ] || continue
    if grep -qE '^(<<<<<<<|>>>>>>>)( |$)' "$store/$f"; then
      marked="$marked$f"$'\n'
    fi
  done < <(git -C "$store" diff -z --name-only HEAD
           git -C "$store" ls-files -z -o --exclude-standard)
  [ -n "$marked" ] || return 0
  # Empty means unchecked here, not clean: this refusal comes before the index
  # gate, so it has no verdict on this synthesis, and it empties the field so
  # that no earlier verdict is carried onto a synthesis nobody checked.
  gitlore_record_merge_index_problems "$store" "" \
    || echo "gitlore: the merged-index check could not be cleared in the merge state in $store, so a directive emitted for this merge later may carry lines a new synthesis has already cleared." >&2
  echo "gitlore: these files still hold conflict markers, so the merge was not committed; the merge stays prepared for a new synthesis:" >&2
  printf '%s' "$marked" | sed 's/^/gitlore:   /' >&2
  exit 1
}

# Fast-forward a ref with `push`, routing a refusal by its cause. Returns 0 on
# success; returns 1 when git's parenthesized reason says the ref diverged,
# which is the caller's cue to prepare a merge; reports git's own explanation
# and returns 2 on any other refusal — a protected branch, a pre-receive
# decline, a bad credential, a full quota. Never exits.
#
# The same discriminator `pre-push` and `gitlore_sync_memory_to_live` apply, and
# for the same reason: only divergence is something a merge can fix. Without it
# a policy refusal prepares a merge that cannot help — and this script is where
# the user lands *after* pre-push has correctly told them the push failed for a
# reason other than divergence, so it is the last place that should re-diagnose
# it as one.
#
# An empty message is treated as divergence: `push -q`
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
