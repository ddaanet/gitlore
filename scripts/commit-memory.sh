#!/usr/bin/env bash
set -euo pipefail

# Standalone blessed entry point (D16): commit the memory store and its dirty tiers
# from a sectioned summary, then fast-forward each committed store's local `live`.
# The summary is the only input, on stdin, through a quoted heredoc:
#   gitlore-commit <<'EOF'
#   == <tier> ==
#   <tier commit message>
#   == memory ==
#   <root commit message>
#   EOF
# One `== <store> ==` section per store with changes, `memory` for root. Each
# section is committed verbatim in its own store, tiers before root. Refused
# (exit 2) when the summary is empty, has text before its first header, or does
# not match the stores that have changes; no commit precedes a refusal. A
# refused run may still have composed first: that writes the tier carriers and
# the root MEMORY.md, the same writes the index-compose hook makes.
# It never prepares or takes a merge: a `live` that cannot fast-forward is
# reported. Callers run it as `gitlore-commit`, the plugin `bin/` name.

# Defensive: a caller's env may carry leaked repo-local GIT_* vars (see
# `.claude/rules/shell.md` "Git hook env leak"). Clear the full local-env-var set, not a hand-picked
# subset — GIT_COMMON_DIR/GIT_OBJECT_DIRECTORY can redirect submodule git ops.
# shellcheck disable=SC2046  # intentional word-splitting of the var-name list
unset $(git rev-parse --local-env-vars)

