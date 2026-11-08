#!/usr/bin/env bash
# The end of a take: write root's index once for every tier the run left ahead of
# the commit root records, and record them in one canned bookkeeping commit. Also
# the report of a refused adoption, shared with the arrival repair.
# Part of lib/resolve.sh; source that, not this file.

# Project every tier ahead of its pin up into root's index, stage the moves and
# record them in one commit naming those tiers. Whatever moved a tier counts, this
# run's take or an earlier continuation that landed a tier merge: a tier off its
# pin is all the state there is, so a killed run needs no marker. A run that moved
# nothing writes nothing.
#
# Refused by the compose, this records nothing and moves nothing back: every tier
# stays where its take put it, and the next take retries the write. A compose
# that leaves a diff3 chunk in root writes root with it, stages the moves and
# commits nothing; the markers stop every pass and commit until they are
# resolved, and the next approved memory commit carries the moves.
#
# A root store holding other uncommitted work gets the moves staged rather than
# committed, for the next approved memory commit to carry (D43): a canned commit
# would sweep that work up. Root `MEMORY.md` is outside that question on purpose,
# since the compose rewrites it whatever it held (D31), and so are tier paths,
# which a take is moving.
#
# Best-effort past the compose: a landed take must not become a failed one because
# its bookkeeping could not be recorded, so a failure there names what it left.
# Args: $1 = memory worktree. Returns 1 after emitting when nothing was recorded.
gitlore_compose_moved_tiers() {
  local mempath="$1" moved names="" tier composed rc=0 msgfile err abs
  local -a paths=()
  moved=$(gitlore_tiers_ahead_of_pin "$mempath") || return 1
  [ -n "$moved" ] || return 0

  [ ! -f "$mempath/MEMORY.md" ] || paths+=(MEMORY.md)
  while IFS= read -r tier; do
    names="${names:+$names, }$tier"
    paths+=("$tier")
  done <<<"$moved"

  composed=$(gitlore_compose_up "$mempath" "$moved" :) || rc=$?
  if [ "$rc" -eq 3 ]; then
    gitlore_report_compose_markers "$mempath" "$(gitlore_tier_labels "$moved")" "$composed"
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    gitlore_adopt_report_refusal "$(gitlore_tier_labels "$moved")" "$composed" "Fix the store, then run /gitlore:merge again."
    return 1
  fi
  [ -z "$composed" ] || printf '%s\n' "$composed" | sed 's/^/gitlore: /'

  # The body reads the pins HEAD records, which the staging below does not move.
  msgfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-tier-msg.XXXXXX") || msgfile=""
  [ -z "$msgfile" ] || gitlore_bookkeeping_message "$mempath" "$names" "$moved" > "$msgfile"

  if ! gitlore_git -C "$mempath" add -- "${paths[@]}"; then
    # The printed path is absolute, so the command runs from anywhere.
    abs=$(CDPATH='' cd -- "$mempath" && pwd) || abs="$mempath"
    # shellcheck disable=SC2016  # backticks are markdown for the reader, not a command sub
    printf 'gitlore: %s advanced, but the pointer could not be staged in the memory store. Run `git -C "%s" add --%s` before the next session, or the pointer will be reset to its previous commit.\n' \
      "$names" "$abs" "$(printf ' "%s"' "${paths[@]}")" >&2
    [ -z "$msgfile" ] || rm -f "$msgfile"
    return 0
  fi

  if [ -n "$(git -C "$mempath" status --porcelain --ignore-submodules=all -- . ":(exclude)MEMORY.md")" ]; then
    [ -z "$msgfile" ] || rm -f "$msgfile"
    printf 'gitlore: the memory store has other uncommitted changes, so the moved %s pointer and the recomposed root index were staged rather than committed. They ride the next memory commit (approved summary).\n' "$names"
    return 0
  fi
  # Nothing staged: the compose changed nothing and the staged gitlinks match what
  # root already records, so an empty commit would only fail.
  if git -C "$mempath" diff --cached --quiet; then
    [ -z "$msgfile" ] || rm -f "$msgfile"
    return 0
  fi
  if [ -z "$msgfile" ]; then
    printf 'gitlore: %s advanced and the moves are staged, but no message file could be made for the bookkeeping commit, so they ride the next memory commit.\n' "$names" >&2
    return 0
  fi

  # Bare `commit`, never `-a` or an `add -A`: exactly what was staged above goes
  # in. A store clean beyond those paths has nothing else staged to catch.
  if ! err=$(gitlore_git -C "$mempath" commit -q -F "$msgfile" 2>&1); then
    rm -f "$msgfile"
    printf 'gitlore: %s advanced and the moves are staged, but the bookkeeping commit failed, so they ride the next memory commit. git said:\n%s\n' "$names" "$err" >&2
    return 0
  fi
  rm -f "$msgfile"

  # Same invariant every other memory commit restores: `live` holds the commit
  # the moment it exists. Refused only by a race, which the next gate re-reads.
  if ! err=$(gitlore_git -C "$mempath" push -q . HEAD:live 2>&1); then
    printf 'gitlore: the %s bookkeeping commit landed but memory'\''s local '\''live'\'' could not follow it. git said:\n%s\n' "$names" "$err" >&2
    return 0
  fi
  printf 'gitlore: memory — recorded %s in a bookkeeping commit; the store is clean.\n' "$names"
}

