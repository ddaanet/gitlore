#!/usr/bin/env bash
# The retired store gate's cleanup stage of session-start.sh (D70). Sourced by
# session-start.sh only. An earlier release wrote a `pre-commit` wrapper into
# memory/ and each mounted tier and mirrored `gitlore.hooksDir` beside it; both
# are removed when the hook carries that wrapper's marker, its
# `exec "$HOOKS_DIR/memory-pre-commit" "$@"` line, which every release of the
# wrapper wrote; any other `pre-commit` is the user's and stays.

# Remove the retired wrapper and its hooksDir mirror from the store at $1.
# Silent, and never fails the caller: a store that cannot be inspected is left.
gitlore_retire_store_gate() {
  local store="$1" hooks hook
  [ -e "$store/.git" ] || return 0   # unchecked-out: `git -C` would escape to the parent
  hooks=$(git -C "$store" rev-parse --git-path hooks 2>/dev/null) || return 0
  case "$hooks" in /*) ;; *) hooks="$store/$hooks" ;; esac
  hook="$hooks/pre-commit"
  [ -f "$hook" ] || return 0
  # shellcheck disable=SC2016  # the marker is the literal wrapper line, not an expansion
  if grep -Fxq -- 'exec "$HOOKS_DIR/memory-pre-commit" "$@"' "$hook"; then
    rm -f -- "$hook"
    git -C "$store" config --local --unset gitlore.hooksDir 2>/dev/null || true
  fi
  return 0
}

# Run the cleanup over memory/ and every mounted tier.
gitlore_retire_store_gates() {
  local mempath="$1" tier
  gitlore_retire_store_gate "$mempath"
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    gitlore_retire_store_gate "$mempath/$tier"
  done < <(gitlore_tier_paths "$mempath" 2>/dev/null || true)
  return 0
}
