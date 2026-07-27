#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

# Both PostToolBatch consumers below key on what CHANGED during the batch, so
# both need a baseline captured before it. Write and Edit announce their target,
# so the baseline is only taken when that target is an index. Bash announces
# nothing — the path is buried in a command line nobody should be parsing — so a
# Bash call takes the baseline unconditionally and the post hooks compare
# afterwards. Detecting the change instead of trusting the declaration is what
# closes the desync a `sed -i` on MEMORY.md used to leave behind: the edit landed
# and neither propagation nor composition ran.
payload=$(cat)
tool=$(jq -r '.tool_name // empty' <<<"$payload")
case "$tool" in Write|Edit|Bash) ;; *) exit 0 ;; esac

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0
mempath=$(gitlore_memory_path)
index="$mempath/MEMORY.md"
manifest="$mempath/.gitlore-tiers"
[ -e "$index" ] || exit 0

if [ "$tool" != "Bash" ]; then
  file=$(jq -r '.tool_input.file_path // empty' <<<"$payload")
  [ -n "$file" ] || exit 0
  # Only the project index or the tier manifest; identity via -ef (portable, no
  # realpath). A Write to either is what the two post hooks act on.
  target=""
  [ "$file" -ef "$index" ] && target=1
  [ -e "$manifest" ] && [ "$file" -ef "$manifest" ] && target=1
  [ -n "$target" ] || exit 0
fi

stash=$(gitlore_index_preimage_file "$mempath")   # absolute; parent dir exists
stamp=$(gitlore_compose_stamp_file "$mempath")

# First index-touching call of the batch establishes the baselines; later ones in
# the same batch must not overwrite them, or a batch-end comparison would run
# against a mid-batch state and miss everything the earlier calls changed. Each
# post hook removes its own file at batch end (even when nothing was touched), so
# an existing one here always belongs to the batch in flight.
if [ ! -f "$stamp" ]; then
  gitlore_compose_stamp "$index" "$manifest" > "$stamp" || \
    printf 'gitlore: failed to stamp the pre-edit index state (%s)\n' "$stamp" >&2
fi

if [ -f "$stash" ]; then exit 0; fi

# Capture cp's reason rather than dropping it — "why" (no space, permissions,
# bad path) is exactly what makes this recoverable for the user.
if ! cp_err=$(cp "$index" "$stash" 2>&1); then
  # Never exit 2 (would block the Write) and never exit 1 (stdout JSON is
  # only parsed on exit 0 — D14). systemMessage + exit 0 is the only channel
  # proven user-visible regardless of exit code; stderr is a debug-log echo.
  printf 'gitlore: failed to stash the pre-edit MEMORY.md (%s): %s\n' "$stash" "$cp_err" >&2
  jq -n --arg stash "$stash" --arg err "$cp_err" \
    '{systemMessage: ("gitlore: failed to stash the pre-edit MEMORY.md (" + $stash + "): " + $err + "; index→frontmatter sync will be skipped for this edit")}'
fi
exit 0
