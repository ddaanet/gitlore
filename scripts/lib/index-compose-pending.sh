#!/usr/bin/env bash
# The compose pass parametrized by what it does with a computed index, and the
# read-only form of it. The write (gitlore_compose_write, in index-compose.sh)
# and the check (gitlore_compose_would_write) both take the content from
# gitlore_compose_render and both walk the indexes through gitlore_compose_pass;
# only the last step, writing the file or reporting that it would change, differs.
# Function-only and safe to source twice.

# Print index $1 as it reads once the bullets on stdin replace its bullet region,
# preamble and trailer kept.
gitlore_compose_render() {
  local file="$1" bullets pre
  bullets=$(cat)
  # The `x` keeps the command substitution from stripping the preamble's trailing
  # newlines, which are content.
  pre=$(gitlore_index_part "$file" preamble && printf x) || return 1
  pre=${pre%x}
  printf '%s' "$pre"
  # A bulletless index is ALL preamble, emitted verbatim — so one that arrived
  # unterminated would take the first bullet onto the end of its last line, and a
  # glued line is not a bullet: the pointer would be lost on write. Only ever a
  # separator, never normalisation — with no bullets there is nothing to separate
  # and the file is left exactly as it came.
  if [ -n "$bullets" ] && [ -n "$pre" ] && [ "${pre%$'\n'}" = "$pre" ]; then
    printf '\n'
  fi
  {
    [ -n "$bullets" ] && printf '%s\n' "$bullets"
    gitlore_index_part "$file" trailer
  }
}

# The read-only twin of gitlore_compose_write: same stdin, same report line
# ("composed <file>" when the index would change), and no file is written.
gitlore_compose_would_write() {
  local file="$1" new cur
  new=$(gitlore_compose_render "$file" && printf x) || return 1
  cur=$(cat -- "$file" && printf x) || return 1
  [ "$new" = "$cur" ] && return 0
  printf 'composed %s\n' "$file"
}

# The whole pass: validate, compose every active tier ahead of its pin UP into
# root three-way, project root's lines DOWN into every active tier's carrier,
# then lay out the root index. $2 names the function that receives each
# computed index on stdin and its path as $1: gitlore_compose_write for the pass
# itself, gitlore_compose_would_write for the check. Return codes are those of
# gitlore_compose.
gitlore_compose_pass() {
  local mempath="$1" writer="$2"
  local root="$mempath/MEMORY.md"
  local active tier changed="" out ahead dir mrc=0
  [ -f "$root" ] || return 0

  # Both checks run before either verdict is read, so one refusal carries the
  # whole list. Rule 7 is here rather than in gitlore_compose_check because the
  # end of a take composes a tier whatever its pin (see gitlore_compose_check_pins).
  local refused=0
  gitlore_compose_check "$mempath" || refused=1
  gitlore_compose_check_pins "$mempath" || refused=1
  [ "$refused" -eq 0 ] || return 1

  # Up first, so the down projection reads root with what a tier another
  # checkout or a killed take moved already merged in. The check stops at the
  # first change, since root is what it would write. The pass stages the
  # gitlink of every tier it merged, chunk or not: the staged gitlink is the base
  # the next pass reads, so a root edit to an adopted line stands instead of
  # being merged against the old pin again (D78). The check stages nothing. A
  # chunk ends the pass with root written and the tiers staged: projecting a
  # block holding three versions of one line down would push whichever the
  # projection picked into the carrier.
  ahead=$(gitlore_tiers_off_pin "$mempath" :)
  if [ -n "$ahead" ]; then
    if ! dir=$(mktemp -d "${TMPDIR:-/tmp}/gitlore-compose-up.XXXXXX"); then
      printf 'could not make a scratch directory to compose %s\n' "$root"
      return 2
    fi
    out=$(gitlore_compose_merge_tiers "$mempath" "$ahead" "$dir" :) || mrc=$?
    if [ "$mrc" -ge 2 ]; then
      rm -rf "$dir"
      printf '%s\n' "$out"
      return 1
    fi
    if ! out=$(gitlore_compose_root_bullets "$mempath" "$dir" | "$writer" "$root"); then
      rm -rf "$dir"
      printf 'could not write %s\n' "$root"
      return 2
    fi
    if [ -n "$out" ] && [ "$writer" != gitlore_compose_write ]; then
      rm -rf "$dir"
      printf '%s\n' "$out"
      return 0
    fi
    if [ "$writer" = gitlore_compose_write ] && ! gitlore_stage_merged_tiers "$mempath" "$dir"; then
      rm -rf "$dir"
      return 2
    fi
    if [ "$mrc" -eq 1 ]; then
      printf '%s\n' "$out"
      rm -rf "$dir"
      gitlore_index_marker_lines "$root"
      return 3
    fi
    rm -rf "$dir"
    [ -z "$out" ] || changed="$out
"
  fi

  active=$(gitlore_active_tiers "$mempath")

  # Down first, then the root layout. The layout pass adopts a carrier for any
  # active tier root has no line for, and the down pass skips that tier, so
  # deleting a tier's last root line brings its whole block back: deactivating
  # the tier is what drops it from a repo (D36).
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
      | "$writer" "$mempath/$tier/MEMORY.md"); then
      [ -n "$changed" ] && printf '%s' "$changed"
      printf 'could not write %s\n' "$mempath/$tier/MEMORY.md"
      return 2
    fi
    changed="$changed$out
"
  done <<EOF2
$active
EOF2

  if ! out=$(gitlore_compose_root_bullets "$mempath" | "$writer" "$root"); then
    [ -n "$changed" ] && printf '%s' "$changed"
    printf 'could not write %s\n' "$root"
    return 2
  fi
  # Root written by the up step above is named once.
  if [ -n "$out" ] && ! grep -qxF -- "$out" <<<"$changed"; then
    changed="$changed$out"
  fi

  [ -n "$changed" ] && printf '%s\n' "$changed"
  return 0
}

# Print the path of each index a compose pass would change, one per line. It
# writes no index and no file in a store, and moves no tier. Return 0 with no
# output when the store is composed; 1 when the pass would refuse (the problems
# on stdout, as gitlore_compose prints them); 2 when an index could not be read.
gitlore_compose_pending() {
  local out rc=0
  out=$(gitlore_compose_pass "$1" gitlore_compose_would_write) || rc=$?
  if [ "$rc" -ne 0 ]; then
    printf '%s\n' "$out"
    return "$rc"
  fi
  [ -z "$out" ] || printf '%s\n' "$out" | sed 's/^composed //'
  return 0
}

# Print the abort for the pending indexes in $1 (newline-separated paths). The
# agent arm names the bin entry; a terminal has no bin/ on PATH, so its arm names
# the script by path.
gitlore_say_compose_pending() {
  local pending="$1" bin
  bin=$(CDPATH="" cd -P -- "${BASH_SOURCE[0]%/*}/../.." && pwd)/bin/gitlore-compose
  gitlore_say_for_agent_or_user \
    "gitlore: the commit was aborted because a compose pass would change these indexes:
$pending
Run gitlore-compose, then retry the commit." \
    "gitlore: the commit was aborted because a compose pass would change these indexes:
$pending
Run \"$bin\" in this repository, then retry the commit."
}
