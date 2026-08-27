#!/usr/bin/env bash
set -euo pipefail

PLUGIN_ROOT="${CLAUDE_PLUGIN_ROOT:-}"

# shellcheck disable=SC1091
source "$PLUGIN_ROOT/scripts/lib/util.sh"
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
# that bypass the gate. Emit the *prohibition* every session, before the agent acts —
# it guards an action the agent would otherwise take unprompted, so it cannot be
# deferred. The four-step persist *procedure* is NOT preloaded: front-loading a recipe
# reads as "a process you must run" and makes the agent run ceremony (pausing for
# approval before even writing a memory file) when persistence is meant to be seamless.
# The procedure is surfaced just-in-time instead — by the memory-pre-commit hook's own
# output if a direct commit is blocked, and by /gitlore:resolve on divergence. Here we
# keep only the prohibition plus the one-line seamless happy path (commit the parent;
# the hook does the rest), which defuses over-worry rather than feeding it.
protocol_ctx="gitlore: memory in this repo lives in a git submodule guarded by a per-commit approval gate (FR11). NEVER commit inside the memory submodule directly — do not run 'git -C <mempath> commit' or 'cd <mempath> && git commit' (the submodule has a pre-commit hook that will block you). Persisting memory is seamless: writing a memory file is an ordinary edit, and committing the PARENT repo is all you need — its pre-commit hook records, gates, and pushes memory for you."

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

# Branch model: submodule init, detach at live, ff-merge.
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
# gitlink SHA as a detached HEAD and creates no local branches — only
# `origin/live` exists. The branch-model logic below references `live` as a
# *local* ref (detach target and ff-merge source), so materialize it first.
# Prefer origin/live; fall back to the checked-out gitlink commit (HEAD) when
# the memory has no remote (degenerate, never-pushed case). No-op once live
# exists (install, normal sessions, linked worktrees).
if ! git -C "$mempath" show-ref --verify --quiet refs/heads/live; then
  if git -C "$mempath" show-ref --verify --quiet refs/remotes/origin/live; then
    gitlore_git -C "$mempath" branch live origin/live >&2
  else
    gitlore_git -C "$mempath" branch live HEAD >&2
  fi
fi

# Branch model (D17): memory is checked out DETACHED — `live` is the sole
# travelling ref and is never checked out as a branch, so one memory gitdir
# serves any number of parent worktrees and every commit path reduces to
# "pending HEAD vs live". Detaching is done *in place* (no ref argument), which
# keeps the current commit and any uncommitted work; the ff-merge below is what
# advances HEAD onto live. A session that predates this model arrives on a named
# branch and is migrated here, losing nothing — the old model advanced `live` on
# every commit, so the branch never held anything `live` did not.
if git -C "$mempath" symbolic-ref -q HEAD >/dev/null; then
  gitlore_git -C "$mempath" checkout -q --detach
fi

# Wire the submodule-side commit gate (Fix A / FR11). Runs after the memory
# worktree exists so its gitdir hooks dir is resolvable. Idempotent; re-pins the
# submodule's gitlore.hooksDir to the live plugin each session.
bash "$PLUGIN_ROOT/scripts/emit-memory-gate.sh"

if [ "$(gitlore_memory_dirty "$mempath")" = "0" ]; then
  if merge_err=$(gitlore_git -C "$mempath" merge --ff-only live 2>&1); then
    add_sysmsg "gitlore: memory ready (detached at live)."
  elif [ "$(gitlore_classify_refusal "$mempath" HEAD live)" = "diverged" ]; then
    # Only a genuine divergence between HEAD and live is something
    # /gitlore:resolve can fix — a lock, a corrupt object or an unwritable
    # worktree all refuse --ff-only too, and sending the user to resolve for
    # those would be a guess replacing git's own explanation (never do that).
    add_sysmsg "gitlore: memory diverged from live. Run /gitlore:resolve, then start a fresh session."
    emit_session_json
    exit 0
  else
    add_sysmsg "gitlore: memory could not be fast-forwarded onto live. git said:
$merge_err"
    emit_session_json
    exit 0
  fi
else
  add_sysmsg "gitlore: memory ready (detached at live); uncommitted changes present, skipped live sync."
fi

