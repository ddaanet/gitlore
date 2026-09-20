#!/usr/bin/env bash
# Report an adoption refusal and walk the tier back to its pin, then — on the
# landed path — stage the adopted pair and record it in a canned bookkeeping
# commit.
# Part of lib/resolve.sh; source that, not this file.

# Print the problems the up projection could not take, then walk the tier back.
# Shared by a refusal naming nothing in the arriving carrier, by a repair that
# fails on something the next take redoes, and by a repair's retry that still
# finds root, the manifest or another tier refusing.
# Args: $1 = memory worktree, $2 = tier name, $3 = the pre-take commit,
#       $4 = "tier '<name>'", $5 = the compose problems, $6 = the closing
#       remedy and $7 = what the tier's local `live` keeps, both optional and
#       passed to gitlore_adopt_walk_back_tier, whose default an empty one keeps.
# Returns 1 after emitting.
gitlore_adopt_report_refusal_and_walk_back() {
  local mempath="$1" tier="$2" old_gitlink="$3" label="$4" composed="$5" remedy="${6:-}"
  local live_holds="${7:-}"
  gitlore_adopt_print_root_refusal "$label" "$composed"
  gitlore_adopt_walk_back_tier "$mempath" "$tier" "$old_gitlink" "$label" "$remedy" "$live_holds" || :
  return 1
}

# Print the root-index-could-not-take header and the refused lines, each
# prefixed for the reader, to stderr. Shared by the unrepairable arm's own
# lines and the refusal-and-walk-back path's composed lines — one spelling of
# the same user-visible message.
# Args: $1 = "tier '<name>'" or whatever else names the arrival, $2 = the
#       refused lines, one per line.
gitlore_adopt_print_root_refusal() {
  local label="$1" lines="$2"
  printf 'gitlore: the root index could not take %s'\''s lines:\n' "$label" >&2
  printf '%s\n' "$lines" | sed 's/^/gitlore:   /' >&2
}

# Return the tier to the commit the memory store records, after a refusal left
# nothing to adopt.
# Args: $1 = memory worktree, $2 = tier name, $3 = the pre-take commit,
#       $4 = "tier '<name>'", for the messages, $5 = the closing remedy when
#       the store is not what needs fixing (optional; empty keeps "Fix the
#       store, …"), $6 = what the tier's local `live` keeps (optional; empty
#       keeps "what arrived").
# Returns 1 after emitting, whether or not the checkout succeeded.
gitlore_adopt_walk_back_tier() {
  local mempath="$1" tier="$2" old_gitlink="$3" label="$4" err abs
  local remedy="${5:-Fix the store, then run /gitlore:merge again.}"
  local live_holds="${6:-what arrived}"
  if ! err=$(gitlore_git -C "$mempath/$tier" checkout -q --detach "$old_gitlink" 2>&1); then
    # Absolute, so the printed command runs from anywhere.
    abs=$(CDPATH='' cd -- "$mempath/$tier" && pwd) || abs="$mempath/$tier"
    # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
    printf 'gitlore: nothing was recorded, but %s could not be returned to the commit the memory store records. git said:\n%s\ngitlore: run `git -C "%s" checkout --detach %s`, fix the store, then run /gitlore:merge again.\n' \
      "$label" "$err" "$abs" "$old_gitlink" >&2
    return 1
  fi
  printf 'gitlore: nothing was recorded, and %s is back on the commit the memory store records; its local '\''live'\'' keeps %s. %s\n' "$label" "$live_holds" "$remedy" >&2
  return 1
}

# Stage the tier's newly-adopted carrier pair and record it in a canned commit
# — the tail a landed take and a landed repair share.
# Args: $1 = memory worktree, $2 = tier name, $3 = "1" when the root store was
#       dirty before the take, $4 = the pre-take commit, $5 = "tier '<name>'".
gitlore_adopt_stage_pair_and_commit() {
  local mempath="$1" tier="$2" root_dirty_before="$3" old_gitlink="$4" label="$5" abs
  # Stage the pair the take just produced. `submodule update` reads the gitlink
  # from the superproject's INDEX, so an unstaged one is walked back to the
  # pre-take commit by the next SessionStart tier pass — and the composed root
  # index, being an ordinary working-tree write, survives to describe facts the
  # tier no longer holds. Staged, the unconditional pin is idempotent rather than
  # destructive. Staging is best-effort: a failure here must not turn a landed
  # take into a failed merge.
  # The printed path is absolute, so the command runs from anywhere.
  if ! gitlore_git -C "$mempath" add -- MEMORY.md "$tier"; then
    abs=$(CDPATH='' cd -- "$mempath" && pwd) || abs="$mempath"
    # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
    printf 'gitlore: %s advanced, but its pointer could not be staged in the memory store. Run `git -C "%s" add -- MEMORY.md "%s"` before the next session, or the pointer will be reset to its previous commit.\n' "$label" "$abs" "$tier" >&2
  fi
  # Then commit the pair, so an explicit take leaves a clean store (D49). The
  # dirty reading is the one taken BEFORE the tree moved: everything dirty now is
  # this take's own work, and anything that was dirty before it is unapproved
  # content the canned commit must not sweep up.
  gitlore_commit_tier_bookkeeping "$mempath" "$tier" "$root_dirty_before" "$old_gitlink"
}

