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
# Rule 6 (the welded line) is checked per index below; rule 7 (an active tier
# off its pin) is the down pass's alone and lives in gitlore_compose_check_pins,
# which this function does not call.
gitlore_compose_check() {
  local mempath="$1" mounted active problems="" tier file found
  mounted=$(gitlore_tier_paths "$mempath")
  active=$(gitlore_active_tiers "$mempath")

  # Rule 2 — a listed tier must be mounted.
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    # A here-string, not a pipe: under `set -o pipefail` (every caller), `grep
    # -q` exiting at its first match sends the producer SIGPIPE, and a healthy
    # store gets misread as refused (index-sync.sh:186-189 fixed the same shape).
    if ! grep -qxF -- "$tier" <<<"$mounted"; then
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
    while IFS= read -r line || [ -n "$line" ]; do
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

# Print the path of a SECOND pointer bullet welded onto line $1; return 1 when
# there is none. Keyed on the first link's closing paren rather than on the
# `) — ` separator, so glue that lands ahead of the first hook — leaving no
# separator between the two links at all — is still caught.
#
# No backtick-awareness, by policy rather than by parsing: a hook has no
# legitimate use for a bare markdown hyperlink, since the entry already links
# its own file. Residual, accepted: a hook quoting an index-format example is
# reported spuriously, which is visible and repairable. awk has no
# backreferences and POSIX leaves them undefined in EREs, so a balanced-span
# pattern would force this check out of the idiom the rest of the index parsing
# uses — to buy a guarantee the policy already gives.
gitlore_welded_path() {
  local line="$1" tail second
  gitlore_bullet_path "$line" >/dev/null || return 1
  tail=${line#*](}
  tail=${tail#*)}                  # everything past the first link
  case "$tail" in
    *"- ["*) ;;
    *) return 1 ;;
  esac
  second="- [${tail#*"- ["}"
  gitlore_bullet_path "$second"
}

# Rules 1, 4 and 6 for a single index file. Prints problems; always returns 0
# (the caller aggregates).
gitlore_compose_check_index() {
  local file="$1" first last n=0 line path welded seen=""
  read -r first last < <(gitlore_index_region "$file")
  [ "$first" -eq 0 ] && return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    if path=$(gitlore_bullet_path "$line"); then
      # Rule 6 — a welded line parses as ONE valid bullet for its first path,
      # so nothing else here sees it, and the second path is absent from every
      # parse: the next compose reads that absence as a root-side delete and
      # drops the entry from the carrier. Observed in the wild. This is not
      # defence in depth — it is the only thing between a one-character edit
      # accident and a silent index deletion.
      if welded=$(gitlore_welded_path "$line"); then
        printf '%s: line %d welds two pointer bullets onto one line — %s is invisible to every parse and the next compose will drop it; split them\n' \
          "$file" "$n" "$welded"
      fi
      # Here-string, not a pipe — see the same note at gitlore_compose_check above.
      if grep -qxF -- "$path" <<<"$seen"; then
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

# Rule 7 — every ACTIVE tier sits at the commit the memory store records for it.
# Print one problem per moved tier and return 1; print nothing and return 0
# otherwise. Depends on gitlore_active_tiers and gitlore_merge_state_file
# (util.sh); callers already source it.
#
# The down projection is safe only because a pinned tier cannot have moved on
# its own, which is what leaves one projection to move between passes (D36). A
# tier advanced outside /gitlore:merge breaks that: nothing adopted the carrier's
# newer text up into the root, so the next pass writes root's OLDER text over it
# and reports a successful compose. That is a silent overwrite of approved
# upstream facts, so this refuses rather than reports.
#
# It lives OUTSIDE gitlore_compose_check, and only gitlore_compose calls it,
# because the rule belongs to the down pass alone. gitlore_compose_up adopts a
# carrier at the end of a landed merge, where the tier is legitimately ahead of
# the pin and the staging that restores it comes after the adoption — a
# parameter on the shared check would leave the merge path one argument away
# from refusing the very state it exists to land, where a function the up path
# never calls makes the scope structural.
#
# The pin is read from the memory store's INDEX (`:$tier`), not from
# `HEAD:$tier`: `submodule update` checks a tier out at the sha the index holds,
# and every path that advances a tier stages the moved gitlink there as its last
# act (D43). Reading HEAD would call a landed merge a defect for as long as the
# memory commit recording it is pending.
gitlore_compose_check_pins() {
  local mempath="$1" active tier tierpath pinned head abs problems=""
  active=$(gitlore_active_tiers "$mempath")
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    # `git -C` into an unmaterialized submodule walks up to the enclosing repo,
    # which would answer for memory's own HEAD under the tier's name.
    [ -e "$tierpath/.git" ] || continue
    # `-q --verify` is silent on the expected miss: no gitlink for this tier in
    # the index at all — mid-mount, or removed — which this rule has no opinion
    # about. Same for a store with no HEAD yet.
    pinned=$(git -C "$mempath" rev-parse -q --verify ":$tier") || continue
    head=$(git -C "$tierpath" rev-parse -q --verify HEAD) || continue
    [ "$head" = "$pinned" ] && continue
    # Mid-merge takes a different remedy: the return-to-the-pin checkout below
    # unlinks MERGE_HEAD and destroys the prepared merge. The predicate is
    # gitlore_detect_stale_merge_state's own "not clean" — state file or
    # MERGE_HEAD — spelled out rather than called, because that function lives in
    # resolve.sh and resolve.sh sources this file.
    if [ -f "$(gitlore_merge_state_file "$tierpath")" ] \
       || git -C "$tierpath" rev-parse -q --verify MERGE_HEAD >/dev/null; then
      problems="${problems}tier '$tier' is mid-merge and sits off the commit the memory store records for it; run /gitlore:resolve to land the merge before the indexes can be composed
"
      continue
    fi
    # Absolute, so the printed command runs from anywhere; quoted, so a tier path
    # containing whitespace survives being pasted into a shell.
    abs=$(CDPATH='' cd -- "$tierpath" && pwd) || abs="$tierpath"
    # Truncated by parameter expansion rather than `rev-parse --short`: the
    # pinned commit need not exist in either store's object database.
    problems="${problems}tier '$tier' is checked out at ${head:0:12} but the memory store records ${pinned:0:12}: it was moved outside /gitlore:merge, and projecting the root index onto it would overwrite what it holds. Return it to the pin with \`git -C \"$abs\" checkout --detach $pinned\`, then run /gitlore:merge to take upstream properly.
"
  done <<EOF
$active
EOF

  [ -z "$problems" ] && return 0
  printf '%s' "$problems" | grep -v '^$'
  return 1
}

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
  # function exists to add (same shape gitlore_index_largest already avoids).
  printf '%s\n' "$input" | awk -v n="$GITLORE_DANGLING_CAP" 'NR<=n'
  if [ "$total" -gt "$GITLORE_DANGLING_CAP" ]; then
    printf '… and %d more\n' "$((total - GITLORE_DANGLING_CAP))"
  fi
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
    while IFS= read -r line || [ -n "$line" ]; do
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
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      [ -e "$mempath/$tier/$path" ] && continue
      # An active tier's line lives in both indexes and resolves to one file;
      # report the root's copy only, since that is the surface the agent edits.
      # Here-string, not a pipe — see the same note at gitlore_compose_check above.
      grep -qxF -- "$tier/$path" <<<"$reported" && continue
      printf '%s: %s names no file in the tier\n' "$file" "$path"
    done < "$file"
  done <<EOF
$mounted
EOF
  return 0
}

# Print tier $2's new carrier bullet list, unprefixed: root's lines for that tier,
# projected DOWN. Root is canonical (D17), so every line root carries is emitted
# with root's text and root's placement — this is where a line authored in the
# root index becomes a line the tier can travel with.
#
# A tier is pinned at its gitlink, so the carrier cannot have moved on its own
# since the memory commit that recorded both surfaces — and when one has,
# gitlore_compose_check_pins refuses the whole pass, because root's older text
# would otherwise land on a carrier nothing had adopted up. What is left to
# decide is a carrier path root does not carry, and "root lacks it" alone is
# ambiguous — root may have deleted it, or may never have had it. Root at HEAD
# answers:
#
#   present there → root deleted the line → drop it from the carrier;
#   absent there  → nobody authored it in root → keep it (a line written straight
#                   into the carrier, or one left there while the tier slept),
#                   and gitlore_compose_orphans names it.
#
# One lookup against a commit git already holds. Nothing is remembered between
# passes: a reconciliation ref would be state that can outlive what it describes,
# and the pin is what makes it unnecessary.
#
# Order is merged through gitlore_order_merge over the three path lists, so a
# kept carrier-only line stays at its own offset instead of collecting at the end.
gitlore_compose_down() {
  local mempath="$1" tier="$2"
  local carrier="$mempath/$tier/MEMORY.md"
  local root="$mempath/MEMORY.md"
  local line path tmpd b o t

  tmpd=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-compose-down.XXXXXX") || return 1
  local side
  for side in root carrier head; do
    : > "$tmpd/$side.paths" || { rm -rf "$tmpd"; return 1; }
    : > "$tmpd/$side.bullets" || { rm -rf "$tmpd"; return 1; }
  done

  # root — its bullets for this tier, prefix stripped: the canonical text and the
  # authored order.
  if [ -f "$root" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in "$tier"/*) ;; *) continue ;; esac
      line=$(gitlore_bullet_deprefix "$line" "$tier") || continue
      printf '%s\n' "$line" >> "$tmpd/root.bullets"
      printf '%s\n' "${path#"$tier"/}" >> "$tmpd/root.paths"
    done < "$root"
  fi

  # carrier — the working tree's bullets, in carrier order.
  if [ -f "$carrier" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      printf '%s\n' "$line" >> "$tmpd/carrier.bullets"
      printf '%s\n' "$path" >> "$tmpd/carrier.paths"
    done < <(gitlore_index_part "$carrier" bullets)
  fi

  # root at HEAD — paths only, and only this tier's. `-q --verify` is silent on
  # the one expected miss: a store whose root index is not committed yet, which
  # leaves the list empty and makes every carrier line a keep.
  if git -C "$mempath" rev-parse -q --verify HEAD:MEMORY.md >/dev/null; then
    while IFS= read -r line || [ -n "$line" ]; do
      path=$(gitlore_bullet_path "$line") || continue
      case "$path" in "$tier"/*) ;; *) continue ;; esac
      printf '%s\n' "${path#"$tier"/}" >> "$tmpd/head.paths"
    done < <(git -C "$mempath" show HEAD:MEMORY.md)
  fi

  while IFS= read -r path; do
    [ -n "$path" ] || continue
    grep -qxF -- "$path" "$tmpd/head.paths"    && b=1 || b=0
    grep -qxF -- "$path" "$tmpd/root.paths"    && o=1 || o=0
    grep -qxF -- "$path" "$tmpd/carrier.paths" && t=1 || t=0
    if [ "$o" = 1 ]; then
      gitlore_compose_pick "$path" < "$tmpd/root.bullets"
    elif [ "$t" = 1 ] && [ "$b" = 0 ]; then
      gitlore_compose_pick "$path" < "$tmpd/carrier.bullets"
    fi
  done < <(gitlore_order_merge "$tmpd/head.paths" "$tmpd/root.paths" "$tmpd/carrier.paths")

  rm -rf "$tmpd"
  return 0
}

# Return 0 when index $1 carries at least one pointer line prefixed with tier $2.
gitlore_index_has_tier() {
  local file="$1" tier="$2" line path
  [ -f "$file" ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    path=$(gitlore_bullet_path "$line") || continue
    case "$path" in "$tier"/*) return 0 ;; esac
  done < "$file"
  return 1
}

# Print the root index's composed bullet block: each ACTIVE tier's lines, in
# manifest order, then the project's own bare-path lines in the order they
# already have.
#
# A tier's lines are taken from ROOT, which is what keeps the in-session pass
# placement-only — it moves lines, it never rewrites one. Two cases read the
# carrier instead:
#
#   - $2 names the tier. An explicit adoption (gitlore_compose_up), run once when
#     a merge lands a carrier the user has approved: there the carrier is the
#     reviewed artifact and its text wins over whatever root still holds.
#   - root carries no line at all for an active tier. That is what a freshly
#     mounted or freshly activated tier looks like, and root has no opinion about
#     it yet, so it takes the carrier's — the augmentation a mount owes the
#     index. Deleting every one of a tier's lines from root does NOT resurrect
#     the block: the down projection runs first and has already dropped those
#     lines from the carrier by the time this reads it.
#
# Lines prefixed with a mounted but DORMANT tier are dropped: root does not
# represent a dormant tier. They keep living in its carrier, and reactivating the
# tier brings them back through the case above.
gitlore_compose_root_bullets() {
  local mempath="$1" adopt="${2:-}"
  local root="$mempath/MEMORY.md" active tier line path
  active=$(gitlore_active_tiers "$mempath")

  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ -f "$mempath/$tier/MEMORY.md" ] || continue
    if [ "$tier" = "$adopt" ] || ! gitlore_index_has_tier "$root" "$tier"; then
      while IFS= read -r line || [ -n "$line" ]; do
        [ -n "$line" ] || continue
        gitlore_bullet_reprefix "$line" "$tier" || continue
      done < <(gitlore_index_part "$mempath/$tier/MEMORY.md" bullets)
    else
      while IFS= read -r line || [ -n "$line" ]; do
        path=$(gitlore_bullet_path "$line") || continue
        case "$path" in "$tier"/*) printf '%s\n' "$line" ;; esac
      done < <(gitlore_index_part "$root" bullets)
    fi
  done <<EOF
$active
EOF

  while IFS= read -r line || [ -n "$line" ]; do
    path=$(gitlore_bullet_path "$line") || continue
    case "$path" in */*) continue ;; esac
    printf '%s\n' "$line"
  done < <(gitlore_index_part "$root" bullets)
}

# Project tier $2's carrier UP into the root index and write it: root's block for
# that tier becomes the carrier's lines, prefixed, and every other line stays
# exactly where it is. This is the adoption step of a merge — the only moment a
# carrier is authoritative over root's text, because it is the artifact the user
# just approved.
#
# Writes no carrier, so a merge in one store never propagates into another the
# user did not review. Same three return codes as gitlore_compose.
gitlore_compose_up() {
  local mempath="$1" tier="$2"
  local root="$mempath/MEMORY.md"
  [ -f "$root" ] || return 0
  if ! gitlore_compose_check "$mempath"; then
    return 1
  fi
  local out
  if ! out=$(gitlore_compose_root_bullets "$mempath" "$tier" | gitlore_compose_write "$root"); then
    printf 'could not write %s\n' "$root"
    return 2
  fi
  [ -n "$out" ] && printf '%s\n' "$out"
  return 0
}

# Print one report line per ACTIVE tier carrier path that the composed root index
# does not carry; return 0 either way. Run AFTER a pass, like the dangling report
# and for the same reason: it describes the store as it now stands.
#
# A carrier line reaches the root unless root already had a block for that tier
# and never mentioned this path — a line written straight into the carrier, or
# one left there while the tier slept. Nothing is rewritten or dropped over it:
# it is a line whose two surfaces disagree about whether the fact is in play
# here, and which way to settle that is the agent's call, not the pass's.
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
      printf '%s: %s is in the tier but not in the root index\n' \
        "$mempath/$tier/MEMORY.md" "$path"
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
      ctx="The gitlore tier composition rewrote these indexes to place each active tier's pointer block ahead of the project's own lines, and projected root-authored tier lines down into their carrier — including deletions, so removing a tier fact's line from the root index is enough; its carrier copy goes in this same pass, not left for you to also edit by hand. This is expected and complete — do not re-read or re-edit them to verify. Composition moves or drops lines; it never changes a line's text.
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
