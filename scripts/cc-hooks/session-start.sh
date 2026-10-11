#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
# Read once, here, before the guards below start exiting: this is the script's
# only read of stdin, and the session_id it carries is parsed from it at its
# one use, near the relay drain at the end.
payload=$(cat)
gitlore_cd_project_root || exit 0   # the launch repo, never the session cwd (see util.sh)
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/log.sh"
# gitlore_get_frontmatter_description, for tier routing guidance (D17).
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-sync.sh"
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/index-compose.sh"
# gitlore_detect_stale_merge_state, so the tier re-detach below can tell a store
# with a merge prepared in it from one it may safely check out.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/resolve.sh"
# gitlore_sync_nested_tiers, the "Nested tiers" stage below.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/session-tiers.sh"
# report_memory_position, the "where memory stands" stage below.
# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/session-memory.sh"

# Guard 1: gitlore.enabled
# Guard on the file rather than suppressing jq: "no settings.json" is the normal
# not-a-gitlore-repo case, but a *malformed* settings.json is a real fault that
# would otherwise be silently downgraded to "gitlore disabled" — the whole hook
# then no-ops with no explanation.
[ -f .claude/settings.json ] || exit 0
# The missing-file case is handled by the guard above; a MALFORMED file is a
# real fault and must not be folded into it. `enabled=$(... || echo false)`
# used to downgrade a parse error to plain "false" — jq's own message still
# reached stderr, but SessionStart's stderr is invisible to the user outside
# --verbose (see the comment on `exec 3>&1 1>&2` below), so nothing the user
# actually sees said gitlore had gone silent. Report it on the one channel
# that is: the SessionStart systemMessage, emitted directly to stdout here,
# before that redirection takes effect.
if ! enabled=$(jq -r '.gitlore.enabled // false' .claude/settings.json 2>&1); then
  jq -nc --arg e "$enabled" \
    '{systemMessage:("gitlore: .claude/settings.json could not be parsed, so gitlore is inactive this session: " + $e)}'
  exit 0
fi
[ "$enabled" = "true" ] || exit 0

# Guard 2: gitlore-memory submodule registered
gitlore_has_submodule || exit 0

mempath=$(gitlore_memory_path)

# Keep stdout clean: everything below logs to stderr; only the guard JSON (if any)
# goes to real stdout (fd 3), which CC parses for systemMessage/additionalContext.
exec 3>&1 1>&2

# Standing commit-protocol orientation (Fix B / FR11). The base Claude Code memory
# instructions describe generic "edit files, save facts" memory with no review gate;
# in a gitlore repo that mental model is wrong and leads to direct submodule commits
# that bypass the gate. Emit it every session, before the agent acts: the prohibition
# guards an action the agent would otherwise take unprompted, so it cannot be
# deferred, and the commit command is front-loaded because no hook surfaces it any
# more — a parent commit does not commit memory (D58), so the agent that holds the
# user's approval runs commit-memory.sh itself. Writing stays seamless: an ordinary
# edit, with no approval step before it, so the text does not induce ceremony.
# The text is acts, carrying no mechanism: what the gate is, which hook blocks, and
# what it records are things the agent cannot act on, and the gate emits its own
# instructions at the moment it fires. The prohibition forbids by role rather than
# naming the command forms — spelling out `git -C <mempath> commit` invites reasoning
# about the forms not named — and nothing here cites an FR id, which resolves to
# nothing in the consumer repos this context lands in.
# The `$(git config …)` is literal text for the agent to run, so it is escaped here.
protocol_ctx="gitlore: writing a memory file is an ordinary edit. To commit memory, summarize the pending changes, get the user's explicit approval, then run bash \"\$(git config gitlore.commitCommand)\" -F - from the repo root with the approved summary on stdin, through a quoted heredoc (<<'EOF') so the shell expands nothing in it. Never run git commit inside the memory submodule. A request to commit memory is not approval of a summary the user has not seen: show the summary, end your turn, and commit only after the user's reply approves it."

# User-facing output (D14): every user-visible SessionStart notice rides the
# single SessionStart `systemMessage` (the only reliably user-visible hook
# channel; stderr is shown only on exit 2 / --verbose). `sysmsg` accumulates
# notices; `emit_session_json` writes the one JSON to fd 3 (systemMessage when
# non-empty, plus the standing commit-protocol additionalContext always).
sysmsg=""
add_sysmsg() {
  if [ -n "$sysmsg" ]; then sysmsg="$sysmsg

$1"; else sysmsg="$1"; fi
}
emit_session_json() {
  if [ -n "$sysmsg" ]; then
    jq -nc --arg sys "$sysmsg" --arg ctx "$protocol_ctx" \
      '{systemMessage:$sys, hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}' >&3
  else
    jq -nc --arg ctx "$protocol_ctx" \
      '{hookSpecificOutput:{hookEventName:"SessionStart", additionalContext:$ctx}}' >&3
  fi
  exec 3>&- 1>&2
}

