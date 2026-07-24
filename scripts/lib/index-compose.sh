#!/usr/bin/env bash
# Tier index composition (D17 slice 3-ii). Splices each ACTIVE tier's carrier
# bullets into the root MEMORY.md (prefix-added) and mirrors root-authored tier
# bullets back down into every MOUNTED tier's carrier (prefix-stripped).
#
# Composition is PLACEMENT ONLY: it never edits a bullet's text, never touches
# project bullets, never creates or deletes a memory file. Line identity is the
# path prefix — no sentinel text is injected into any index.

# Print the path of a pointer bullet; return 1 if $1 is not one. A bullet is
# `- [` ... `](` PATH `)` ... — the hook (if any) is irrelevant here. Pure
# parameter expansion: no field splitting, so a path or title containing
# whitespace is safe.
gitlore_bullet_path() {
  local line="$1" rest path
  case "$line" in
    '- ['*) ;;
    *) return 1 ;;
  esac
  case "$line" in
    *']('*) ;;
    *) return 1 ;;
  esac
  rest=${line#*](}                 # "foo.md) — hook"
  case "$rest" in
    *')'*) ;;
    *) return 1 ;;
  esac
  path=${rest%%)*}
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

# Print $1 with "$2/" inserted before its path. Return 1 if $1 is not a bullet.
gitlore_bullet_reprefix() {
  local line="$1" prefix="$2" left rest path tail
  gitlore_bullet_path "$line" >/dev/null || return 1
  left=${line%%](*}                # "- [Title"
  rest=${line#*](}                 # "foo.md) — hook"
  path=${rest%%)*}
  tail=${rest#*)}                  # " — hook"
  printf '%s](%s/%s)%s\n' "$left" "$prefix" "$path" "$tail"
}

# Print $1 with a leading "$2/" removed from its path. Return 1 if $1 is not a
# bullet or its path does not carry that prefix.
gitlore_bullet_deprefix() {
  local line="$1" prefix="$2" left rest path tail
  path=$(gitlore_bullet_path "$line") || return 1
  case "$path" in
    "$prefix"/*) ;;
    *) return 1 ;;
  esac
  left=${line%%](*}
  rest=${line#*](}
  tail=${rest#*)}
  printf '%s](%s)%s\n' "$left" "${path#"$prefix"/}" "$tail"
}

# Print "FIRST LAST", the 1-indexed line numbers of the first and last pointer
# bullet in $1, or "0 0" when there are none. Space-separated so callers can
# `read` the pair instead of doing tab arithmetic in a parameter expansion.
gitlore_index_region() {
  local line first=0 last=0 n=0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if gitlore_bullet_path "$line" >/dev/null; then
      [ "$first" -eq 0 ] && first=$n
      last=$n
    fi
  done < "$1"
  printf '%s %s\n' "$first" "$last"
}

# Print one part of an index: "preamble" (before the first bullet), "bullets"
# (the region between the first and last bullet, inclusive), or "trailer"
# (after the last bullet). A bulletless index is ALL preamble — which is the
# day-one state of a freshly seeded tier carrier.
gitlore_index_part() {
  local file="$1" part="$2" first last
  read -r first last < <(gitlore_index_region "$file")
  if [ "$first" -eq 0 ]; then
    case "$part" in
      preamble) cat "$file" ;;
      *) : ;;
    esac
    return 0
  fi
  case "$part" in
    preamble) [ "$first" -gt 1 ] && sed -n "1,$((first - 1))p" "$file" ;;
    bullets)  sed -n "$first,${last}p" "$file" ;;
    trailer)  sed -n "$((last + 1)),\$p" "$file" ;;
  esac
  return 0
}

# Print the first path component of $1 when it names a tier listed in the
# newline-separated $2; return 1 otherwise (a bare path, or a prefix that
# matches no mounted tier).
gitlore_tier_of() {
  local path="$1" tiers="$2" head t
  case "$path" in
    */*) head=${path%%/*} ;;
    *) return 1 ;;
  esac
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    [ "$t" = "$head" ] && { printf '%s\n' "$head"; return 0; }
  done <<EOF
$tiers
EOF
  return 1
}

# Print one problem per line and return 1 when $1's store cannot be composed
# safely; print nothing and return 0 otherwise. Every problem is reported, not
# just the first: a user fixing a broken store wants the whole list.
#
# The four rules (D17 3-ii):
#   1. no duplicate pointer path within any single index;
#   2. every manifest entry names a MOUNTED tier;
#   3. every root bullet with a "/" names a mounted tier — an unattributable
#      prefix has no carrier to survive in, so dropping it would be data loss;
#   4. no non-blank non-bullet line inside an index's bullet region — the
#      layout rule would relocate it and lose its position.
gitlore_compose_check() {
  local mempath="$1" mounted active problems="" tier file found
  mounted=$(gitlore_tier_paths "$mempath")
  active=$(gitlore_active_tiers "$mempath")

  # Rule 2 — a listed tier must be mounted.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    if ! printf '%s\n' "$mounted" | grep -qxF -- "$tier"; then
      problems="${problems}the tier manifest lists '$tier', which is not mounted in $mempath/.gitmodules
"
    fi
  done <<EOF
$active
EOF

  # Rules 1 and 4 — for the root index and every mounted tier carrier. The
  # capture drops the helper's trailing newline, so each non-empty batch gets
  # one back: without it the last problem from one index and the first from the
  # next share a line. An empty capture must NOT add one — a lone newline would
  # make $problems non-empty and refuse a healthy store with no message.
  file="$mempath/MEMORY.md"
  if [ -f "$file" ]; then
    found=$(gitlore_compose_check_index "$file")
    if [ -n "$found" ]; then
      problems="${problems}${found}
"
    fi
  fi
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    found=$(gitlore_compose_check_index "$mempath/$tier/MEMORY.md")
    if [ -n "$found" ]; then
      problems="${problems}${found}
"
    fi
  done <<EOF
$mounted
EOF

  # Rule 3 — root bullets only; a carrier's own bullets are bare by construction.
  if [ -f "$mempath/MEMORY.md" ]; then
    local line path
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in */*) ;; *) continue ;; esac
      if ! gitlore_tier_of "$path" "$mounted" >/dev/null; then
        problems="${problems}root index line '$path' has a prefix naming no mounted tier — it is a leftover from a removed tier and must be fixed by hand
