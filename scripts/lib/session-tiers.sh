#!/usr/bin/env bash
# The nested-tiers sync stage of session-start.sh (D17 3-i-a). Sourced by
# session-start.sh only; its one function takes the memory path as its
# argument and calls session-start.sh's own `add_sysmsg`, and appends
# directly to its `$protocol_ctx` global — neither declared here, both left
# for session-start.sh to emit.

# Check each tier submodule inside the memory store out at the commit the
# memory tree records for it. Discovery is by enclosure — every entry in
# memory/.gitmodules is a tier. Tiers use the detached branch model (D17): no
# named working branch.
#
# A tier is PINNED at its gitlink and never fast-forwarded here. One memory
# commit records `MEMORY.md` and the tier gitlink together, so root's tier
# block and the carrier index it projects are consistent by construction;
# advancing the tier behind root's back breaks that pairing, and nothing
# downstream can repair it — composition places lines, it does not merge
# them. Taking an upstream commit is a merge, and it goes through
# /gitlore:merge or /gitlore:push.
#
# Every git call is guarded: a broken tier must never abort the session.
# Args: $1 = mempath.
gitlore_sync_nested_tiers() {
  local mempath="$1"
  local tier tierpath fetch_err tier_head tier_remote
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # A prepared merge is detected FIRST, before anything that checks out. `git
    # checkout` — which `submodule update` runs — calls remove_branch_state(),
    # unlinking MERGE_HEAD and MERGE_MSG silently and on success; a clean
    # auto-merge stages no unmerged entries, so even a no-op re-checkout of the
    # commit HEAD is already on succeeds and destroys the merge pointers while
    # leaving the staged result behind. What survives is a state file with no
    # MERGE_HEAD, which gitlore_recover_stale_no_merge_head can repair — by
    # writing the pointers back — but only by reading the index to decide how, and
    # a session start that provokes the damage every time makes that repair the
    # normal path rather than the recovery it is. Skip the whole tier, and say
    # so — a suppressed pass must not be silent, or the tier looks synced when it
    # is mid-merge.
    # `detect` rather than `guard_stale_merge_state`: the guard's directive tells
    # the agent to abort and retry, which is wrong for a merge that is simply
    # waiting to be landed, and it writes to stderr, which SessionStart does not
    # show the user (D14).
    # The `.git` test leads: `git -C` into an unchecked-out submodule path walks up
    # to the enclosing repo, so an unmaterialized tier would be answered for by
    # memory's own merge state.
    if [ -e "$tierpath/.git" ] \
       && { [ "$(gitlore_detect_stale_merge_state "$tierpath")" != "clean" ] \
            || git -C "$tierpath" rev-parse -q --verify MERGE_HEAD >/dev/null; }; then
      add_sysmsg "gitlore: tier '$tier' has an unfinished merge, so its working tree was left as it is this session. Run /gitlore:resolve to land it."
      # The agent gets its own line: systemMessage is user-only (D14), and the
      # destructive acts here are ones the agent takes unprompted, so the
      # prohibition leads and the remedy follows. Uncapped, unlike the dangling
      # report — a gate yields on the first divergence it meets and stops, so two
      # tiers mid-merge at once is not a state the tooling produces.
      protocol_ctx="$protocol_ctx

gitlore: tier at $tierpath holds an unfinished merge. Do not check it out, reset it, or commit into it. Run /gitlore:resolve to land the merge before writing anything to that tier."
      continue
    fi
    # Pin, unconditionally — not only when the tier was never checked out. Every
    # clone made before tiers were pinned sits ahead of its gitlink already, so a
    # pass that only materializes a missing tier would pin nothing that exists.
    # `--init` covers materialization in the same call.
    gitlore_git -C "$mempath" submodule update --init -- "$tier" >&2 \
      || add_sysmsg "gitlore: tier '$tier' could not be checked out at its recorded commit; skipped."
    [ -e "$tierpath/.git" ] || continue
    # Detach in place (no ref argument, so the commit does not move) when the tier
    # arrived on a named branch — a mount checks the remote's default branch out
    # attached, and `submodule update` leaves it that way whenever that branch's
    # tip already IS the gitlink. The tier branch model has no working branch: a
    # commit made on one would advance a ref the lockstep does not read.
    if git -C "$tierpath" symbolic-ref -q HEAD >/dev/null; then
      gitlore_git -C "$tierpath" checkout -q --detach \
        || add_sysmsg "gitlore: tier '$tier' could not be detached from its branch."
    fi
    # Fetch read-only: `origin live` with no refspec moves no local branch, so the
    # pin holds and the remote tip is still in hand to compare against. Non-fatal —
    # a session must start whatever a tier's remote says — but NOT silent: a tier
    # that has quietly stopped talking to its remote is indistinguishable from one
    # with nothing new, so capture the reason and report it.
    if ! fetch_err=$(git -C "$tierpath" fetch origin live 2>&1); then
      add_sysmsg "gitlore: tier '$tier' could not fetch from its remote; it may be stale. git said: $fetch_err"
      continue
    fi
    # Name what is waiting. Three outcomes, two of them worth a word: the remote
    # contained in HEAD is the lockstep's business (local commits awaiting a push),
    # and saying "waiting" there would send the user into a merge with nothing to
    # merge.
    tier_head=$(git -C "$tierpath" rev-parse HEAD) || continue
    tier_remote=$(git -C "$tierpath" rev-parse FETCH_HEAD) || continue
    if git -C "$tierpath" merge-base --is-ancestor "$tier_remote" "$tier_head"; then
      :
    elif git -C "$tierpath" merge-base --is-ancestor "$tier_head" "$tier_remote"; then
      add_sysmsg "gitlore: tier '$tier' has upstream facts waiting — its remote 'live' is ahead of the pinned commit. Run /gitlore:merge to take them, or /gitlore:push to take them and publish."
    else
      add_sysmsg "gitlore: tier '$tier' has diverged from its remote 'live' — each side has commits the other lacks. Run /gitlore:merge to reconcile them, or /gitlore:push to reconcile and publish."
    fi
  done < <(gitlore_tier_paths "$mempath")
}