# Commit the root index and moved tier gitlink an explicit take just staged,
# with a canned message, and fast-forward the store's local `live` onto it.
# Unprompted by design (D49): both parents of the take passed an approval gate
# already — the local side at its own FR11 commit, the upstream side in the repo
# that published it — so the bookkeeping introduces no unapproved content.
#
# Refuses, leaving the staged pair for the next FR11 episode, when the root
# store was dirty BEFORE the take: those edits are unapproved, and a canned
# `commit` would carry whatever else is staged alongside the pair. That path is
# D43's staged-pair discipline, which stays the degraded case rather than the
# resting state.
#
# Best-effort throughout: a landed fast-forward must not become a failed take
# because its bookkeeping could not be recorded. Every failure names the pair
# and leaves it staged.
# Args: $1 = memory worktree, $2 = tier name, $3 = "1" when the root store was
#       already dirty before the take, $4 = the tier's pre-take commit.
gitlore_commit_tier_bookkeeping() {
  local mempath="$1" tier="$2" dirty_before="$3" old_gitlink="$4"
  local msgfile err

  if [ "$dirty_before" = "1" ]; then
    printf 'gitlore: the memory store had uncommitted changes before this take, so the moved %s pointer and the recomposed root index were staged rather than committed. They ride the next memory commit (approved summary).\n' "$tier"
    return 0
  fi
  # Nothing staged: the root already records this exact state — a root commit
  # taken from upstream carried the gitlink, and the tier loop's fast-forward
  # then only caught the worktree up. An empty commit would fail, and reporting
  # that failure would dress a healthy path as a broken one.
  if git -C "$mempath" diff --cached --quiet; then
    return 0
  fi

  msgfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-tier-msg.XXXXXX") || return 0
  {
    printf 'Update MEMORY.md for %s tier merge.\n\n' "$tier"
    # The subjects the take brought in. A fast-forward creates no commit in the
    # tier itself, so without this the root commit would be the only record and
    # would say nothing about what arrived.
    git -C "$mempath/$tier" log --format='%s' "$old_gitlink..HEAD" 2>/dev/null \
      | sed 's/^/  /'
  } > "$msgfile"

  # Bare `commit`, never `-a` or an `add -A`: exactly the pair staged above goes
  # in. A store clean before the take has nothing else staged to catch.
  if ! err=$(GITLORE_MEMORY_COMMIT=1 gitlore_git -C "$mempath" commit -q -F "$msgfile" 2>&1); then
    rm -f "$msgfile"
    printf 'gitlore: %s advanced and its pointer is staged, but the bookkeeping commit failed, so it rides the next memory commit. git said:\n%s\n' "$tier" "$err" >&2
    return 0
  fi
  rm -f "$msgfile"

  # Same invariant every other memory commit restores: `live` holds the commit
  # the moment it exists. Refused only by a race, which the next gate re-reads.
  if ! err=$(gitlore_git -C "$mempath" push -q . HEAD:live 2>&1); then
    printf 'gitlore: the %s bookkeeping commit landed but memory'\''s local '\''live'\'' could not follow it. git said:\n%s\n' "$tier" "$err" >&2
    return 0
  fi
  printf 'gitlore: memory — recorded %s'\''s move in a bookkeeping commit; the store is clean.\n' "$tier"
  return 0
}

# Print 1 when the root store holds a change beyond the pair a take is about to
# commit — its own `MEMORY.md` and the tier gitlink — and 0 otherwise.
#
# The plain dirty reading cannot answer this from inside a landed merge: the
# preparation has already moved the tier, so the root is dirty by construction
# and every take would refuse. What the guard is actually asking is whether
# somebody else's unapproved work would ride the canned commit, and that is a
# question about the OTHER paths. Pathspec exclusions, not a filter over
# porcelain output: a path with a space or a quote survives them intact.
# Args: $1 = memory worktree, $2 = tier name.
gitlore_root_dirty_beyond_pair() {
  local mempath="$1" tier="$2"
  if [ -z "$(git -C "$mempath" status --porcelain -- . ":(exclude)MEMORY.md" ":(exclude)$tier")" ]; then
    printf '0\n'
  else
    printf '1\n'
  fi
}