"
      fi
    done < "$mempath/MEMORY.md"
  fi

  [ -z "$problems" ] && return 0
  printf '%s' "$problems" | grep -v '^$'
  return 1
}

# Rules 1 and 4 for a single index file. Prints problems; always returns 0 (the
# caller aggregates).
gitlore_compose_check_index() {
  local file="$1" first last n=0 line path seen=""
  read -r first last < <(gitlore_index_region "$file")
  [ "$first" -eq 0 ] && return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if path=$(gitlore_bullet_path "$line"); then
      if printf '%s\n' "$seen" | grep -qxF -- "$path"; then
        printf '%s: duplicate pointer path %s\n' "$file" "$path"
      fi
      seen="$seen
$path"
    elif [ "$n" -gt "$first" ] && [ "$n" -lt "$last" ] && [ -n "${line//[[:space:]]/}" ]; then
      printf '%s: interleaved non-bullet line %s inside the pointer block\n' "$file" "$n"
    fi
  done < "$file"
  return 0
}

# Print one report line per pointer bullet whose target file is absent; return 0
# either way. This is the fifth compose validation, and the only one that
# REPORTS instead of refusing: a dangling line does not make the composed output
# wrong, and refusing would block every later index write over a stale line the
# agent can fix in one edit.
#
# Under presence-authority (D17) the index says what memory CONTAINS, so the
# missing FILE is the anomaly, not the line — which is why nothing here touches
# either surface. Reporting is the whole job.
gitlore_compose_dangling() {
  local mempath="$1" mounted tier file line path reported=""

  file="$mempath/MEMORY.md"
  if [ -f "$file" ]; then
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      [ -e "$mempath/$path" ] && continue
      printf '%s: %s names no file in the memory store\n' "$file" "$path"
      reported="$reported
$path"
    done < "$file"
  fi

  # Carrier lines too: a DORMANT tier's bullets never reach the root, so a
  # root-only scan would leave them unchecked for as long as the tier sleeps.
  mounted=$(gitlore_tier_paths "$mempath")
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    file="$mempath/$tier/MEMORY.md"
    [ -f "$file" ] || continue
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      [ -e "$mempath/$tier/$path" ] && continue
      # An active tier's line lives in both indexes and resolves to one file;
      # report the root's copy only, since that is the surface the agent edits.
      printf '%s\n' "$reported" | grep -qxF -- "$tier/$path" && continue
      printf '%s: %s names no file in the tier\n' "$file" "$path"
    done < "$file"
  done <<EOF
$mounted
EOF
  return 0
}

