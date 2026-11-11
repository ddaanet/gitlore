#!/usr/bin/env bash
# What a take does to a tier ahead of the commit root records, ahead of root's own
# move: adopt commits only its local `live` holds, and repair a defective carrier
# on a scratch copy, committing the repair on top of the arrival.
# Part of lib/resolve.sh; source that, not this file.

# Adopt a TIER's local `live` when it holds commits its HEAD does not: move the
# working tree onto them, so the end of the run records them. The mirror of
# gitlore_repair_stranded_live, and the direction that one deliberately leaves
# alone.
#
# A tier commit advances HEAD and `live` together, so the two part only when the
# MEMORY side loses the moved gitlink afterwards — a merge preparation checks the
# memory store out and rewrites its index, and the next SessionStart pins HEAD
# back at the older commit (D43) while `live` keeps what was approved. Nothing
# reports it: `live` is invisible to the take's ancestry test, which reads HEAD,
# and to SessionStart's, which compares HEAD against the remote.
#
# `live` must not be rewound: that discards approved commits. What the state calls
# for is the take: the same move a remote arrival gets, sourced from a local ref.
# `live` already holds the target, so no ref moves here at all.
#
# TIERS ONLY. The memory root has no pin above it — SessionStart checks it out at
# `live` and the parent's gitlink is allowed to lag (D46) — so there a `live`
# ahead of HEAD is answered by the checkout the gate names, and moving the root
# store here would take a decision the refs do not carry.
# Args: $1 = memory worktree, $2 = store worktree, $3 = tier name ("" = root).
# Returns 1 after emitting when the adoption cannot proceed.
gitlore_adopt_advanced_live() {
  local store="$2" tier="$3" label err
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
  return 0
}

# Check a tier off the commit root records, on its own carrier, and repair a
# carrier that fails (D52). Runs on every take rather than only on an arrival, so
# a repair that failed on something the next take redoes is retried: the tier
# stays on what arrived, and its next take finds nothing new to fetch. A tier with
# uncommitted changes is passed over: what its worktree shows is not what arrived.
# Args: $1 = memory worktree, $2 = tier name.
# Returns 1 after emitting when a defective carrier could not be repaired.
gitlore_repair_moved_carrier() {
  local mempath="$1" tier="$2" tierpath="$1/$2" pin head problems
  # `-q --verify` is silent on the expected misses: no gitlink in the index
  # (mid-mount), and a tier with no commit.
  pin=$(git -C "$mempath" rev-parse -q --verify ":$tier") || return 0
  head=$(git -C "$tierpath" rev-parse -q --verify HEAD) || return 0
  [ "$head" != "$pin" ] || return 0
  [ -f "$tierpath/MEMORY.md" ] || return 0
  [ "$(gitlore_memory_dirty "$tierpath")" = "0" ] || return 0
  problems=$(gitlore_compose_check_index "$tierpath/MEMORY.md")
  [ -n "$problems" ] || return 0
  gitlore_adopt_repair_arrival "$mempath" "$tier" "$pin" "tier '$tier'" "$problems"
}

# Repair the carrier a take just checked out, commit the repair on top of the
# arrival, advance the tier's local `live` to it and recheck the carrier. History
# stays linear (D6), and the commit is unprompted (D49): it restructures lines
# that already passed an approval gate and adds no text. The worktree never holds
# the repair uncommitted — the rewrite happens on a scratch copy outside the
# repository, and the tier moves only by checking out `live` once it holds the
# commit — so a killed take leaves the tier clean, on the arrival or the repair,
# with `live` holding the arrival or the repair.
# Args: $1 = memory worktree, $2 = tier name, $3 = the commit root records,
#       $4 = "tier '<name>'", $5 = the problems naming the carrier, in the
#       arrival's own line numbering.
# Returns 0 once the recheck passes. Returns 1, having emitted, with the tier
# where the take put it, when the repair cannot be built or cannot fix the
# carrier, `live` cannot be advanced, or the worktree cannot follow it.
gitlore_adopt_repair_arrival() {
  local mempath="$1" tier="$2" old_gitlink="$3" label="$4" carrier_problems="$5"
  local tierpath="$mempath/$tier" scratch report line repair="" err

  if ! scratch=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-repair.XXXXXX"); then
    printf 'gitlore: %s — its arrival could not be repaired: no scratch directory could be made.\n' "$label" >&2
    gitlore_adopt_report_refusal "$label" "$carrier_problems" "Run /gitlore:merge again."
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
    # The first check's lines, not the rechecked copy's: every line number then
    # counts in the commit the upstream fix is made against.
    printf 'gitlore: tier '\''%s'\'' took an index the take cannot repair; it is held in the tier'\''s local '\''live'\'' and must be fixed where it was published:\n' "$tier" >&2
    while IFS= read -r line || [ -n "$line" ]; do
      [ -n "$line" ] || continue
      printf 'gitlore:   live:MEMORY.md: %s\n' "${line#"$tierpath/MEMORY.md: "}" >&2
    done <<<"$carrier_problems"
    rm -rf -- "$scratch"
    gitlore_adopt_report_nothing_recorded "$label" "Once the index is fixed where it was published, run /gitlore:merge again."
    return 1
  elif ! repair=$(gitlore_adopt_commit_repair "$tierpath" "$tier" "$scratch" "$report"); then
    printf 'gitlore: %s — its arrival could not be repaired: building the repair commit failed.\n' "$label" >&2
    repair=""
  fi
  rm -rf -- "$scratch"
  # Every arm left here without a repair failed on something the next take
  # redoes from scratch.
  if [ -z "$repair" ]; then
    gitlore_adopt_report_refusal "$label" "$carrier_problems" "Run /gitlore:merge again."
    return 1
  fi

  if ! err=$(gitlore_git -C "$tierpath" push -q . "$repair:refs/heads/live" 2>&1); then
    printf 'gitlore: %s — its repair could not advance its local '\''live'\''. git said:\n%s\n' "$label" "$err" >&2
    gitlore_adopt_report_refusal "$label" "$carrier_problems" "Run /gitlore:merge again."
    return 1
  fi
  if ! err=$(gitlore_git -C "$tierpath" checkout -q --detach live 2>&1); then
    printf 'gitlore: %s — its repair advanced its local '\''live'\'' but its working tree could not follow. git said:\n%s\n' "$label" "$err" >&2
    gitlore_adopt_report_refusal "$label" "$carrier_problems" "Run /gitlore:merge again."
    return 1
  fi
  while IFS= read -r line || [ -n "$line" ]; do
    [ -n "$line" ] || continue
    printf 'gitlore: repaired %s'\''s arrival: %s\n' "$tier" "$line"
  done <<<"$report"

  # Inside a push the take is itself publishing, and naming /gitlore:push would
  # send the reader to run again what is already running.
  if [ -n "${GITLORE_TAKE_IN_PUSH:-}" ]; then
    printf 'gitlore: %s — the repair is committed in its local '\''live'\'', and this push publishes it.\n' "$label"
  else
    printf 'gitlore: %s — the repair is committed in its local '\''live'\''; /gitlore:push publishes it.\n' "$label"
  fi
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
