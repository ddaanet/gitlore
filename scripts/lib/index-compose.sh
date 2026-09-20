#!/usr/bin/env bash
# Tier index composition (D17 slice 3-ii). Splices each ACTIVE tier's carrier
# bullets into the root MEMORY.md (prefix-added) and mirrors root-authored tier
# bullets back down into every MOUNTED tier's carrier (prefix-stripped).
#
# Composition is PLACEMENT ONLY: it never edits a bullet's text, never touches
# project bullets, never creates or deletes a memory file. Line identity is the
# path prefix — no sentinel text is injected into any index.
#
# Every index read carries `|| [ -n "$line" ]`, without exception. An index whose
# last line has no newline is never gitlore's own output — gitlore_compose_write
# terminates what it writes — but a hand edit, an agent `Edit` call or another
# consumer's writer leaves one behind and the store travels that way. A bare
# `read` fills $line and then returns non-zero at EOF, so that line is read and
# discarded: it vanishes from the path list, and gitlore_order_merge reads its
# absence on one side as that side having deleted it. Losing the line from an
# index is losing the fact, since the index is what memory contains (D17). A
# guard on only the reads whose loss is currently visible is what produced the
# defect — the region arithmetic counted a line the projection could not see.
#
# The library is split into index-compose-*.sh parts, each function-only and
# safe to source twice, that this file sources below:
#   index-compose-check.sh    gitlore_compose_check's four rules, welded-line
#                              detection, and rule 7 (a tier off its pin)
#   index-compose-repair.sh   the mechanical rewrite for a compose-check problem
#   index-compose-project.sh  the dangling/orphan reports and the down/up
#                              projection between root and a tier's carrier

# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/index-compose-check.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/index-compose-repair.sh"
# shellcheck disable=SC1091
source "${BASH_SOURCE[0]%/*}/index-compose-project.sh"

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