# The end compose of a push: root takes its remote first when it is merely behind,
# so the bookkeeping commit lands on top. A diverged root composes nothing here:
# the refused push that follows prepares the merge, which records each tier's HEAD.
# Assumes `origin/live` has just been fetched. Args: $1 = memory worktree.
# Returns 1 after emitting.
gitlore_compose_moved_tiers_for_push() {
  local mempath="$1" moved remote
  moved=$(gitlore_tiers_ahead_of_pin "$mempath") || return 1
  [ -n "$moved" ] || return 0
  # `-q --verify` is silent on the expected miss: a remote with no `live` yet.
  if remote=$(git -C "$mempath" rev-parse -q --verify refs/remotes/origin/live) \
     && ! git -C "$mempath" merge-base --is-ancestor "$remote" live; then
    git -C "$mempath" merge-base --is-ancestor live "$remote" || return 0
    gitlore_merge_one_store "$mempath" "$mempath" "" || return 1
  fi
  gitlore_compose_moved_tiers "$mempath"
}

# Print each mounted tier whose HEAD strictly descends the commit root's HEAD
# records, one per line. HEAD, not the index, decides whether a tier moved: the
# compose pass stages the gitlink of a tier it merged up without committing it,
# and a pointer only staged is not recorded until a commit carries it, which is
# what the bookkeeping commit is for. A mount HEAD does not record yet reads
# its staged gitlink as the pin. The index pin is the one the record would
# move, so ancestry is read against it: a tier behind it is left out, so a pin
# never moves backward, and the commit's own guard answers that tier. So is a
# tier off to the side of it, which is reported, since nothing below can say
# which of the two was meant.
# Args: $1 = memory worktree. Returns 1, after the refusal, on a recorded commit
# neither the tier nor its remote holds.
gitlore_tiers_ahead_of_pin() {
  local mempath="$1" tier tierpath pin staged head
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # `git -C` into an unchecked-out submodule walks up to the enclosing repo.
    [ -e "$tierpath/.git" ] || continue
    # `-q --verify` is silent on the expected misses: no stage-0 gitlink in
    # the index (mid-mount), and a tier with no commit. A mount left staged on a
    # store that held other work has no gitlink in HEAD yet; the staged one is
    # its pin, since no earlier commit records the tier at all.
    staged=$(git -C "$mempath" rev-parse -q --verify ":$tier") || continue
    pin=$(git -C "$mempath" rev-parse -q --verify "HEAD:$tier") || pin="$staged"
    head=$(git -C "$tierpath" rev-parse -q --verify HEAD) || continue
    [ "$head" != "$pin" ] || continue
    gitlore_tier_holds_gitlink "$mempath" "$tier" "$staged" || return 1
    if git -C "$tierpath" merge-base --is-ancestor "$staged" "$head"; then
      printf '%s\n' "$tier"
    elif ! git -C "$tierpath" merge-base --is-ancestor "$head" "$staged"; then
      printf 'gitlore: tier '\''%s'\'' sits at %s, which does not contain the commit the memory store'\''s index records (%s), so nothing was recorded for it. The next memory commit refuses that pin and names the remedy.\n' \
        "$tier" "${head:0:12}" "${staged:0:12}" >&2
    fi
  done < <(gitlore_tier_paths "$mempath")
}

# The canned bookkeeping message on stdout: a subject naming the moved tiers, then
# for each the subjects its move brought in. A fast-forward creates no commit in
# the tier itself, so without these the root commit would be the only record and
# would say nothing about what arrived. Args: $1 = memory worktree, $2 = the tier
# names for the subject, $3 = the tiers, one per line.
gitlore_bookkeeping_message() {
  local mempath="$1" names="$2" moved="$3" tier pin
  printf 'Update MEMORY.md for %s tier merge.\n\n' "$names"
  while IFS= read -r tier; do
    pin=$(git -C "$mempath" rev-parse -q --verify "HEAD:$tier") \
      || pin=$(git -C "$mempath" rev-parse -q --verify ":$tier") || continue
    printf '%s:\n' "$tier"
    git -C "$mempath/$tier" log --format='%s' "$pin..HEAD" | sed 's/^/  /'
  done <<<"$moved"
}

# Report root written with a diff3 chunk and nothing committed. Args: $1 = memory
# worktree, $2 = "tier '<name>'" or a list of them, $3 = gitlore_compose_up's
# output: the composed line, then one line per marker.
gitlore_report_compose_markers() {
  local mempath="$1" label="$2" composed="$3" line
  printf 'gitlore: the root index and %s changed the same lines apart, so %s/MEMORY.md now holds conflict markers; the tier moves are staged and nothing was committed:\n' "$label" "$mempath" >&2
  while IFS= read -r line; do
    case "$line" in "composed "* | "") continue ;; esac
    printf 'gitlore:   %s\n' "$line" >&2
  done <<<"$composed"
  printf 'gitlore: resolve each chunk to the line the root index should carry, then commit memory.\n' >&2
}

# Print "tier 'a', tier 'b'" for the tiers listed one per line in $1.
gitlore_tier_labels() {
  local tier labels=""
  while IFS= read -r tier; do
    labels="${labels:+$labels, }tier '$tier'"
  done <<<"$1"
  printf '%s\n' "$labels"
}

# Report what the root index could not take and that nothing was recorded.
# Args: $1 = "tier '<name>'" or a list of them, $2 = the refused lines, one per
# line, $3 = the closing remedy.
gitlore_adopt_report_refusal() {
  local label="$1" lines="$2" remedy="$3"
  printf 'gitlore: the root index could not take %s'\''s lines:\n' "$label" >&2
  printf '%s\n' "$lines" | sed 's/^/gitlore:   /' >&2
  gitlore_adopt_report_nothing_recorded "$label" "$remedy"
}

# Args: $1 = "tier '<name>'" or a list of them, $2 = the closing remedy.
gitlore_adopt_report_nothing_recorded() {
  printf 'gitlore: nothing was recorded, and %s stays where the take put it. %s\n' "$1" "$2" >&2
}