# Launcher guard (D10): without the shim, GITLORE_LAUNCHED is unset and CC's
# native auto-memory strands in ~/.claude/projects/<cwd>/memory instead of the submodule.
if [ -z "${GITLORE_LAUNCHED:-}" ]; then
  add_sysmsg "gitlore: memory is NOT redirected — this session was started with a plain 'claude', so auto-memory will strand in the default directory, not the submodule. Fix: run 'direnv allow' in this repo (or '/gitlore:install-launcher' if you don't use direnv), then restart Claude Code."
  protocol_ctx="$protocol_ctx

gitlore: GITLORE_LAUNCHED is unset — the launcher shim did not run, so CC auto-memory is writing to the default ~/.claude/projects/<cwd>/memory dir, NOT the gitlore submodule. Tell the user to run 'direnv allow' (Placement A) or '/gitlore:install-launcher' (Placement B) and restart. Do NOT write autoMemoryDirectory to any settings file — that tier is ignored (D10)."
fi

# Hook dir + wrappers.
git config gitlore.hooksDir "$PLUGIN_ROOT/scripts/git-hooks"
git config gitlore.commitCommand "$PLUGIN_ROOT/scripts/commit-memory.sh"
git config gitlore.pushCommand "$PLUGIN_ROOT/scripts/push-memory.sh"
git config gitlore.mergeCommand "$PLUGIN_ROOT/scripts/merge-memory.sh"
git config gitlore.memoryApprovalClauseFile "$PLUGIN_ROOT/reference/memory-approval-clause.txt"
bash "$PLUGIN_ROOT/scripts/emit-wrappers.sh"

# Sentinel replay: re-apply hook-setup recorded at install time.
SENTINEL=".claude/gitlore-hook-setup"
if [ -f "$SENTINEL" ]; then
  cmd=$(head -1 "$SENTINEL" | tr -d '\n')
  case "$cmd" in
    "")
      echo "gitlore: empty sentinel; nothing to replay" >&2
      ;;
    direct)
      bash "$PLUGIN_ROOT/scripts/hook-manager/wire-direct.sh"
      ;;
    manual)
      echo "gitlore: hook wiring is 'manual'; verify your hooks still invoke \$(git rev-parse --git-common-dir)/gitlore-pre-*." >&2
      ;;
    # The sentinel is a TRACKED file — a fresh clone brings whatever its first
    # line says, so an unconstrained `sh -c "$cmd"` here would run any line
    # that clone carried at the very first session start. Only the three known
    # hook-manager installers (wire-lefthook.sh/wire-husky.sh/wire-overcommit.sh
    # are the only writers) are legitimate `*)` content; each runs as the
    # literal command, never through `sh -c`, so nothing beyond that fixed set
    # can execute.
    "lefthook install")
      lefthook install
      ;;
    "npx husky")
      npx husky
      ;;
    "overcommit --install")
      overcommit --install
      ;;
    *)
      add_sysmsg "gitlore: .claude/gitlore-hook-setup names an unrecognized command ('$cmd') and was not run. gitlore only replays the three known hook-manager installers (lefthook install, npx husky, overcommit --install). Run the command yourself, or set the sentinel's first line to 'manual'."
      ;;
  esac
fi

# Branch model: submodule init, detach at live, report where it stands.
# Memory working tree missing in this worktree. Two cases:
#  - submodule never initialized (main worktree, fresh clone) → submodule update;
#  - submodule initialized in the main repo but this is a *linked* worktree whose
#    memory tree was never checked out → create it from the shared submodule gitdir.
# Plain `git submodule update --init` does not reliably populate a submodule in a
# linked worktree, so the linked case uses an explicit `git worktree add`.
if [ ! -e "$mempath/.git" ]; then
  # CDPATH='' cd --: --git-common-dir returns a RELATIVE '.git' in a main
  # worktree, and a set CDPATH would resolve it elsewhere *and* make cd echo the
  # destination, yielding a two-line, wrong common_dir.
  common_dir=$(CDPATH='' cd -- "$(git rev-parse --git-common-dir)" && pwd)
  mem_gitdir="$common_dir/modules/$GITLORE_SUBMODULE_NAME"
  if [ -d "$mem_gitdir" ]; then
    git -C "$mem_gitdir" worktree prune >/dev/null 2>&1 || true
    git -C "$mem_gitdir" worktree add --detach "$PWD/$mempath" live >&2
  else
    git submodule update --init -- "$mempath" >&2
  fi