# Print the merged ORDER of pointer paths for a three-way merge, one per line,
# each path once. Args: $1/$2/$3 = base/ours/theirs path-list files.
#
# Order is a merge INPUT, not a rule applied afterwards: each side states where
# its entries go, and both statements are honoured, so an insertion keeps the
# offset its author chose instead of being appended to the block. Only a genuine
# disagreement about ONE offset needs a tiebreak, and `--union` is it — ours'
# block, then theirs'. Marking that as a conflict would sit a human in front of
# two facts nothing is actually disputing.
#
# The lists are PATHS only, never whole bullets. Feeding text in would make
# every reworded hook a positional edit: a routine description change would
# relocate its entry and collide with an unrelated insertion beside it.
#
# `--union` can emit one path twice, when the two sides placed it differently.
# The first occurrence wins, which is ours' offset.
gitlore_order_merge() {
  local basef="$1" oursf="$2" theirsf="$3" merged mrc=0
  # merge-file returns the conflict COUNT; --union resolves every one of them, so
  # only git's own -1 (a merge it could not attempt) is a failure here.
  merged=$(git merge-file -p --union "$oursf" "$basef" "$theirsf") || mrc=$?
  [ "$mrc" -ge 128 ] && return 1
  printf '%s\n' "$merged" | awk 'length($0) && !seen[$0]++'
  return 0
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

# Replace $1's bullet region with the bullets on stdin, preserving preamble and
# trailer. Writes only when the result differs, so an already-canonical index
# produces no churn; prints "composed <file>" when it did write.
gitlore_compose_write() {
  local file="$1" tmp bullets
  # Inside the store's own gitdir, not beside the target: the same reason
  # gitlore_weld_repair (edit-weld.sh) gives for its own scratch file — a kill
  # between this write and the mv/rm below would otherwise leave an untracked
  # neighbour inside the tracked worktree for the FR11 gate's `git add -A` to
  # sweep up. `$$`: this runs per-store, but never assume only one caller.
  # `--absolute-git-dir`, not `--git-path`: the latter is relative to the `-C`
  # dir for a plain repo, and the caller's cwd is not that dir.
  tmp=$(git -C "$(dirname -- "$file")" rev-parse --absolute-git-dir) \
    && tmp="$tmp/gitlore-compose.tmp.$$" || return 1
  bullets=$(cat)
  gitlore_index_part "$file" preamble > "$tmp" || { rm -f "$tmp"; return 1; }
  # A bulletless index is ALL preamble, emitted verbatim — so one that arrived
  # unterminated would take the first bullet onto the end of its last line, and a
  # glued line is not a bullet: the pointer would be lost on write. Only ever a
  # separator, never normalisation — with no bullets there is nothing to separate
  # and the file is left exactly as it came.
  if [ -n "$bullets" ] && [ -s "$tmp" ] &&
     [ "$(tail -c 1 "$tmp" | wc -l | tr -d ' ')" = 0 ]; then
    printf '\n' >> "$tmp" || { rm -f "$tmp"; return 1; }
  fi
  {
    [ -n "$bullets" ] && printf '%s\n' "$bullets"
    gitlore_index_part "$file" trailer
  } >> "$tmp" || { rm -f "$tmp"; return 1; }
  if cmp -s "$tmp" "$file"; then
    rm -f "$tmp"
    return 0
  fi
  mv "$tmp" "$file" || { rm -f "$tmp"; return 1; }
  printf 'composed %s\n' "$file"
}

# The whole in-session pass. Validates first; on any problem prints the problems,
# writes nothing, and returns 1 — fail-safe, so a broken store is never
# half-rewritten. Otherwise it projects root's lines DOWN into every ACTIVE
# tier's carrier, then rewrites the root index's layout.
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
# Depends on gitlore_active_tier_scopes (util-config.sh) and
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
      ctx="The gitlore tier composition rewrote these indexes to place each active tier's pointer block ahead of the project's own lines, and projected root-authored tier lines down into their carrier — including deletions, so removing a tier fact's line from the root index is enough; its carrier copy goes in this same pass, not left for you to also edit by hand. This is expected and complete — do not re-read or re-edit them to verify. Composition places, drops and re-texts carrier lines to match the root index; the root index's own lines are only reordered, never re-texted.
$result"
    fi

    # Carrier lines the root index does not carry. Reported, never resolved:
    # which surface is right is a judgement about the fact, not about placement.
    local orphans o ounit orphans_capped
    orphans=$(gitlore_compose_orphans "$mempath")
    if [ -n "$orphans" ]; then
      o=$(printf '%s\n' "$orphans" | grep -c .)
      if [ "$o" -eq 1 ]; then ounit="line"; else ounit="lines"; fi
      orphans_capped=$(printf '%s\n' "$orphans" | gitlore_cap_list)
      sysmsg="${sysmsg:+$sysmsg
}gitlore: $o tier index $ounit not in the root index"
      ctx="${ctx:+$ctx

}These lines are in an active tier's own index but not in the root index ($o total), so they are not recallable here and nothing propagates them: composition projects the ROOT down, and root never carried them. Nothing was rewritten or deleted. Either add the line to $mempath/MEMORY.md with its tier prefix — \`- [Title](<tier>/<file>.md) — hook\` — if the fact belongs in this repo, or remove it from the tier's index if it does not.
$orphans_capped"
    fi

    # The fifth validation reports rather than refuses, so it runs on the
    # composed store and rides the same message whether or not anything wrote.
    local dangling d dunit dangling_capped
    dangling=$(gitlore_compose_dangling "$mempath")
    if [ -n "$dangling" ]; then
      d=$(printf '%s\n' "$dangling" | grep -c .)
      if [ "$d" -eq 1 ]; then dunit="pointer"; else dunit="pointers"; fi
      dangling_capped=$(printf '%s\n' "$dangling" | gitlore_cap_list)
      sysmsg="${sysmsg:+$sysmsg
}gitlore: $d dangling index $dunit — a line names a file that is not there"
      ctx="${ctx:+$ctx

}These memory index lines point at files that do not exist ($d total). Nothing was rewritten or deleted: the index is authoritative over what memory contains, so a line outliving its file is a stale pointer to fix, not a reason to refuse the pass. Either restore the file or remove the line — removing it deletes nothing.
$dangling_capped"
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
Route the best-fit ones up: \`mv\` the file into that tier's directory, and reprefix its root index line to \`<tier>/<file>.md\`. A fact no active tier's scope covers stays local. Do not move a fact already in a tier.
Invoke the \`gitlore:memory-writing\` skill before judging: promotion turns on whether the fact's mechanism depends on this repo or only on this repo being a member of a class, and a promoted fact's \`[[links]]\` to project-local siblings go dead in every other consumer of the tier."
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
  local active tier changed="" out
  [ -f "$root" ] || return 0

  # Both checks run before either verdict is read, so one refusal carries the
  # whole list. Rule 7 is here rather than in gitlore_compose_check because it
  # guards the down projection specifically (see gitlore_compose_check_pins).
  local refused=0
  gitlore_compose_check "$mempath" || refused=1
  gitlore_compose_check_pins "$mempath" || refused=1
  [ "$refused" -eq 0 ] || return 1

  active=$(gitlore_active_tiers "$mempath")

  # Down first, then the root layout. The order is load-bearing: the layout pass
  # adopts a carrier for any active tier root has no line for, and deleting a
  # tier's last root line must not resurrect its block. Running down first means
  # those carrier lines are already gone when the layout reads it.
  #
  # ACTIVE tiers only. Root does not represent a dormant tier — it holds no line
  # for one — so it has no authority over that tier's carrier, and projecting an
  # empty opinion down would delete a whole store's index.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    # Root with no line at all for this tier states nothing about it — the same
    # condition the layout pass adopts on, and projecting an absence down here
    # would empty the carrier a moment before the layout reads it. That is what
    # a mount, and a deactivate/reactivate round trip, both look like.
    gitlore_index_has_tier "$root" "$tier" || continue
    if ! out=$(gitlore_compose_down "$mempath" "$tier" \
      | gitlore_compose_write "$mempath/$tier/MEMORY.md"); then
      [ -n "$changed" ] && printf '%s' "$changed"
      printf 'could not write %s\n' "$mempath/$tier/MEMORY.md"
      return 2
    fi
    changed="$changed$out
"
  done <<EOF
$active
EOF

  if ! out=$(gitlore_compose_root_bullets "$mempath" | gitlore_compose_write "$root"); then
    [ -n "$changed" ] && printf '%s' "$changed"
    printf 'could not write %s\n' "$root"
    return 2
  fi
  changed="$changed$out"

  [ -n "$changed" ] && printf '%s\n' "$changed"
  return 0
}
