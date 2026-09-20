#!/usr/bin/env bash
# Adopt a tier's arrival into the root index: project the carrier up, and
# when the root refuses it, repair the carrier on a scratch copy, commit the
# repair on top of the arrival, and retry.
# Part of lib/resolve.sh; source that, not this file.

# Adopt a TIER's local `live` when it holds commits its HEAD does not: move the
# working tree onto them, project the carrier up into root's block, and record
# the pair. The mirror of gitlore_repair_stranded_live, and the direction that
# one deliberately leaves alone.
#
# A tier commit advances HEAD and `live` together, so the two part only when the
# MEMORY side loses the moved gitlink afterwards — a merge preparation checks the
# memory store out and rewrites its index, and the next SessionStart pins HEAD
# back at the older commit (D43) while `live` keeps what was approved. Nothing
# reports it: `live` is invisible to the take's ancestry test, which reads HEAD,
# and to SessionStart's, which compares HEAD against the remote.
#
# Neither ref may simply be moved onto the other. Rewinding `live` discards
# approved commits; moving HEAD alone takes the tier off the commit the store
# records, which is the state gitlore_compose_check_pins refuses — so the publish
# gate's bare "put HEAD back on 'live'" remedy is the one that breaks the store.
# What the state calls for is the take: the same fast-forward-plus-adoption a
# remote arrival gets, sourced from a local ref. `live` already holds the target,
# so no ref moves here at all.
#
# TIERS ONLY. The memory root has no pin above it — SessionStart checks it out at
# `live` and the parent's gitlink is allowed to lag (D46) — so there a `live`
# ahead of HEAD is answered by the checkout the gate names, and moving the root
# store here would take a decision the refs do not carry.
# Args: $1 = memory worktree, $2 = store worktree, $3 = tier name ("" = root).
# Returns 1 after emitting when the adoption cannot proceed.
gitlore_adopt_advanced_live() {
  local mempath="$1" store="$2" tier="$3" label root_dirty_before head err
  [ -n "$tier" ] || return 0
  gitlore_live_ahead_of_head "$store" || return 0
  label="tier '$tier'"

  # Refused rather than checked out over, exactly as the remote take refuses a
  # dirty store: the working tree may hold this session's unapproved facts, and
  # the checkout below would carry them onto a commit nobody approved them
  # against.
  if [ "$(gitlore_memory_dirty "$store")" = "1" ]; then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its local 'live' holds commits the memory store never recorded, but the tier has uncommitted changes, so nothing was adopted. Commit them (approved summary, then a memory commit) and run /gitlore:merge again." \
      "gitlore: $label — its local 'live' holds commits the memory store never recorded, but the tier has uncommitted changes, so nothing was adopted. Commit them and merge again." >&2
    return 1
  fi

  # Read BEFORE the tree moves, same as the remote take: what matters is whether
  # the root already held work the canned bookkeeping commit would sweep up.
  root_dirty_before=$(gitlore_root_dirty_beyond_pair "$mempath" "$tier")
  head=$(git -C "$store" rev-parse HEAD) || return 1
  if ! err=$(gitlore_git -C "$store" checkout -q --detach live 2>&1); then
    gitlore_say_for_agent_or_user \
      "gitlore: $label — its working tree could not follow its local 'live'. git said:
$err" \
      "gitlore: $label — its working tree could not follow its local 'live'. git said:
$err" >&2
    return 1
  fi
  printf 'gitlore: %s — its local '\''live'\'' held commits the memory store never recorded; adopted them at %s.\n' \
    "$label" "$(git -C "$store" rev-parse --short HEAD)"
  gitlore_adopt_tier_into_root "$mempath" "$tier" "$root_dirty_before" "$head" || return 1
  return 0
}