# Nested tiers (D17 3-i-a): check each tier submodule inside the memory store out
# at the commit the memory tree records for it. Discovery is by enclosure — every
# entry in memory/.gitmodules is a tier. Tiers use the detached branch model
# (D17): no named working branch.
#
# A tier is PINNED at its gitlink and never fast-forwarded here. One memory
# commit records `MEMORY.md` and the tier gitlink together, so root's tier block
# and the carrier index it projects are consistent by construction; advancing the
# tier behind root's back breaks that pairing, and nothing downstream can repair
# it — composition places lines, it does not merge them. Taking an upstream
# commit is a merge, and it goes through /gitlore:merge or /gitlore:push.
#
# Every git call is guarded: a broken tier must never abort the session.
while IFS= read -r tier; do
  [ -n "$tier" ] || continue
  tierpath="$mempath/$tier"
  # A prepared merge is detected FIRST, before anything that checks out. `git
  # checkout` — which `submodule update` runs — calls remove_branch_state(),
  # unlinking MERGE_HEAD and MERGE_MSG silently and on success; a clean
  # auto-merge stages no unmerged entries, so even a no-op re-checkout of the
  # commit HEAD is already on succeeds and destroys the merge pointers while
  # leaving the staged result behind. What survives is a state file with no
  # MERGE_HEAD, which gitlore_recover_stale_no_merge_head can repair — by
  # writing the pointers back — but only by reading the index to decide how, and
  # a session start that provokes the damage every time makes that repair the
  # normal path rather than the recovery it is. Skip the whole tier, and say
  # so — a suppressed pass must not be silent, or the tier looks synced when it
  # is mid-merge.
  # `detect` rather than `guard_stale_merge_state`: the guard's directive tells
  # the agent to abort and retry, which is wrong for a merge that is simply
  # waiting to be landed, and it writes to stderr, which SessionStart does not
  # show the user (D14).
  # The `.git` test leads: `git -C` into an unchecked-out submodule path walks up
  # to the enclosing repo, so an unmaterialized tier would be answered for by
  # memory's own merge state.
  if [ -e "$tierpath/.git" ] \
     && { [ "$(gitlore_detect_stale_merge_state "$tierpath")" != "clean" ] \
          || git -C "$tierpath" rev-parse -q --verify MERGE_HEAD >/dev/null; }; then
    add_sysmsg "gitlore: tier '$tier' has an unfinished merge, so its working tree was left as it is this session. Run /gitlore:resolve to land it."
    # The agent gets its own line: systemMessage is user-only (D14), and the
    # destructive acts here are ones the agent takes unprompted, so the
    # prohibition leads and the remedy follows. Uncapped, unlike the dangling
    # report — a gate yields on the first divergence it meets and stops, so two
    # tiers mid-merge at once is not a state the tooling produces.
    protocol_ctx="$protocol_ctx

gitlore: tier at $tierpath holds an unfinished merge. Do not check it out, reset it, or commit into it. Run /gitlore:resolve to land the merge before writing anything to that tier."
    continue
  fi
  # Pin, unconditionally — not only when the tier was never checked out. Every
  # clone made before tiers were pinned sits ahead of its gitlink already, so a
  # pass that only materializes a missing tier would pin nothing that exists.
  # `--init` covers materialization in the same call.
  gitlore_git -C "$mempath" submodule update --init -- "$tier" >&2 \
    || add_sysmsg "gitlore: tier '$tier' could not be checked out at its recorded commit; skipped."
  [ -e "$tierpath/.git" ] || continue
  # Detach in place (no ref argument, so the commit does not move) when the tier
  # arrived on a named branch — a mount checks the remote's default branch out
  # attached, and `submodule update` leaves it that way whenever that branch's
  # tip already IS the gitlink. The tier branch model has no working branch: a
  # commit made on one would advance a ref the lockstep does not read.
  if git -C "$tierpath" symbolic-ref -q HEAD >/dev/null; then
    gitlore_git -C "$tierpath" checkout -q --detach \
      || add_sysmsg "gitlore: tier '$tier' could not be detached from its branch."
  fi
  # Fetch read-only: `origin live` with no refspec moves no local branch, so the
  # pin holds and the remote tip is still in hand to compare against. Non-fatal —
  # a session must start whatever a tier's remote says — but NOT silent: a tier
  # that has quietly stopped talking to its remote is indistinguishable from one
  # with nothing new, so capture the reason and report it.
  if ! fetch_err=$(git -C "$tierpath" fetch origin live 2>&1); then
    add_sysmsg "gitlore: tier '$tier' could not fetch from its remote; it may be stale. git said: $fetch_err"
    continue
  fi
  # Name what is waiting. Three outcomes, two of them worth a word: the remote
  # contained in HEAD is the lockstep's business (local commits awaiting a push),
  # and saying "waiting" there would send the user into a merge with nothing to
  # merge.
  tier_head=$(git -C "$tierpath" rev-parse HEAD) || continue
  tier_remote=$(git -C "$tierpath" rev-parse FETCH_HEAD) || continue
  if git -C "$tierpath" merge-base --is-ancestor "$tier_remote" "$tier_head"; then
    :
  elif git -C "$tierpath" merge-base --is-ancestor "$tier_head" "$tier_remote"; then
    add_sysmsg "gitlore: tier '$tier' has upstream facts waiting — its remote 'live' is ahead of the pinned commit. Run /gitlore:merge to take them, or /gitlore:push to take them and publish."
  else
    add_sysmsg "gitlore: tier '$tier' has diverged from its remote 'live' — each side has commits the other lacks. Run /gitlore:merge to reconcile them, or /gitlore:push to reconcile and publish."
  fi
done < <(gitlore_tier_paths "$mempath")

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

# Emit one SessionStart JSON: the commit-protocol additionalContext always, plus
# any accumulated user-facing systemMessage (success/dirty/launcher — D14).
emit_session_json
