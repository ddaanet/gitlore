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
# before any store is touched (exit 2) when the summary is empty, has text
# before its first header, or does not match the stores that have changes.
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
  printf 'usage: commit-memory.sh: %s. Run /gitlore:commit to draft the summary and get it approved.\n' "$1" >&2
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

# The launch repo, whatever directory the agent's shell is in: the memory path is
# read from `.gitmodules` relative to it. Agent Bash has no CLAUDE_PROJECT_DIR,
# so without it the repo is the outermost worktree holding the cwd — climbing
# out of memory/ or a tier when the shell sits inside one.
if [ -n "${CLAUDE_PROJECT_DIR:-}" ]; then
  gitlore_cd_project_root || exit 0
# Outside any worktree rev-parse fails, which is expected: memory_path then
# finds no .gitmodules and the run is a no-op.
elif top=$(git rev-parse --show-toplevel 2>/dev/null); then
  cd "$top" || exit 1
  while sup=$(git rev-parse --show-superproject-working-tree) && [ -n "$sup" ]; do
    cd "$sup" || exit 1
  done
fi

mempath=$(gitlore_memory_path) || mempath=""

# Activation: no memory submodule → nothing to do.
[ -z "$mempath" ] && exit 0
# Session-less worktree: memory worktree not materialized → nothing to do.
[ -e "$mempath/.git" ] || exit 0

# A prepared merge is answered before anything is committed on top of it.
gitlore_guard_stale_merge_state "$mempath" || exit 1
# A tier holding a prepared merge is answered before the summary is judged: the
# merge's directive is the message, not a request for a summary.
while IFS= read -r tier; do
  [ -n "$tier" ] || continue
  [ -e "$mempath/$tier/.git" ] || continue
  gitlore_guard_stale_merge_state "$mempath/$tier" || exit 1
done < <(gitlore_tier_paths "$mempath")

# Composition runs before the stores are judged: it writes tier carriers, so a
# root tier-line edit it propagates makes a tier dirty that the status below
# must see. A refusal or a failed write is reported by the sync's own compose,
# which runs again; a refusal writes nothing, so the state read here is the
# state the sync starts from.
gitlore_compose "$mempath" >/dev/null || true

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

# Nothing to commit: exit 0 whatever the summary says.
if [ "$root_has" = "0" ] && [ -z "$dirty_tiers" ]; then
  exit 0
fi

# The section check. Every refusal here precedes the first commit.
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

# Stage the memory gitlink into the superproject index (D58) when this run moved
# memory HEAD. A no-op run stages nothing. The staging is skipped during a replay
# (rebase, cherry-pick, revert): a replayed commit must keep the pointer it
# recorded, and the memory worktree does not move when the parent's HEAD does.
stage_memory_pointer() {
  local mempath="$1" super top rel p name op err
  super=$(git -C "$mempath" rev-parse --show-superproject-working-tree)
  [ -n "$super" ] || return 0
  top=$(git -C "$mempath" rev-parse --show-toplevel)
  rel="${top#"$super"/}"
  # Marker list: path:operation. A merge is deliberately absent — it is authored now.
  for marker in rebase-merge:rebase rebase-apply:rebase \
                CHERRY_PICK_HEAD:cherry-pick REVERT_HEAD:revert; do
    name="${marker%%:*}"
    p=$(git -C "$super" rev-parse --git-path "$name")
    case "$p" in /*) ;; *) p="$super/$p" ;; esac
    if [ -e "$p" ]; then
      op="${marker##*:}"
      echo "gitlore: $op in progress — skipping the staging of the memory pointer; stage it yourself once the $op is done." >&2
      return 0
    fi
  done
  if ! err=$(git -C "$super" add -- "$rel" 2>&1); then
    echo "gitlore: memory was committed, but its pointer could not be staged in the parent (git: $err). The pointer floats until you stage it." >&2
  fi
}

memory_before=$(git -C "$mempath" rev-parse HEAD)
gitlore_sync_memory_to_live "$mempath" "$summary" || exit 1
memory_after=$(git -C "$mempath" rev-parse HEAD)
if [ "$memory_before" != "$memory_after" ]; then
  stage_memory_pointer "$mempath"
fi
exit 0