# Project a tier's newly-adopted carrier up into the root index, stage the pair
# and record it — the tail every take shares, whether what arrived came from the
# tier's own remote or from a local `live` that ran ahead of the pin. A no-op for
# the memory root, which adopts nothing: its own index is one of the files that
# moved.
#
# A failed up projection records nothing and returns the tier's working tree to
# the pre-take commit. Staging the gitlink alone would put the tier back on its
# pin while root still holds the older block, so the next compose would write
# that older text over the carrier and report success (D50). Leaving the tier
# ahead of an unstaged pin is no better: the pin guard refuses every commit until
# SessionStart walks it back, and a take meanwhile finds nothing to take. Walked
# back here, the tier is on its pin with the arrival held in its local `live` —
# the state gitlore_adopt_advanced_live adopts — so the next take retries the
# whole adoption. The checkout loses nothing: a take refuses a dirty tier, and
# the up projection writes no carrier.
#
# A refusal in which any problem names the arriving carrier is repaired first:
# gitlore_adopt_repair_arrival commits the repaired carrier on top of the
# arrival, advances the tier's local `live` to it and retries. The repair then
# rests in `live` whether the retry adopts it or still refuses on root, the
# manifest or another tier — problems this repo fixes itself, which the retry's
# refusal reports and walks back from as above.
# Args: $1 = memory worktree, $2 = tier name ("" = the memory root), $3 = "1"
#       when the root store was dirty before the take, $4 = the pre-take commit.
# Returns 1 after emitting when the root index could not take the carrier.
gitlore_adopt_tier_into_root() {
  local mempath="$1" tier="$2" root_dirty_before="$3" old_gitlink="$4"
  local label composed carrier_problems rc=0
  [ -n "$tier" ] || return 0
  label="tier '$tier'"

  composed=$(gitlore_compose_up "$mempath" "$tier") || rc=$?
  if [ "$rc" -eq 1 ] && carrier_problems=$(gitlore_compose_problems_in "$mempath/$tier/MEMORY.md" <<<"$composed"); then
    gitlore_adopt_repair_arrival "$mempath" "$tier" "$old_gitlink" \
      "$root_dirty_before" "$label" "$carrier_problems" "$composed" || return 1
    return 0
  fi
  if [ "$rc" -ne 0 ]; then
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" || :
    return 1
  fi
  [ -n "$composed" ] && printf '%s\n' "$composed" | sed 's/^/gitlore: /'
  gitlore_adopt_stage_pair_and_commit "$mempath" "$tier" "$root_dirty_before" "$old_gitlink" "$label"
}

