#!/usr/bin/env bash
# Compose-check: the four gitlore_compose_check rules (duplicate paths,
# unmounted manifest entries, unattributable prefixes, interleaved lines),
# welded-line detection, and rule 7 (a tier off its pin).
# Part of lib/index-compose.sh; source that, not this file.

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
    # store gets misread as refused (index-sync-relay.sh:77-81 fixed the same shape).
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

# Print the substring of $1 starting at a SECOND pointer bullet welded onto
# it; return 1 when there is none. Keyed on the first link's closing paren
# rather than on the `) — ` separator, so glue that lands ahead of the first
# hook — leaving no separator between the two links at all — is still caught.
#
# No backtick-awareness, by policy rather than by parsing: a hook has no
# legitimate use for a bare markdown hyperlink, since the entry already links
# its own file. Residual, accepted: a hook quoting an index-format example is
# reported spuriously, which is visible and repairable. awk has no
# backreferences and POSIX leaves them undefined in EREs, so a balanced-span
# pattern would force this check out of the idiom the rest of the index parsing
# uses — to buy a guarantee the policy already gives.
#
# Shared by gitlore_welded_path (which reduces the result to a path) and
# gitlore_repair_index (which splits the line on it) — one scan, so a repair
# splits exactly the shape the check flags.
gitlore_weld_tail() {
  local line="$1" tail
  gitlore_bullet_path "$line" >/dev/null || return 1
  tail=${line#*](}
  tail=${tail#*)}                  # everything past the first link
  case "$tail" in
    *"- ["*) ;;
    *) return 1 ;;
  esac
  printf '%s\n' "- [${tail#*"- ["}"
}

# Print the path of a SECOND pointer bullet welded onto line $1; return 1 when
# there is none.
gitlore_welded_path() {
  local line="$1" second
  # Screened in this shell first: a subshell per line is paid by every
  # bullet of every index the check reads, and only a weld needs the capture.
  gitlore_weld_tail "$line" >/dev/null || return 1
  second=$(gitlore_weld_tail "$line")
  gitlore_bullet_path "$second"
}

# Rules 1, 4 and 6 for a single index file. Prints problems; always returns 0
# (the caller aggregates). A rule added here gains a matching repair rule in
# gitlore_repair_index in the same change — a problem this reports and
# gitlore_repair_index cannot fix is a defect no take can adopt past.
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

# Print the lines of gitlore_compose_check output (stdin) that name index file
# $1 — every line with the exact "$1: " prefix, no pattern interpretation of
# $1. Return 0 when at least one matched, 1 otherwise.
gitlore_compose_problems_in() {
  local file="$1" line found=1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      "$file: "*) ;;
      *) continue ;;
    esac
    printf '%s\n' "$line"
    found=0
  done
  return "$found"
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
# It lives OUTSIDE gitlore_compose_check, called by gitlore_compose and by the
# commit path's pin guard ahead of it, because the rule belongs to the down pass
# alone. gitlore_compose_up adopts a
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
  local mempath="$1" active tier tierpath pinned head abs live checkout_err problems=""
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
    # A tier whose HEAD is a fast-forward descendant of the pin takes a
    # different remedy from one moved sideways or diverged: HEAD already
    # contains the pin, so the return-to-the-pin checkout the sideways branch
    # names would discard real commits rather than recover lost ones.
    # The `rev-parse -q --verify` guard removes the one expected failure of
    # `merge-base --is-ancestor` here — a pin that is no object in this
    # database at all, which the truncation comment below records as a normal
    # state — rather than letting its rc-128 `fatal:` reach the terminal. It
    # costs no coverage: a pin genuinely ancestral to HEAD is necessarily an
    # object here already, so what the guard rejects was never ahead.
    #
    # Staging the gitlink is not a remedy on its own: it satisfies this rule and
    # the next pass then projects root's older text over the carrier — the
    # overwrite being refused. Adoption is the tooling's, never a hand edit of
    # root's block: /gitlore:merge composes the carrier up into the root index
    # and stages the pair together (gitlore_adopt_advanced_live). A tier
    # gitlore's own commit path left ahead never reaches here: the commit path
    # stages it first (gitlore_stage_landed_tiers).
    if git -C "$tierpath" rev-parse -q --verify "${pinned}^{commit}" >/dev/null \
       && git -C "$tierpath" merge-base --is-ancestor "$pinned" "$head"; then
      # Absolute, so the printed command runs from anywhere; quoted, so a tier
      # path containing whitespace survives being pasted into a shell.
      abs=$(CDPATH='' cd -- "$tierpath" && pwd) || abs="$tierpath"
      # The take reads the tier's local `live`, so a tier whose `live` already
      # holds what HEAD holds reaches it: the checkout back to the pin loses
      # nothing and leaves precisely the state gitlore_adopt_advanced_live
      # adopts from — a clean tier on its pin with `live` ahead of it. A dirty
      # tier is left where it is: the checkout would carry work no summary
      # covers onto the pin, and the take refuses a dirty store anyway. So does
      # a `live` short of HEAD, which would strand the commits HEAD alone holds.
      if [ "$(gitlore_memory_dirty "$tierpath")" = "0" ] \
         && live=$(git -C "$tierpath" rev-parse -q --verify live) \
         && git -C "$tierpath" merge-base --is-ancestor "$head" "$live"; then
        # One problem per line, so git's own message is folded onto this one.
        if checkout_err=$(gitlore_git -C "$tierpath" checkout -q --detach "$pinned" 2>&1); then
          problems="${problems}tier '$tier' was checked out at ${head:0:12}, ahead of the pin the memory store records at ${pinned:0:12}, and its local 'live' holds those commits: it is back on the pin, so none of them is lost. Run /gitlore:merge to adopt them into the root index, then retry.
"
          continue
        fi
        problems="${problems}tier '$tier' is checked out at ${head:0:12}, ahead of the pin the memory store records at ${pinned:0:12}, and could not be returned to the pin for /gitlore:merge to adopt what its local 'live' holds. git said: $(printf '%s' "$checkout_err" | tr '\n' ' '). Return it with \`git -C \"$abs\" checkout --detach $pinned\` — 'live' holds the commits, so nothing is lost — then run /gitlore:merge.
"
        continue
      fi
      problems="${problems}tier '$tier' is checked out at ${head:0:12}, ahead of the pin the memory store records at ${pinned:0:12}: it advanced without composing, and projecting the root index onto it would overwrite what it holds. Adoption is /gitlore:merge's, which takes a tier's commits from its local 'live' and only from a clean tier: put HEAD's commits there with \`git -C \"$abs\" push . HEAD:refs/heads/live\`, leave nothing uncommitted in $abs, then run this again — the tier goes back on its pin and /gitlore:merge adopts what 'live' holds. A push refused as a non-fast-forward means 'live' moved too: run /gitlore:resolve.
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
