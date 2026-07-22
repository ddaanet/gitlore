#!/usr/bin/env bash
# Active recall: fetch memory bodies deterministically. Source; do not exec.
#
# CC's native recall runs a per-query classifier against the USER PROMPT and is
# told not to re-select within a conversation. So a fact whose trigger only
# appears mid-task — an error string in a tool result, a flag in a file just
# read — can never reach context on its own. Active recall closes that gap:
# the agent writes a short request file, and this library reads the named
# bodies so the HOOK injects them. The agent never issues the Read, which is
# what makes the fetch deterministic rather than a matter of agent judgement.
#
# Cap is 5, matching CC's own classifier ("return at most 5 filenames you are
# certain are relevant"). Over the cap is a HARD failure, never a truncation:
# a list of 9 means the selection was not made, and silently keeping the first
# 5 would hide that. The agent reassesses and retries with a specific list.

# Max entries per request. Same number as CC's native recall classifier.
GITLORE_RECALL_MAX=5
readonly GITLORE_RECALL_MAX

# Print abs path to the recall request file. The agent writes it as an ordinary
# in-project file — no Bash call, no gitdir write — so it clears the sandbox and
# the auto-mode classifier, exactly as the commit trigger does. Gitignored.
# Args: $1 = memory worktree path.
gitlore_recall_file() {
  printf '%s/gitlore-recall\n' "$(_gitlore_ipc_dir "$1")"
}

# Print the path to this session's recall ledger: which memory bodies are
# already in context. Lives in the memory gitdir (like gitlore_commit_notified_file)
# so it never shows up in `git status` and needs no .gitignore entry. Keyed by
# session so concurrent sessions don't read each other's context as their own.
# Args: $1 = memory worktree path; $2 = session id.
gitlore_recall_ledger() {
  local safe
  # Session ids are uuids, but a ledger path is not the place to trust that.
  safe=$(printf '%s' "${2:-nosession}" | LC_ALL=C sed 's/[^A-Za-z0-9-]/_/g')
  git -C "$1" rev-parse --git-path "gitlore-recall-$safe"
}

# Record that a memory file's CURRENT content is in context. Records path AND
# content hash: a memory edited since it was read is no longer known, so the
# stale record must not suppress a re-fetch.
# Args: $1 = memory worktree path; $2 = session id; $3 = path relative to mempath.
gitlore_recall_record() {
  local mempath="$1" rel="$3" ledger hash
  [ -f "$mempath/$rel" ] || return 0
  ledger=$(gitlore_recall_ledger "$mempath" "$2")
  # `-C` already puts us in the store, so the operand is relative to it.
  hash=$(git -C "$mempath" hash-object -- "$rel") || return 0
  # Records are "<hash> <relpath>": hash first so a path containing spaces
  # survives the split. Paths containing a newline are out of scope — the same
  # line-oriented bound the activation manifest carries.
  printf '%s %s\n' "$hash" "$rel" >> "$ledger"
}

# Exit 0 if this session already holds the file's current content.
# Args: $1 = memory worktree path; $2 = session id; $3 = path relative to mempath.
gitlore_recall_known() {
  local mempath="$1" rel="$3" ledger hash line
  ledger=$(gitlore_recall_ledger "$mempath" "$2")
  [ -f "$ledger" ] || return 1
  [ -f "$mempath/$rel" ] || return 1
  hash=$(git -C "$mempath" hash-object -- "$rel") || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    [ "$line" = "$hash $rel" ] && return 0
  done < "$ledger"
  return 1
}

# Clear this session's ledger, and sweep ledgers left by sessions that ended
# without one. Called at SessionStart (a resumed session keeps its id but starts
# with a fresh context) and at PreCompact.
#
# PreCompact is the load-bearing one. What survives a compaction is a SUMMARY,
# not the tool results — and the docs guarantee re-injection only for the
# project-root CLAUDE.md, nothing for memory bodies. Which reads the summarizer
# preserved is unknowable, so the ledger is cleared wholesale: re-injecting a
# body that is still present costs tokens, whereas assuming presence that is
# gone silently withholds a fact the agent believes it has. The cheap error is
# the correct one.
# Args: $1 = memory worktree path; $2 = session id.
gitlore_recall_reset() {
  local mempath="$1" ledger dir
  ledger=$(gitlore_recall_ledger "$mempath" "$2")
  rm -f "$ledger"
  dir=$(dirname -- "$ledger")
  # Sweep week-old ledgers from sessions that are long gone.
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name 'gitlore-recall-*' -type f -mtime +7 -delete
  return 0
}