# Repair the carrier a take just checked out, commit the repair on top of the
# arrival, advance the tier's local `live` to it and retry the up projection.
# History stays linear (D6), and the commit is unprompted (D49): it restructures
# lines that already passed an approval gate and adds no text. The worktree
# never holds the repair uncommitted — the rewrite happens on a scratch copy
# outside the repository, and the tier moves only by checking out `live` once
# it holds the commit — so a killed take leaves the tier clean, on the arrival,
# the repair or its pin, with `live` holding the arrival or the repair.
# Args: $1 = memory worktree, $2 = tier name, $3 = the pre-take commit,
#       $4 = "1" when the root store was dirty before the take,
#       $5 = "tier '<name>'", $6 = the first refusal's problems naming the
#       carrier, in the arrival's own line numbering, $7 = the first refusal's
#       full text, printed whole when the repair fails on something the next
#       take redoes, and for its problems beyond the carrier when the repair
#       cannot fix it.
# Returns 0 once the retry adopts the repair. Returns 1, having emitted and
# walked the tier back to its pin, when the repair cannot be built or cannot fix
# the carrier, `live` cannot be advanced, the worktree cannot follow it, or the
# retry still refuses.
gitlore_adopt_repair_arrival() {
  local mempath="$1" tier="$2" old_gitlink="$3" root_dirty_before="$4" label="$5" carrier_problems="$6" composed="$7"
  local tierpath="$mempath/$tier" scratch report line repair="" err retry_composed retry_rc=0
  local remedy="" other_lines

  if ! scratch=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"); then
    printf 'gitlore: %s — its arrival could not be repaired: no scratch directory could be made.\n' "$label" >&2
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." || :
    return 1
  fi
  # A pin that predates the tier's own MEMORY.md leaves no pin copy, which
  # gitlore_repair_index reads as an empty carrier; `-q --verify` is silent on
  # that miss.
  if ! git -C "$tierpath" show HEAD:MEMORY.md > "$scratch/arrival"; then
    printf 'gitlore: %s — its arrival could not be read for repair.\n' "$label" >&2
  elif git -C "$tierpath" rev-parse -q --verify "$old_gitlink:MEMORY.md" >/dev/null &&
       ! git -C "$tierpath" show "$old_gitlink:MEMORY.md" > "$scratch/pin"; then
    printf 'gitlore: %s — the carrier at its pin could not be read for repair.\n' "$label" >&2
  elif ! report=$(gitlore_repair_index "$scratch/arrival" "$scratch/pin" "$tierpath"); then
    printf 'gitlore: %s — its arrival could not be rewritten during repair.\n' "$label" >&2
  elif [ -n "$(gitlore_compose_check_index "$scratch/arrival")" ]; then
    # The first refusal's lines, not the rechecked copy's: every line number
    # then counts in the commit the upstream fix is made against.
    printf 'gitlore: tier '\''%s'\'' took an index the take cannot repair; it is held in the tier'\''s local '\''live'\'' and must be fixed where it was published:\n' "$tier" >&2
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      printf 'gitlore:   live:MEMORY.md: %s\n' "${line#"$tierpath/MEMORY.md: "}" >&2
    done <<<"$carrier_problems"
    other_lines=$(
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        gitlore_compose_problems_in "$tierpath/MEMORY.md" <<<"$line" >/dev/null && continue
        printf '%s\n' "$line"
      done <<<"$composed"
    )
    if [ -n "$other_lines" ]; then
      gitlore_adopt_print_root_refusal "$label" "$other_lines"
      remedy="Fix the problems listed above in this repo; once the index is fixed where it was published, run /gitlore:merge again."
    else
      remedy="Once the index is fixed where it was published, run /gitlore:merge again."
    fi
    rm -rf -- "$scratch"
    gitlore_adopt_walk_back_tier "$mempath" "$tier" "$old_gitlink" "$label" "$remedy" || :
    return 1
  elif ! repair=$(gitlore_adopt_commit_repair "$tierpath" "$tier" "$scratch" "$report"); then
    printf 'gitlore: %s — its arrival could not be repaired: building the repair commit failed.\n' "$label" >&2
    repair=""
  fi
  rm -rf -- "$scratch"
  # Every arm left here without a repair failed on something the next take
  # redoes from scratch.
  if [ -z "$repair" ]; then
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." || :
    return 1
  fi

  if ! err=$(gitlore_git -C "$tierpath" push -q . "$repair:refs/heads/live" 2>&1); then
    printf 'gitlore: %s — its repair could not advance its local '\''live'\''. git said:\n%s\n' "$label" "$err" >&2
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." || :
    return 1
  fi
  if ! err=$(gitlore_git -C "$tierpath" checkout -q --detach live 2>&1); then
    printf 'gitlore: %s — its repair advanced its local '\''live'\'' but its working tree could not follow. git said:\n%s\n' "$label" "$err" >&2
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$composed" "Run /gitlore:merge again." "the repair" || :
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    printf 'gitlore: repaired %s'\''s arrival: %s\n' "$tier" "$line"
  done <<<"$report"

  retry_composed=$(gitlore_compose_up "$mempath" "$tier") || retry_rc=$?
  if [ "$retry_rc" -ne 0 ]; then
    gitlore_adopt_report_refusal_and_walk_back "$mempath" "$tier" "$old_gitlink" "$label" "$retry_composed" "" "the repair" || :
    return 1
  fi
  # Inside a push the take is itself publishing, and naming /gitlore:push would
  # send the reader to run again what is already running.
  if [ -n "${GITLORE_TAKE_IN_PUSH:-}" ]; then
    printf 'gitlore: %s — the repair is committed in its local '\''live'\'', and this push publishes it.\n' "$label"
  else
    printf 'gitlore: %s — the repair is committed in its local '\''live'\''; /gitlore:push publishes it.\n' "$label"
  fi
  [ -n "$retry_composed" ] && printf '%s\n' "$retry_composed" | sed 's/^/gitlore: /'
  gitlore_adopt_stage_pair_and_commit "$mempath" "$tier" "$root_dirty_before" "$old_gitlink" "$label"
}

# Print a commit whose only parent is the tier's HEAD and whose tree is HEAD's
# with MEMORY.md replaced, byte for byte, by <scratch>/arrival. Built from a
# temporary index in <scratch>, so the worktree is never the commit's staging
# area, and with `commit-tree`, which runs no hook.
# Args: $1 = tier worktree, $2 = tier name, $3 = scratch directory, $4 = the
#       repair report, which becomes the commit body.
gitlore_adopt_commit_repair() {
  local tierpath="$1" tier="$2" scratch="$3" report="$4" entry blob tree
  entry=$(git -C "$tierpath" ls-tree HEAD -- MEMORY.md) || return 1
  [ -n "$entry" ] || return 1
  GIT_INDEX_FILE="$scratch/index" git -C "$tierpath" read-tree HEAD || return 1
  blob=$(git -C "$tierpath" hash-object -w --no-filters -- "$scratch/arrival") || return 1
  GIT_INDEX_FILE="$scratch/index" git -C "$tierpath" update-index --cacheinfo "${entry%% *},$blob,MEMORY.md" || return 1
  tree=$(GIT_INDEX_FILE="$scratch/index" git -C "$tierpath" write-tree) || return 1
  git -C "$tierpath" commit-tree -p HEAD -m "Repair the MEMORY.md structure $tier received" -m "$report" "$tree"
}
