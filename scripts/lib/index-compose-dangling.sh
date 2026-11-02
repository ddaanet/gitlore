#!/usr/bin/env bash
# Compose-dangling: the dangling-pointer report, the fix it names per line, and
# the list cap its output and the orphan report share.
# Part of lib/index-compose.sh; source that, not this file.

# Echo at most GITLORE_DANGLING_CAP non-empty lines of stdin; when more remain,
# append a "… and N more" summary in their place. One whole tier going stale at
# once (another consumer merging or renaming a cluster of facts in a shared tier)
# produces a dangling report as long as the cluster — dozens of lines — which
# floods the user's systemMessage AND the agent's additionalContext and, in the
# UI, gets truncated to an unhelpful "and many more lines". The cap keeps the
# report legible: enough lines to see what kind of breakage it is, a count for
# the rest. Non-empty lines only, so a trailing blank from a "$var" append is
# neither counted nor shown.
GITLORE_DANGLING_CAP="${GITLORE_DANGLING_CAP:-5}"
gitlore_cap_list() {
  local input total
  input=$(grep . || true)
  [ -n "$input" ] || return 0
  total=$(printf '%s\n' "$input" | wc -l | tr -d ' ')
  # awk reads to EOF rather than exiting early like `head -n` would — callers
  # run under `set -o pipefail`, and an early-exiting consumer here would send
  # the producer SIGPIPE and lose exactly the "… and N more" summary this
  # function exists to add.
  printf '%s\n' "$input" | awk -v n="$GITLORE_DANGLING_CAP" 'NR<=n'
  if [ "$total" -gt "$GITLORE_DANGLING_CAP" ]; then
    printf '… and %d more\n' "$((total - GITLORE_DANGLING_CAP))"
  fi
}

# For the agent's channel: when $1 lines outnumber the cap, print where the
# lines past it surface, since a collapsed line carries no fix of its own.
# $2 = mempath.
gitlore_cap_rest_note() {
  [ "$1" -gt "$GITLORE_DANGLING_CAP" ] || return 0
  printf 'Only the first %d are listed. Every edit to %s re-runs this report with the rest.\n' \
    "$GITLORE_DANGLING_CAP" "$2/MEMORY.md"
}

