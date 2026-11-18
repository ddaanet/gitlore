#!/usr/bin/env bash
# Compose-check: the four gitlore_compose_check rules (duplicate paths,
# unmounted manifest entries, unattributable prefixes, interleaved lines),
# welded-line detection, conflict markers, and rule 7 (a tier off its
# pin).
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
# Rules 6 (the welded line) and 8 (a conflict marker) are checked per index
# below; rule 7 (a mounted tier off its pin) lives in
# gitlore_compose_check_pins, which this function does not call.
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

# Rules 1, 4, 6 and 8 for a single index file. Prints problems; always returns 0
# (the caller aggregates). A rule added here gains a matching repair rule in
# gitlore_repair_index in the same change — a problem this reports and
# gitlore_repair_index cannot fix is a defect no take can adopt past. Rule 8,
# conflict markers, is the exception: which side of a chunk is right is a
# judgement about the fact, so a person settles it and no rewrite does.
gitlore_compose_check_index() {
  local file="$1" first last n=0 line path welded seen=""
  gitlore_index_marker_lines "$file"
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

# Rule 8 — print one problem per conflict-marker line in index $1, the whole file
# read, so a chunk in the preamble or the trailer is named too. A compose-up
# writes a diff3 chunk where root and a tier both changed one entry apart, and
# every pass and commit stops here until it is settled. `=======` alone is left
# out: a markdown heading underline is the same text, and the other three
# markers already name every chunk.
gitlore_index_marker_lines() {
  local file="$1" n=0 line
  [ -f "$file" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    n=$((n + 1))
    case "$line" in
      '<<<<<<<' | '<<<<<<< '* | '|||||||' | '||||||| '* | '>>>>>>>' | '>>>>>>> '*)
        printf '%s: line %d holds a conflict marker\n' "$file" "$n" ;;
    esac
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

# Rule 7 — every MOUNTED tier, dormant ones included, sits ON the commit the
# memory store records for it, except where the rule yields (below). Print one
# problem per tier that does not and return 1; print nothing and return 0
# otherwise. Depends on gitlore_tier_paths (util-config.sh),
# gitlore_store_mid_merge, gitlore_root_merge_refused and
# gitlore_tier_take_refused (util-merge-state.sh); callers source util.sh, which
# pulls in all four.
#
# A tier ahead of its pin holds lines the root index has not taken: the
# commit's `add -A` would record it with those lines never composed into the
# root index, so it is refused naming the take, which composes them up
# three-way and records the gitlink. The refusal states no cause, since what
# moved the tier is not what the reader acts on. A tier behind its pin is
# refused, dormant or not, since that `add -A` would record the older commit
# and move the pin backward with no one having asked. So is a tier beside its
# pin, whose HEAD and pin each hold commits the other lacks: naming the take
# when the tier has forked from its own `live`, which holds the pin, and the
# return-to-the-pin checkout otherwise.
#
# The rule yields a tier exactly where its remedy, the take, would refuse for
# uncommitted changes, in the memory root or in a mounted tier
# (gitlore_pin_yield_tiers, gitlore_take_refused): refusing there sends the
# commit to a take that sends it back. The pass then projects nothing down into that tier,
# and the commit leaves its gitlink where root records it.
#
# It lives OUTSIDE gitlore_compose_check, called by the pass and by the commit
# path's pin guard ahead of it, because the end of a take, the memory merge's
# continuation and the recovery compose a tier whatever its relation to the pin.
gitlore_compose_check_pins() {
  local mempath="$1" tier tierpath relation pinned head abs problems="" refused=""
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    relation=$(gitlore_tier_pin_relation "$mempath" "$tier")
    case "$relation" in ""|on) continue ;; esac
    # The yield set of gitlore_pin_yield_tiers, classified in this loop: a
    # `merge *` tier yields where the take is refused, which is read once, on
    # the first such tier.
    case "$relation" in
      "merge "*)
        if [ -z "$refused" ]; then
          if gitlore_take_refused "$mempath"; then refused=1; else refused=0; fi
        fi
        [ "$refused" -eq 1 ] && continue ;;
    esac
    pinned=$(git -C "$mempath" rev-parse ":$tier")
    head=$(git -C "$tierpath" rev-parse HEAD)
    case "$relation" in
      "resolve mid-merge")
        problems="${problems}tier '$tier' is mid-merge and sits off the commit the memory store records for it; run /gitlore:resolve to land the merge before the indexes can be composed
" ;;
      "merge unheld")
        problems="${problems}tier '$tier' is checked out at ${head:0:12} and the memory store records ${pinned:0:12}, a commit this checkout of the tier does not hold. Run /gitlore:merge, which fetches the tier and fast-forwards it.
" ;;
      "merge ahead")
        problems="${problems}tier '$tier' is checked out at ${head:0:12}, ahead of the commit the memory store records at ${pinned:0:12}, so the root index has not taken its lines. Run /gitlore:merge, which composes them into the root index and records the tier.
" ;;
      "merge behind")
        problems="${problems}tier '$tier' is checked out at ${head:0:12}, behind the commit the memory store records at ${pinned:0:12}, and a commit would record the older one. Run /gitlore:merge, which fast-forwards it.
