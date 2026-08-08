#!/usr/bin/env bash
set -euo pipefail

# PostToolBatch: report a plugin upgrade that landed after this session started,
# and name the one remedy (D21).
#
# CLAUDE_PLUGIN_ROOT is resolved once, at process start, from
# installed_plugins.json. The record keeps moving — another repo's session, or
# the user's own `/plugin update`, rewrites it mid-session. When the two
# disagree, everything this session froze at start (hook event registration,
# skill bodies, agent definitions, and the five gitlore.* git-config keys that
# point into the plugin root) belongs to the OLD version, and nothing available
# inside the session changes that.
#
# So this hook reports and never repairs. Repointing the git-config keys at the
# new root would leave CC-side registration on the old one — a split-version
# session, strictly worse than uniform staleness. Exit and relaunch with
# `claude -c` is the whole remedy: it is a full process restart that re-fires
# SessionStart (source=resume) and keeps the conversation.

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"
[ -n "$PLUGIN_ROOT" ] || exit 0

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"

payload=$(cat)

gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
gitlore_has_submodule || exit 0     # the gitlore.* keys only exist in a gitlore repo
mempath=$(gitlore_memory_path)
[ -e "$mempath/.git" ] || exit 0

# One override covers the record and the cache prefix derived from it, so the
# suite can drive this under a temp HOME without a second knob.
record="${GITLORE_PLUGIN_RECORD:-$HOME/.claude/plugins/installed_plugins.json}"
cache_prefix="$(dirname -- "$record")/cache/"

# CC sets no trailing slash, but the record's installPath carries none either
# and the comparison below is textual.
frozen="${PLUGIN_ROOT%/}"

# A --plugin-dir checkout is never stale, and without this guard gitlore's own
# development sessions would warn on every batch.
case "$frozen/" in
  "$cache_prefix"*) ;;
  *) exit 0 ;;
esac

[ -f "$record" ] || exit 0

session=$(jq -r '.session_id // ""' <<<"$payload")
marker=$(gitlore_upgrade_nudge_file "$mempath" "$session")
if [ -f "$marker" ]; then exit 0; fi   # once per episode; nudge-reset.sh re-arms it

# Every install of THIS plugin that applies here: the user-scoped entry, plus
# any entry pinned to this project. Owner-agnostic — the parent of the frozen
# root IS the plugin's cache family, so no `gitlore@ddaanet` literal is needed.
#
# No `grep -F` short-circuit ahead of the jq: the frozen root can appear in the
# record under a DIFFERENT projectPath, and a bare match would then read as
# "installed here" — a false negative. The jq costs less than this hook's own
# process spawn.
parent=$(dirname -- "$frozen")

errfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-upgrade.XXXXXX")
rc=0
candidates=$(jq -r --arg proj "$PWD" --arg parent "$parent/" '
  .plugins // {} | to_entries[] | .value[]
  | select(.scope == "user" or .projectPath == $proj)
  | select(.installPath | startswith($parent))
  | [.scope, .version, .installPath] | @tsv' "$record" 2>"$errfile") || rc=$?
err=$(cat "$errfile")
rm -f "$errfile"
if [ "$rc" -ne 0 ]; then
  # Captured rather than suppressed: a corrupt record is an expected, wholly
  # unactionable miss, but any other jq failure (missing binary, bad filter) is
  # a real fault and must still reach stderr.
  case "$err" in
    *"parse error"*|*"Invalid numeric literal"*) exit 0 ;;
    *) printf '%s\n' "$err" >&2; exit 0 ;;
  esac
fi

[ -n "$candidates" ] || exit 0

# Not stale if the frozen root IS one of the installs that apply here. A repo
# deliberately pinned behind the user-scoped version is therefore silent, which
# is the point.
if awk -F'\t' -v f="$frozen" '$3 == f { found = 1 } END { exit !found }' <<<"$candidates"; then
  exit 0
fi

# Name the entry pinned to this project when there is one. The remedy does not
# depend on which, but reporting the user-scoped version to a repo pinned
# elsewhere sends the reader after the wrong number.
new_ver=$(awk -F'\t' '$1 == "project" { print $2; exit }' <<<"$candidates")
if [ -z "$new_ver" ]; then
  new_ver=$(awk -F'\t' 'NR == 1 { print $2 }' <<<"$candidates")
fi
old_ver=$(basename -- "$frozen")

touch "$marker"

# Both channels (D14). systemMessage is user-only and additionalContext is
# model-only, and here each audience needs something the other cannot act on:
# only the user can exit and relaunch, and only the agent needs telling which
# repairs are dead ends. Routing the remedy through the agent alone would make a
# hot-path notice model-dependent, which D7 rules out — so the user-facing line
# names the remedy directly, departing from the usual no-instructions style.
sysmsg="gitlore: this session runs $old_ver, but $new_ver is what is installed for this repo. A mid-session upgrade does not take effect: hook registration, skill bodies and the five gitlore.* git-config keys are all fixed at process start. Exit Claude and relaunch with \`claude -c\` — it resumes this conversation."

# The prohibition is the load-bearing half: the session that prompted this ran
# two full cycles of exactly those remedies before the cause was found.
ctx="gitlore: the plugin was upgraded to $new_ver since this session started; this session still runs $old_ver and its git-config keys point into $old_ver. Nothing in this session can adopt it. Do not attempt a repair with /plugin, /reload-plugins, or by rewriting gitlore.* git config — none of them re-fire SessionStart. Tell the user to exit and relaunch with \`claude -c\`."

jq -n --arg s "$sysmsg" --arg c "$ctx" \
  '{systemMessage: $s, suppressOutput: true,
    hookSpecificOutput: {hookEventName: "PostToolBatch", additionalContext: $c}}'
exit 0