# Print one report line per pointer bullet whose target file is absent; return 0
# either way. This is the fifth compose validation, and the only one that
# REPORTS instead of refusing: a dangling line does not make the composed output
# wrong, and refusing would block every later index write over a stale line the
# agent can fix in one edit.
#
# Under presence-authority (D17) the index says what memory CONTAINS, so the
# missing FILE is the anomaly, not the line — which is why nothing here touches
# either surface. Each line ends with the edit that removes it, chosen by
# gitlore_dangling_root_fix: which one works depends on state the working tree
# does not show, so the report decides it rather than the agent's recall.
gitlore_compose_dangling() {
  local mempath="$1" mounted active head tier file line path all="" reported=""

  mounted=$(gitlore_tier_paths "$mempath")
  file="$mempath/MEMORY.md"
  if [ -f "$file" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      all="$all$path
"
      [ -e "$mempath/$path" ] && continue
      reported="$reported$path
"
    done < "$file"
  fi
  if [ -n "$reported" ]; then
    # Only a mounted tier has a carrier to name: a manifest tier that is not
    # mounted falls to the project-line fix.
    active=$(gitlore_mounted_active_tiers "$mempath" "$mounted")
    head=$(gitlore_index_head_paths "$mempath")
    while IFS= read -r path; do
      [ -n "$path" ] || continue
      printf '%s: %s names no file in the memory store — %s\n' "$file" "$path" \
        "$(gitlore_dangling_root_fix "$mempath" "$path" "$active" "$head" "$all" "$reported")"
    done <<EOF
$reported
EOF
  fi

  # Carrier lines too: a DORMANT tier's bullets never reach the root, so a
  # root-only scan would leave them unchecked for as long as the tier sleeps.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    file="$mempath/$tier/MEMORY.md"
    [ -f "$file" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      [ -e "$mempath/$tier/$path" ] && continue
      # An active tier's line lives in both indexes and resolves to one file;
      # report the root's copy only, since that is the surface the agent edits.
      # Here-string, not a pipe — see the same note at gitlore_compose_check above.
      grep -qxF -- "$tier/$path" <<<"$reported" && continue
      printf '%s: %s names no file in the tier — delete its line from %s\n' \
        "$file" "$path" "$file"
    done < "$file"
  done <<EOF
$mounted
EOF
  return 0
}

# Print the manifest's active tiers that are also in $2, the newline-separated
# mounted tiers, in manifest order. $1 = mempath.
gitlore_mounted_active_tiers() {
  local tier
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    if grep -qxF -- "$tier" <<<"$2"; then printf '%s\n' "$tier"; fi
  done <<<"$(gitlore_active_tiers "$1")"
  return 0
}

# Print the edit that removes dangling root line $2. Args: $1 = mempath,
# $3 = active tiers, $4 = root's paths at HEAD, $5 = every root path, $6 = the
# dangling root paths — all newline-separated. A project line is one edit. A
# tier line's fix turns on what the next compose does with the carrier copy:
#
#   root at HEAD has it → the down projection reads root's deletion and drops the
#     copy, so the root edit alone is the fix;
#   root at HEAD lacks it → the copy reads as never authored in root and is kept,
#     so it goes from the carrier too, after root, since a carrier-only deletion
#     of a line root still carries is restored;
#   the dangling lines are all root's lines for the tier → deleting them leaves
#     root none, and the layout adopts the whole carrier back, so the copy goes
#     from the carrier too, after the tier's orphans, which the adoption would
#     carry into root, both deletions in one batch — or the tier is deactivated.
#     Counted per tier, not per line: each of several such lines alone leaves
#     the others standing.
#
# Root first, or both edits in one batch: a carrier edit composes at the end of
# its batch and restores a line root still carries, so a carrier-first edit in a
# batch of its own is undone. The last-line case takes one batch because root
# alone is adopted back.
gitlore_dangling_root_fix() {
  local mempath="$1" path="$2" active="$3" head="$4" all="$5" dangling="$6"
  local root="$mempath/MEMORY.md" tier carrier both
  if ! tier=$(gitlore_tier_of "$path" "$active"); then
    printf 'delete its line from %s\n' "$root"
    return 0
  fi
  carrier="$mempath/$tier/MEMORY.md"
  both="delete its line from $root, then the \`${path#"$tier"/}\` line from $carrier"
  if [ "$(gitlore_paths_in_tier "$tier" <<<"$dangling")" -ge \
       "$(gitlore_paths_in_tier "$tier" <<<"$all")" ]; then
    # The adoption takes the carrier's orphans too, so they are settled first.
    # "If present": a root-first attempt was adopted back and the carrier line
    # may already be gone when this is reported again.
    # shellcheck disable=SC2016 # the backticks are report text, not a substitution
    printf 'settle any orphan reported in %s first, then delete the `%s` line from it and its line from %s in one batch; %s keeps no other live %s/ line, and compose adopts the whole tier index, orphans included, into a root with none. To drop %s from this repo instead, delete its line from %s\n' \
      "$carrier" "${path#"$tier"/}" "$root" "$root" "$tier" "$tier" "$mempath/.gitlore-tiers"
  elif grep -qxF -- "$path" <<<"$head"; then
    printf 'delete its line from %s only; the next compose drops the copy in %s\n' \
      "$root" "$carrier"
  else
    printf '%s; compose keeps a tier line the memory store has not committed\n' "$both"
  fi
}

# Count the newline-separated paths on stdin that tier $1 prefixes.
gitlore_paths_in_tier() {
  local tier="$1" path n=0
  while IFS= read -r path || [ -n "$path" ]; do
    case "$path" in "$tier"/*) n=$((n + 1)) ;; esac
  done
  printf '%s\n' "$n"
}
