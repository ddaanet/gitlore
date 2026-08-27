#!/usr/bin/env bash
# Containment for a Claude Code `Edit` defect (D23): deleting a match that
# begins with a newline consumes the separator on BOTH sides, welding the
# surrounding lines into one. Sourced by the Pre/Post hooks and unit-tested
# directly. Only `gitlore_weld_repair` writes anything.

# Directory holding the pre-edit expectations. Outside any repository: the
# guard arms on every `Edit`, not only ones landing in a gitlore store.
gitlore_weld_state_dir() {
  printf '%s/gitlore-edit-weld\n' "${TMPDIR:-/tmp}"
}

# Expectation file for one (session, target) pair. `PreToolUse` stdin carries no
# `tool_use_id`, so the target path is what distinguishes concurrent edits
# within a session. A cksum collision costs nothing: the post hook compares the
# file byte-for-byte against the recorded weld, and a mismatched record simply
# never matches.
# Args: $1 = session id; $2 = target path.
gitlore_weld_state_file() {
  printf '%s/%s\n' "$(gitlore_weld_state_dir)" \
    "$(printf '%s\0%s' "$1" "$2" | cksum | tr -cd '0-9')"
}

# Print `{orig, exp, weld}` for a weldable call — the file as it stands, the
# result the edit asked for, and the result the defect produces. Return 1 and
# print nothing when the call cannot weld, which is the common case.
#
# Weldable is narrower than risky. The defect needs BOTH a match that begins
# with a newline and a newline immediately after it: the deletion empties a
# line, Edit removes the emptied line along with its trailing separator, and the
# leading one is already inside the match. A match running to the end of a line
# nothing follows has no second separator to lose and comes out correct — so
# arming there would offer a repair where nothing broke, and would dilute the
# retirement signal with observations that test nothing.
#
# Computing the intended result is a slice, not a reimplementation of `Edit`.
# The line-oriented deletion special case — emptying a line removes it rather
# than leaving it blank — only arises when `old_string` carries no separator of
# its own, and that shape never reaches here.
#
# Args: $1 = target path; $2 = the edit's old_string.
gitlore_weld_plan() {
  local out
  # --rawfile so the whole file arrives as one string with its final byte
  # intact. The offset comes from the prefix `split` leaves rather than from
  # `index`, which reports a BYTE offset while slicing and `length` count
  # codepoints — under any multi-byte text the two disagree and the slice cuts
  # mid-character. Invalid UTF-8 fails the decode and the call disarms, which is
  # the safe direction.
  out=$(jq -cn --rawfile s "$1" --arg old "$2" '
    if ($old | startswith("\n")) | not then empty
    else ($s | split($old)) as $parts
    | if ($parts | length) < 2 then empty
      else ($parts[0] | length) as $i
      | ($i + ($old | length)) as $e
      | if $s[$e:$e+1] != "\n" then empty
        else {orig: $s, exp: ($s[:$i] + $s[$e:]), weld: ($s[:$i] + $s[$e+1:])}
        end
      end
    end') || return 1
  [ -n "$out" ] || return 1
  printf '%s\n' "$out"
}

# Print the verdict for a completed edit: `repair`, `clean`, `unchanged` or
# `unknown`. The four are exhaustive over what the target can hold, and each is
# decided by a whole-file byte comparison — so a wrong plan can only ever fall
# through to `unknown`, never provoke a write.
# Args: $1 = expectation file; $2 = target path.
gitlore_weld_verdict() {
  local state="$1" file="$2"
  if   cmp -s "$file" <(jq -j '.weld' "$state"); then printf 'repair\n'
  elif cmp -s "$file" <(jq -j '.exp'  "$state"); then printf 'clean\n'
  elif cmp -s "$file" <(jq -j '.orig' "$state"); then printf 'unchanged\n'
  else printf 'unknown\n'
  fi
}

# Write the intended result over the target, undoing the weld at the edit site —
# before composition, the sync, or any pattern check sees it.
# Args: $1 = expectation file; $2 = target path.
gitlore_weld_repair() {
  local state="$1" file="$2" scratch status
  # The scratch file lives in the state directory, never beside the target: a
  # target inside the memory worktree would otherwise gain an untracked
  # neighbour, which the FR11 gate's `git add -A` sweeps into the next commit.
  scratch="$(gitlore_weld_state_dir)/repair.$$"
  mkdir -p "$(gitlore_weld_state_dir)" || return 1
  # Truncate-and-write rather than a rename, so the target keeps its inode and
  # its mode. jq's own failure is caught before the target is touched.
  if jq -j '.exp' "$state" > "$scratch" && cat "$scratch" > "$file"; then
    rm -f "$scratch"
    return 0
  else
    # $? after a bare `if cond; then ...; fi` with no branch taken is 0, not
    # the condition's status (POSIX) — capture it here, in the else branch,
    # while it is still live.
    status=$?
    rm -f "$scratch"
    return "$status"
  fi
}
