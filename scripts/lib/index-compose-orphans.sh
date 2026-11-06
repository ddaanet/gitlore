#!/usr/bin/env bash
# Compose-orphans: the orphan report, the path-presence test and the line picker
# the compose-up and the entry-wise merge share. Part of lib/index-compose.sh;
# source that, not this file.

# Print one report line per ACTIVE tier carrier path that the composed root index
# does not carry; return 0 either way. Run AFTER a pass, like the dangling report
# and for the same reason: it describes the store as it now stands.
#
# A carrier line reaches the root unless root already had a block for that tier
# and never mentioned this path — a line written straight into the carrier, or
# one left there while the tier slept. Nothing is rewritten or dropped over it:
# it is a line whose two surfaces disagree about whether the fact is in play
# here, and which way to settle that is the agent's call, not the pass's. Either
# way is one edit, and the line names both: a carrier path that root at HEAD
# carries never survives a pass (the down projection reads it as root's
# deletion), so every orphan is one root never committed, and deleting it from
# the carrier is final.
gitlore_compose_orphans() {
  local mempath="$1" active tier line path
  active=$(gitlore_active_tiers "$mempath")
  [ -f "$mempath/MEMORY.md" ] || return 0
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      gitlore_index_has_path "$mempath/MEMORY.md" "$tier/$path" && continue
      # shellcheck disable=SC2016 # the backticks are report text, not a substitution
      printf '%s: %s is in the tier but not in the root index — delete its line from %s, or add `%s` to %s to recall it here\n' \
        "$mempath/$tier/MEMORY.md" "$path" "$mempath/$tier/MEMORY.md" \
        "$(gitlore_bullet_reprefix "$line" "$tier")" "$mempath/MEMORY.md"
    done < <(gitlore_index_part "$mempath/$tier/MEMORY.md" bullets)
  done <<EOF
$active
EOF
  return 0
}

# Return 0 when index $1 carries a pointer line for exactly path $2.
gitlore_index_has_path() {
  local file="$1" want="$2" line path
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    path=$(gitlore_bullet_path "$line") || continue
    [ "$path" = "$want" ] && return 0
  done < "$file"
  return 1
}

# Filter stdin (bullets) to the first one whose path is $1. Helper for the
# merge above; keeps the path comparison out of a subshell-heavy inline loop.
gitlore_compose_pick() {
  local want="$1" line path
  while IFS= read -r line || [ -n "$line" ]; do
    path=$(gitlore_bullet_path "$line") || continue
    if [ "$path" = "$want" ]; then printf '%s\n' "$line"; return 0; fi
  done
  return 0
}