# Print the merged bullet list for tier $2 under store $1, unprefixed and in
# carrier order with root-only lines appended. The ROOT's text wins on a path
# present in both: the root index is canonical for a line's text (D17).
gitlore_compose_tier_bullets() {
  local mempath="$1" tier="$2"
  local carrier="$mempath/$tier/MEMORY.md"
  local root="$mempath/MEMORY.md"
  local line path stripped rootline seen=""

  # Root bullets belonging to this tier, prefix stripped, keyed by path.
  local rootbullets=""
  if [ -f "$root" ]; then
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in "$tier"/*) ;; *) continue ;; esac
      stripped=$(gitlore_bullet_deprefix "$line" "$tier") || continue
      rootbullets="$rootbullets$stripped
"
    done < "$root"
  fi

  # Carrier order first; each line replaced by the root's version when present.
  if [ -f "$carrier" ]; then
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      rootline=$(printf '%s' "$rootbullets" | gitlore_compose_pick "$path")
      if [ -n "$rootline" ]; then printf '%s\n' "$rootline"; else printf '%s\n' "$line"; fi
      seen="$seen
$path"
    done < <(gitlore_index_part "$carrier" bullets)
  fi

  # Then root-only lines, in root order.
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    path=$(gitlore_bullet_path "$line") || continue
    printf '%s\n' "$seen" | grep -qxF -- "$path" && continue
    printf '%s\n' "$line"
  done <<EOF
$rootbullets
EOF
}

# Filter stdin (bullets) to the first one whose path is $1. Helper for the
# merge above; keeps the path comparison out of a subshell-heavy inline loop.
gitlore_compose_pick() {
  local want="$1" line path
  while IFS= read -r line; do
    path=$(gitlore_bullet_path "$line") || continue
    if [ "$path" = "$want" ]; then printf '%s\n' "$line"; return 0; fi
  done
  return 0
}

# Replace $1's bullet region with the bullets on stdin, preserving preamble and
# trailer. Writes only when the result differs, so an already-canonical index
# produces no churn; prints "composed <file>" when it did write.
gitlore_compose_write() {
  local file="$1" tmp="$1.gitlore-compose.tmp" bullets
  bullets=$(cat)
  {
    gitlore_index_part "$file" preamble
    [ -n "$bullets" ] && printf '%s\n' "$bullets"
    gitlore_index_part "$file" trailer
  } > "$tmp" || { rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 0
  fi
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  printf 'composed %s\n' "$file"
}

# The whole pass. Validates first; on any problem prints the problems, writes
# nothing, and returns 1 — fail-safe, so a broken store is never half-rewritten.
# Otherwise mirrors down into every MOUNTED tier (a dormant tier still receives
# its root lines: dropping them would be data loss, not dormancy — the same rule
# the commit/push lockstep applies) and splices up every ACTIVE tier.
#
# Return codes are three, not two, because "nothing was written" and "some of it
# was" need different words from every caller:
#   0 — composed (stdout: one "composed <file>" line per index rewritten)
#   1 — validation refused; nothing written (stdout: the problems)
#   2 — a write FAILED partway; earlier writes stand (stdout: what was written,
#       then the file that could not be)
# Code 2 exists because a write's status is otherwise invisible here: the writes
# ran inside a command substitution feeding a string append, and every caller
# invokes this function as an `if` condition, which disables errexit for the
# whole call — so a failed `mv` or a full disk reported success and left the
# tier index silently unchanged.

# Run gitlore_compose + gitlore_compose_dangling and, when $2 is non-empty,
# the post-mount triage nudge — then set GITLORE_COMPOSE_SYSMSG and
# GITLORE_COMPOSE_CTX (either may end up empty: nothing worth reporting).
# Shared by the PostToolBatch recompose hook (cc-hooks/index-compose.sh, which
# detects a touch via .tool_calls[]) and add-tier-batch.sh (which writes the
# manifest itself, outside any tool call, and so has nothing for that detection
# to see — it calls this directly instead, with $2 always set).
# Depends on gitlore_active_tier_scopes (util.sh) and
# gitlore_get_frontmatter_description (index-sync.sh); callers must source both.
# Args: $1 = mempath, $2 = non-empty when the manifest changed this batch.
gitlore_compose_and_report() {
  local mempath="$1" manifest_touched="$2"
  local sysmsg="" ctx="" compose_rc=0 result

  result=$(gitlore_compose "$mempath") || compose_rc=$?
  if [ "$compose_rc" -eq 0 ]; then
    if [ -n "$result" ]; then
      local n unit
      n=$(printf '%s\n' "$result" | grep -c '^composed ')
      if [ "$n" -eq 1 ]; then unit="index"; else unit="indexes"; fi
      sysmsg="gitlore: recomposed tier pointers ($n $unit)"
      ctx="The gitlore tier composition rewrote these indexes to place each active tier's pointer block ahead of the project's own lines, and mirrored root-authored tier lines down into their carrier. This is expected and complete — do not re-read or re-edit them to verify. Composition moves lines only; it never changes a line's text.
$result"
    fi

    # The fifth validation reports rather than refuses, so it runs on the
    # composed store and rides the same message whether or not anything wrote.
    local dangling d dunit
    dangling=$(gitlore_compose_dangling "$mempath")
    if [ -n "$dangling" ]; then
      d=$(printf '%s\n' "$dangling" | grep -c .)
      if [ "$d" -eq 1 ]; then dunit="pointer"; else dunit="pointers"; fi
      sysmsg="${sysmsg:+$sysmsg
}gitlore: $d dangling index $dunit — a line names a file that is not there"
      ctx="${ctx:+$ctx

}These memory index lines point at files that do not exist. Nothing was rewritten or deleted: the index is authoritative over what memory contains, so a line outliving its file is a stale pointer to fix, not a reason to refuse the pass. Either restore the file or remove the line — removing it deletes nothing.
$dangling"
    fi

    # Post-mount triage nudge (D17 triage-automation design): the active-tier
    # set may just have changed, so gate on the manifest specifically, not any
    # compose. Scopes come from the live frontmatter of each active tier —
    # never a fixed dichotomy — so this reads correctly whether one tier is
    # active or several, and whatever each one's own scope says.
    if [ -n "$manifest_touched" ]; then
      local scopes n2 tunit scope_lines
      scopes=$(gitlore_active_tier_scopes "$mempath")
      if [ -n "$scopes" ]; then
        n2=$(printf '%s\n' "$scopes" | grep -c .)
        if [ "$n2" -eq 1 ]; then tunit="tier"; else tunit="tiers"; fi
        sysmsg="${sysmsg:+$sysmsg
}gitlore: active-tier set changed ($n2 $tunit) — triage local memory against their scopes"
        scope_lines=$(printf '%s\n' "$scopes" | sed 's/^/  - /')
        ctx="${ctx:+$ctx

}gitlore: the active-tier set just changed. For each fact in your LOCAL memory (a bare-path \`- [Title](file.md)\` line in $mempath/MEMORY.md), judge which active tier's scope best covers it — using each tier's OWN scope below, not a fixed rule:
$scope_lines
Route the best-fit ones up: \`mv\` the file into that tier's directory, and reprefix its root index line to \`<tier>/<file>.md\`. A fact no active tier's scope covers stays local. Do not move a fact already in a tier."
      fi
    fi
  elif [ "$compose_rc" -eq 2 ]; then
    # A write failed partway, so the fail-safe promise does NOT hold here: some
    # indexes are composed and at least one is not.
    sysmsg="gitlore: tier composition could not write an index — the memory indexes are only partly composed:
$result"
    ctx="gitlore tier composition failed while writing. Unlike a refusal, this leaves the memory indexes PARTLY composed: everything listed as composed was written, and the file named after them was not. Investigate that path (permissions, disk space, a read-only worktree), then edit MEMORY.md or memory/.gitlore-tiers again to retrigger the pass:
$result"
  else
    # Fail-safe: nothing was written. Never surfaced with a non-zero hook exit —
    # stdout JSON parses on exit 0 only, so a non-zero exit would DISCARD this
    # message and make the failure less visible, not more (D14).
    sysmsg="gitlore: tier composition refused — the memory indexes were left untouched:
$result"
    ctx="gitlore tier composition refused and wrote nothing. Fix the store by hand, then edit MEMORY.md or memory/.gitlore-tiers again to retrigger it. Problems:
$result"
  fi

  # shellcheck disable=SC2034
  GITLORE_COMPOSE_SYSMSG="$sysmsg"
  # shellcheck disable=SC2034
  GITLORE_COMPOSE_CTX="$ctx"
}

gitlore_compose() {
  local mempath="$1"
  local root="$mempath/MEMORY.md"
  local mounted active tier line path changed="" out
  [ -f "$root" ] || return 0

  if ! gitlore_compose_check "$mempath"; then
    return 1
  fi

  mounted=$(gitlore_tier_paths "$mempath")
  active=$(gitlore_active_tiers "$mempath")

  # Mirror down — every mounted tier with a checked-out carrier.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    if ! out=$(gitlore_compose_tier_bullets "$mempath" "$tier" \
      | gitlore_compose_write "$mempath/$tier/MEMORY.md"); then
      [ -n "$changed" ] && printf '%s' "$changed"
      printf 'could not write %s\n' "$mempath/$tier/MEMORY.md"
      return 2
    fi
    changed="$changed$out
"
  done <<EOF
$mounted
EOF

  # Splice up — active tiers in manifest order, then the project's own bullets.
  if ! out=$( {
    while IFS= read -r tier; do
      [ -n "$tier" ] || continue
      [ -f "$mempath/$tier/MEMORY.md" ] || continue
      while IFS= read -r line; do
        [ -n "$line" ] || continue
        gitlore_bullet_reprefix "$line" "$tier"
      done < <(gitlore_index_part "$mempath/$tier/MEMORY.md" bullets)
    done <<INNER
$active
INNER
    while IFS= read -r line; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in */*) continue ;; esac
      printf '%s\n' "$line"
    done < <(gitlore_index_part "$root" bullets)
  } | gitlore_compose_write "$root" ); then
    [ -n "$changed" ] && printf '%s' "$changed"
    printf 'could not write %s\n' "$root"
    return 2
  fi
  changed="$changed$out"

  [ -n "$changed" ] && printf '%s\n' "$changed"
  return 0
}