# Normalize one request line to a path relative to $mempath, or print a problem
# and return 1. Accepts both "feedback_x.md" and "memory/feedback_x.md" — the
# index the agent reads carries bare paths, but the prose around it says
# "memory/", and rejecting one of the two spellings buys nothing.
# Args: $1 = memory worktree path; $2 = raw line.
_gitlore_recall_normalize() {
  local mempath="$1" rel="$2"
  case "$rel" in
    /*) printf 'absolute path not allowed: %s\n' "$rel"; return 1 ;;
  esac
  case "/$rel/" in
    */../*) printf 'path escapes the memory store: %s\n' "$rel"; return 1 ;;
  esac
  # Tolerate the "memory/…" spelling.
  case "$rel" in
    "$mempath"/*) rel="${rel#"$mempath"/}" ;;
  esac
  if [ ! -f "$mempath/$rel" ]; then
    printf 'no such memory file: %s\n' "$rel"
    return 1
  fi
  printf '%s\n' "$rel"
}

# Read the recall request and print the text to inject. Returns 0 with the
# injection payload on stdout, or 1 with the problem report on stdout.
#
# A problem report is a standalone sentence, capitalized, and never says that
# nothing was read: the caller's refusal banner owns that clause, and stating it
# in both places is what produced the doubled live text.
#
# The request file is consumed by the CALLER either way: it is a one-shot
# request, and keeping a rejected one would re-report the same error on every
# subsequent batch. Rejection is safe to make terminal because there is no gate
# blocking the agent — it simply re-invokes the skill with a corrected list.
# Args: $1 = memory worktree path; $2 = session id.
gitlore_recall_resolve() {
  local mempath="$1" session="$2" req line trimmed lower
  local -a wanted=() problems=()
  local n=0 nomatch=0

  req=$(gitlore_recall_file "$mempath")
  [ -f "$req" ] || { printf 'There is no recall request file to serve.\n'; return 1; }

  while IFS= read -r line || [ -n "$line" ]; do
    trimmed="${line#"${line%%[![:space:]]*}"}"
    trimmed="${trimmed%"${trimmed##*[![:space:]]}"}"
    [ -n "$trimmed" ] || continue
    lower=$(printf '%s' "$trimmed" | tr '[:upper:]' '[:lower:]')
    case "$lower" in
      'no match'|'no-match'|none) nomatch=1; continue ;;
    esac
    n=$((n + 1))
    wanted[${#wanted[@]}]="$trimmed"
  done < "$req"

  if [ "$nomatch" -eq 1 ] && [ "$n" -gt 0 ]; then
    printf 'The request mixes "no match" with %d path(s); it must be one or the other.\n' "$n"
    return 1
  fi
  if [ "$nomatch" -eq 1 ]; then
    printf 'no match\n'
    return 0
  fi
  if [ "$n" -eq 0 ]; then
    printf 'The request is empty; write either "no match" or up to %d paths, one per line.\n' \
      "$GITLORE_RECALL_MAX"
    return 1
  fi
  if [ "$n" -gt "$GITLORE_RECALL_MAX" ]; then
    printf 'The request lists %d entries, over the limit of %d. Reassess and retry with a more specific list — pick only the entries whose trigger you have actually seen.\n' \
      "$n" "$GITLORE_RECALL_MAX"
    return 1
  fi

  local rel out
  local -a resolved=()
  for line in "${wanted[@]}"; do
    if out=$(_gitlore_recall_normalize "$mempath" "$line"); then
      resolved[${#resolved[@]}]="$out"
    else
      problems[${#problems[@]}]="$out"
    fi
  done
  if [ "${#problems[@]}" -gt 0 ]; then
    printf 'The request names entries that do not resolve.\n'
    printf '  - %s\n' "${problems[@]}"
    printf 'Check the paths against the index in %s/MEMORY.md and retry.\n' "$mempath"
    return 1
  fi

  local -a fetched=() skipped=()
  for rel in "${resolved[@]}"; do
    if gitlore_recall_known "$mempath" "$session" "$rel"; then
      skipped[${#skipped[@]}]="$rel"
    else
      fetched[${#fetched[@]}]="$rel"
    fi
  done

  if [ "${#fetched[@]}" -eq 0 ]; then
    printf 'gitlore recall: every requested memory is already in this context — nothing fetched. Do not Read them; use what you have.\n'
    printf '  already present: %s\n' "${skipped[@]}"
    return 0
  fi

  printf 'gitlore recall: the bodies below were read for you and are current as of now. Do NOT Read these files — their full contents are here.\n'
  if [ "${#skipped[@]}" -gt 0 ]; then
    printf 'Skipped, already in this context: %s\n' "${skipped[@]}"
  fi
  for rel in "${fetched[@]}"; do
    printf '\n===== %s/%s =====\n' "$mempath" "$rel"
    cat -- "$mempath/$rel"
    gitlore_recall_record "$mempath" "$session" "$rel"
  done
  return 0
}