# The libraries shipped beside this script, never the ones `gitlore.hooksDir` or
# CLAUDE_PLUGIN_ROOT name: both can pin an older cache, and a newer script run
# by path would then call functions its libraries lack.
PLUGIN_ROOT=$(CDPATH="" cd -- "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"

refuse() {
  printf 'usage: gitlore-commit: %s. Run /gitlore:commit to draft the summary and get it approved.\n' "$1" >&2
  exit 2
}

# Whether the root change at $1 belongs to a tier: a tier's gitlink, or a
# MEMORY.md whose changed lines are all link lines pointing under a tier prefix.
# Any other changed MEMORY.md line (a heading, prose, a blank, a link outside
# every tier prefix, a line mixing both) is root content.
root_change_is_tier() {
  local path="$1" tier line ptr ptrs under changed=0
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    [ "$path" = "$tier" ] && return 0
  done < <(gitlore_tier_paths "$mempath")
  [ "$path" = MEMORY.md ] || return 1
  while IFS= read -r line || [ -n "$line" ]; do
    changed=1
    # Captured, so a line with no link is told apart from a failed read.
    ptrs=$(printf '%s\n' "${line:1}" | grep -oE '\]\([^)]*\)' | sed -e 's/^](//' -e 's/)$//' || true)
    [ -n "$ptrs" ] || return 1
    while IFS= read -r ptr; do
      under=0
      while IFS= read -r tier; do
        [ -n "$tier" ] || continue
        case "$ptr" in "$tier"/*) under=1 ;; esac
      done < <(gitlore_tier_paths "$mempath")
      [ "$under" = 1 ] || return 1
    done <<<"$ptrs"
  done < <(git -C "$mempath" diff HEAD -U0 -- MEMORY.md | grep -E '^[-+]' | grep -vE '^(\+\+\+|---) ' || true)
  [ "$changed" = 1 ]
}

[ "$#" -eq 0 ] || refuse "takes no arguments; the summary is read on stdin"
[ -t 0 ] && refuse "stdin is a terminal, not a summary"
summary=$(cat)
case "$summary" in
  *[![:space:]]*) ;;
  *) refuse "the summary on stdin is empty" ;;
esac

# The launch repo, whatever directory the agent's shell is in. Outside any
# worktree memory_path then finds no .gitmodules and the run is a no-op.
outside_worktree=0
launch_rc=0
gitlore_cd_launch_repo || launch_rc=$?
case "$launch_rc" in
  0) ;;
  1)
    echo "gitlore: nothing was committed: the project directory '$CLAUDE_PROJECT_DIR' cannot be entered." >&2
    exit 0 ;;
  2) outside_worktree=1 ;;
  *) exit 1 ;;
esac

mempath=$(gitlore_memory_path) || mempath=""

# Activation: no memory submodule → nothing to do. Exit 0 stays, but the caller
# is told, so an agent does not report a commit that never happened.
if [ -z "$mempath" ]; then
  if [ "$outside_worktree" = 1 ]; then
    echo "gitlore: nothing was committed: the current directory is outside any git worktree." >&2
  else
    echo "gitlore: nothing was committed: this repository has no memory submodule." >&2
  fi
  exit 0
fi
# Session-less worktree: memory worktree not materialized → nothing to do.
if [ ! -e "$mempath/.git" ]; then
  echo "gitlore: nothing was committed: the memory worktree '$mempath' is not materialized in this checkout." >&2
  exit 0
fi

# A prepared merge is answered before anything is committed on top of it.
gitlore_guard_stale_merge_state "$mempath" || exit 1
# A tier holding a prepared merge is answered before the summary is judged: the
# merge's directive is the message, not a request for a summary.
while IFS= read -r tier; do
  [ -n "$tier" ] || continue
  [ -e "$mempath/$tier/.git" ] || continue
  gitlore_guard_stale_merge_state "$mempath/$tier" || exit 1
done < <(gitlore_tier_paths "$mempath")

# The commit writes no index. A store whose indexes a compose pass would change
# aborts here, before the stores are judged: the pass would make a tier dirty
# that the status below must see, and the section check would otherwise answer a
# summary for a state the remedy changes. A pass that would refuse is the sync's
# to report, and writes nothing either way.
pending_rc=0
pending=$(gitlore_compose_pending "$mempath") || pending_rc=$?
if [ "$pending_rc" -eq 0 ] && [ -n "$pending" ]; then
  gitlore_say_compose_pending "$pending" >&2
  exit 1
fi

# What has changes. Tier-only root changes (a gitlink moving, MEMORY.md lines
# under a tier prefix) need no section; any other root change does.
dirty_tiers=""
while IFS= read -r tier; do
  [ -n "$tier" ] || continue
  [ -e "$mempath/$tier/.git" ] || continue
  # A status that cannot be read is not evidence of a clean tier: it counts as
  # changed, so the sync's own reads report the failure rather than a refusal
  # saying the tier has nothing to commit.
  if ! tier_status=$(git -C "$mempath/$tier" status --porcelain 2>&1); then
    dirty_tiers="$dirty_tiers$tier"$'\n'
  elif [ -n "$tier_status" ]; then
    dirty_tiers="$dirty_tiers$tier"$'\n'
  fi
done < <(gitlore_tier_paths "$mempath")

root_has=0
root_content=0
if [ "$(gitlore_memory_dirty "$mempath")" = "1" ]; then
  root_has=1
  # NUL-delimited, so a tier path with a space arrives unquoted. A rename record
  # is followed by its source path as a field of its own.
  while IFS= read -r -d '' entry; do
    [ -n "$entry" ] || continue
    case "${entry:0:2}" in R?|?R|C?|?C) IFS= read -r -d '' _source || true ;; esac
    if ! root_change_is_tier "${entry:3}"; then root_content=1; fi
  done < <(git -C "$mempath" status --porcelain -z)
fi

# Nothing to commit: exit 0 whatever the summary says, and the caller is told,
# so an agent does not report a commit that never happened.
if [ "$root_has" = "0" ] && [ -z "$dirty_tiers" ]; then
  echo "gitlore: nothing was committed: memory and every mounted tier are clean." >&2
  exit 0
fi

# The section check. Every refusal here precedes the first commit (composition
# above has already written, as its hook does).
headers=$(gitlore_summary_headers "$summary")
if [ -n "$(gitlore_summary_preamble "$summary")" ]; then
  refuse "text before the first '== <store> ==' header belongs to no store"
fi
tiers=$(gitlore_tier_paths "$mempath")
seen=""
while IFS= read -r name; do
  [ -n "$name" ] || continue
  if grep -Fqx -- "$name" <<<"$seen"; then
    refuse "store '$name' has more than one section"
  fi
  seen="$seen$name"$'\n'
  if [ "$name" = memory ]; then
    [ "$root_has" = "1" ] || refuse "store 'memory' has no changes to commit"
  elif grep -Fqx -- "$name" <<<"$tiers"; then
    grep -Fqx -- "$name" <<<"$dirty_tiers" || refuse "store '$name' has no changes to commit"
  else
    refuse "store '$name' is not a mounted store"
  fi
  body=$(gitlore_summary_section "$summary" "$name")
  [ -n "${body//[[:space:]]/}" ] || refuse "the section for '$name' is empty"
done <<<"$headers"
while IFS= read -r tier; do
  [ -n "$tier" ] || continue
  grep -Fqx -- "$tier" <<<"$headers" || refuse "store '$tier' has changes and no section"
done <<<"$dirty_tiers"
if [ "$root_content" = "1" ]; then
  grep -Fqx -- memory <<<"$headers" || refuse "the root store has changes beyond its tiers and no 'memory' section"
fi

memory_before=$(git -C "$mempath" rev-parse HEAD)
gitlore_sync_memory_to_live "$mempath" "$summary" || exit 1
memory_after=$(git -C "$mempath" rev-parse HEAD)
if [ "$memory_before" != "$memory_after" ]; then
  gitlore_stage_memory_pointer "$mempath"
fi
exit 0