fi

# Fresh clone (FR7): `git submodule update --init` checks out the recorded
# gitlink SHA as a detached HEAD and creates no local branches. The report
# below reads `live` as a *local* ref, so materialize it first, from HEAD: the
# gitlink commit is what a clone has checked out, whether or not `origin/live`
# exists (D59). Never from `origin/live`, which may be ahead of it. No-op once
# live exists (install, normal sessions, linked worktrees).
if ! git -C "$mempath" show-ref --verify --quiet refs/heads/live; then
  gitlore_git -C "$mempath" branch live HEAD >&2
fi

# Branch model (D17): memory is checked out DETACHED — `live` is the sole
# travelling ref and is never checked out as a branch, so one memory gitdir
# serves any number of parent worktrees and every commit path reduces to
# "pending HEAD vs live". Detaching is done *in place* (no ref argument), which
# keeps the current commit and any uncommitted work. Nothing at session start
# advances HEAD onto live: /gitlore:merge does that. A session that predates
# this model arrives on a named branch and is migrated here, losing nothing —
# the old model advanced `live` on every commit, so the branch never held
# anything `live` did not.
if git -C "$mempath" symbolic-ref -q HEAD >/dev/null; then
  gitlore_git -C "$mempath" checkout -q --detach
fi

# Wire the submodule-side commit gate (Fix A / FR11). Runs after the memory
# worktree exists so its gitdir hooks dir is resolvable. Idempotent; re-pins the
# submodule's gitlore.hooksDir to the live plugin each session.
bash "$PLUGIN_ROOT/scripts/emit-memory-gate.sh"

report_memory_position "$mempath"

# Root index repair. A store can arrive with no `MEMORY.md` at all: an install
# seeded from an auto-memory dir that existed but held nothing committed an
# empty tree, and the working tree has no file to lose. Every path from here on
# assumes the scaffold exists — composition places tier lines into it, a merge
# continuation stages it, the byte-budget nudge measures it — and the dangling
# report below cannot notice, since it reads pointers out of a file that is not
# there. Write the scaffold back as an ordinary dirty file: it joins the next
# FR11 commit under review, never a commit of its own, and it runs AFTER the
# report so the report reads the store as it arrived, not marked dirty by the
# repair. Never fatal — an unwritable store is reported, not aborted on.
if [ ! -f "$mempath/MEMORY.md" ]; then
  if printf '# Memory Index\n\n(populated by Claude over time)\n' > "$mempath/MEMORY.md"; then
    add_sysmsg "gitlore: the memory store had no root MEMORY.md, so nothing could compose into it or be recalled from it. The '# Memory Index' scaffold was written as an uncommitted file; it lands with the next memory commit."
  else
    add_sysmsg "gitlore: the memory store has no root MEMORY.md and the scaffold could not be written to $mempath/MEMORY.md. Create it by hand (first line '# Memory Index') before writing memory."
  fi
fi

# Nested tiers (D17 3-i-a): check each tier submodule inside the memory store out
# at the commit the memory tree records for it, pin it, and report what its
# remote holds. gitlore_sync_nested_tiers (scripts/lib/session-tiers.sh) is the
# whole stage; it calls add_sysmsg and appends to protocol_ctx directly.
gitlore_sync_nested_tiers "$mempath"

# Compose after the tier pin, so the lines each pinned carrier holds surface in
# the always-loaded root index this session rather than next (D17 3-ii). Never
# fatal: a store that fails validation is reported and left alone — SessionStart
# must always finish.
compose_rc=0
compose_problems=$(gitlore_compose "$mempath") || compose_rc=$?
if [ "$compose_rc" -eq 2 ]; then
  # Not a refusal: a write failed partway, so some indexes are composed and one
  # is not. The fail-safe wording below would misdescribe the store.
  add_sysmsg "gitlore: tier composition could not write an index; the memory indexes are only partly composed:
$compose_problems"
elif [ "$compose_rc" -ne 0 ]; then
  add_sysmsg "gitlore: tier composition refused; the memory indexes were left untouched:
$compose_problems"
else
  # The fifth validation reports rather than refuses — a bullet whose file is
  # absent leaves the composed output correct, so it is named, not acted on.
  dangling=$(gitlore_compose_dangling "$mempath")
  if [ -n "$dangling" ]; then
    # One synthetic notice, capped: a whole tier's worth of stale pointers must
    # not flood the user's systemMessage (nor get UI-truncated to "and many more
    # lines"). List a few, count the rest.
    dangling_count=$(printf '%s\n' "$dangling" | grep -c .)
    if [ "$dangling_count" -eq 1 ]; then dangling_unit="file"; else dangling_unit="files"; fi
    dangling_capped=$(printf '%s\n' "$dangling" | gitlore_cap_list)
    add_sysmsg "gitlore: the memory index points at $dangling_count missing $dangling_unit. Nothing was rewritten or deleted — restore each file, or remove its line (removing a line deletes nothing).
$dangling_capped"
    # The agent gets a matching, equally-capped additionalContext: the
    # systemMessage is user-only (D14), so without this the agent has no idea the
    # always-loaded index it is about to trust is stale. Terse on purpose — enough
    # to know it is broken and what to do, not the whole list.
    protocol_ctx="$protocol_ctx

gitlore: the memory index is STALE — $dangling_count root MEMORY.md pointer $dangling_unit name a target absent from the memory store (composition still produced a correct index; nothing was deleted). Likely another consumer merged or renamed those facts in a shared tier. Reconcile the root index: drop each stale line, or redirect it to where the fact now lives.
$dangling_capped"
  fi
fi

# Routing guidance (D17): advertise each ACTIVE tier (listed in the manifest)
# and its self-described purpose, so the agent routes a portable fact to the
# right tier instead of burying it in project-local memory. A mounted but
# unlisted tier is dormant and intentionally not advertised. The scope
# resolution itself lives in gitlore_active_tier_scopes (shared with the
# post-mount triage nudge in index-compose.sh) — this loop only formats it.
tier_guidance=""
while IFS= read -r line; do
  tier_guidance="$tier_guidance
  - $line"
done < <(gitlore_active_tier_scopes "$mempath")

if [ -n "$tier_guidance" ]; then
  protocol_ctx="$protocol_ctx

gitlore memory tiers: shared memory stores mounted inside the memory submodule. Write a portable fact into the matching tier's directory (same one-file-per-fact format), and add its index line to the ROOT $mempath/MEMORY.md with the tier prefix — '- [Title](<tier>/<file>.md) — hook'. gitlore mirrors that line down into the tier's own index for you. Facts specific to this project stay in $mempath/ with a bare path.$tier_guidance"
fi

# Relay: drain this session's own markers (D51) — the only path a report
# reaches a session that resumed or compacted, since neither event fires the
# PostToolBatch drainer relay-drain.sh is registered on. Own-session only: a
# report addressed to a session that ended is undeliverable — the conversation
# it describes is gone — so it is left for the sweep below rather than folded
# into a stranger's session.
#
# Placed before the FINAL emit below. A report addressed to a session that
# ended is a stranger to this one and is left to the sweep, exactly as for any
# other session's report; a resume or a compaction of the same session
# collects its own here, since both keep the session id.
#
# Then sweep: remove every gitlore-relay-* file older than 7 days, temps
# included, regardless of session. A report addressed to a session that ended
# with no further batch is never drained by anyone; age is the only backstop
# it gets, and the store state it reported on is re-covered by this script's
# own structural pass above.
#
# Both calls absorb every failure a marker or its gitdir can produce — a
# marker that cannot be read folds as an empty block, an `rm -f`/`-delete` the
# gitdir refuses is swallowed — and return 0 on every path, so there is
# nothing here for this file's `set -e` to trip on.
#
# Guarded on $GITLORE_RELAY_SYSMSG, deliberately NOT nested inside
# `[ -n "$sysmsg" ]`: report_memory_position adds a line for every position a
# store can be in, so $sysmsg is never empty by the time we reach here today —
# but that is an accident of that function, not a contract this fold may lean
# on. Conditioning on it would be behaviour-identical now and would silently
# drop the relay the day a position stops reporting.
# Non-fatal: the relay is a backstop, never a reason a session fails to start.
# jq has already parsed .claude/settings.json above — the hook exits when it
# cannot — so the only failure left here is a malformed payload, and it costs
# the own-session keying alone: the sweep below still runs.
session=$(jq -r '.session_id // ""' <<<"$payload") || session=""
gitlore_relay_drain "$mempath" "$session"
gitlore_relay_sweep "$mempath"
if [ -n "$GITLORE_RELAY_SYSMSG" ]; then
  add_sysmsg "$GITLORE_RELAY_SYSMSG"
  protocol_ctx="$protocol_ctx

$GITLORE_RELAY_CTX"
fi

# Emit one SessionStart JSON: the commit-protocol additionalContext always, plus
# any accumulated user-facing systemMessage (position report, launcher — D14).
emit_session_json