" ;;
      "merge forked")
        problems="${problems}tier '$tier' is checked out at ${head:0:12}, beside the commit the memory store records at ${pinned:0:12}, with commits no branch holds. Run /gitlore:merge, which merges its local live into them and records the tier.
" ;;
      *)
        # Absolute, so the printed command runs from anywhere; quoted, so a tier
        # path containing whitespace survives being pasted into a shell.
        abs=$(CDPATH='' cd -- "$tierpath" && pwd) || abs="$tierpath"
        problems="${problems}tier '$tier' is checked out at ${head:0:12} but the memory store records ${pinned:0:12}: it was moved outside /gitlore:merge, and projecting the root index onto it would overwrite what it holds. Return it to the pin with \`git -C \"$abs\" checkout --detach $pinned\`, then run /gitlore:merge to take upstream properly.
" ;;
    esac
  done < <(gitlore_tier_paths "$mempath")

  [ -z "$problems" ] && return 0
  printf '%s' "$problems" | grep -v '^$'
  return 1
}

# The tiers rule 7 yields, one per line: where /gitlore:merge refuses the take
# for uncommitted changes, every tier whose own remedy is /gitlore:merge. The
# take refuses for the memory root (gitlore_root_merge_refused) or for any one
# mounted tier (gitlore_tier_take_refused, gitlore_refuse_dirty_tiers), and one
# refusal stops the whole take, so a clean tier off its pin is yielded when
# another tier is the refused one. A tier whose remedy is /gitlore:resolve or a
# checkout keeps its refusal, since that remedy does not run through the take.
# Read live, so the yield ends once the refused work is committed and the take
# can run.
# Args: $1 = memory worktree path.
gitlore_pin_yield_tiers() {
  local mempath="$1" tier candidates=""
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    case "$(gitlore_tier_pin_relation "$mempath" "$tier")" in
      "merge "*) candidates="$candidates$tier
" ;;
    esac
  done < <(gitlore_tier_paths "$mempath")
  [ -n "$candidates" ] || return 0
  gitlore_take_refused "$mempath" || return 0
  printf '%s' "$candidates"
}

# Exit 0 when /gitlore:merge refuses the take of memory root $1 for uncommitted
# changes before it moves any store: root's own (gitlore_root_merge_refused) or
# any mounted tier's (gitlore_tier_take_refused).
# Args: $1 = memory worktree path.
gitlore_take_refused() {
  local mempath="$1" tier
  gitlore_root_merge_refused "$mempath" && return 0
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    gitlore_tier_take_refused "$mempath" "$tier" && return 0
  done < <(gitlore_tier_paths "$mempath")
  return 1
}

# Print how mounted tier $2 sits against the commit memory store $1 records for
# it, as "<remedy> <relation>": `on`; `resolve mid-merge`; `merge unheld`, a pin
# this checkout has not fetched, the shape a raw pull in memory leaves; `merge
# ahead`; `merge behind`; `merge forked`, beside the pin with the tier's own
# `live` holding the pin and no branch or remote-tracking ref holding HEAD;
# `checkout beside`, every other tier whose HEAD and pin each hold commits the
# other lacks. Print nothing for a tier the rule has no opinion about.
#
# A forked tier is what a commit on a tier checked out behind its pin leaves,
# the memory commit's own included when the pin guard yields it: the take
# merges the tier's `live` into HEAD and records the merge, while a checkout of
# the pin would leave HEAD's commits reachable from the reflog alone. Where
# another ref holds HEAD, the checkout strands nothing; where `live` lacks the
# pin, the take has nothing to merge it from.
#
# The pin is read from the memory store's INDEX (`:$tier`), not from
# `HEAD:$tier`: a gitlink staged for the next memory commit is what that commit
# records.
# Args: $1 = memory worktree path, $2 = tier path.
gitlore_tier_pin_relation() {
  local mempath="$1" tierpath="$1/$2" pinned head
  # `git -C` into an unmaterialized submodule walks up to the enclosing repo,
  # which would answer for memory's own HEAD under the tier's name.
  [ -e "$tierpath/.git" ] || return 0
  # `-q --verify` is silent on the expected miss: no gitlink for this tier in
  # the index at all — mid-mount, or removed. Same for a store with no HEAD yet.
  pinned=$(git -C "$mempath" rev-parse -q --verify ":$2") || return 0
  head=$(git -C "$tierpath" rev-parse -q --verify HEAD) || return 0
  if [ "$head" = "$pinned" ]; then
    printf 'on\n'
  elif gitlore_store_mid_merge "$tierpath"; then
    printf 'resolve mid-merge\n'
  elif ! git -C "$tierpath" rev-parse -q --verify "${pinned}^{commit}" >/dev/null; then
    printf 'merge unheld\n'
  elif git -C "$tierpath" merge-base --is-ancestor "$pinned" "$head"; then
    printf 'merge ahead\n'
  elif git -C "$tierpath" merge-base --is-ancestor "$head" "$pinned"; then
    printf 'merge behind\n'
  elif git -C "$tierpath" rev-parse -q --verify live >/dev/null &&
    git -C "$tierpath" merge-base --is-ancestor "$pinned" live &&
    [ -z "$(git -C "$tierpath" for-each-ref --contains "$head" refs/heads refs/remotes)" ]; then
    printf 'merge forked\n'
  else
    printf 'checkout beside\n'
  fi
}
