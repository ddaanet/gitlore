#!/usr/bin/env bash
# Shared shell utilities. Source; do not exec.

# The canonical submodule name regardless of working-tree path.
GITLORE_SUBMODULE_NAME="gitlore-memory"
readonly GITLORE_SUBMODULE_NAME

# The url `.gitmodules` carries for a local-only install, where the memory store
# is versioned in-repo with nowhere to push. It is a marker, not an address: git
# needs *some* url on the entry (without one, `submodule update --init` dies with
# "No url found for submodule path"), and this particular one is what tells the
# remote-creation and repair paths that the slot is theirs to fill.
#
# `git submodule sync` absolutizes a relative url before copying it into the
# submodule's `remote.origin.url`, so what lands there is
# `<parent>/.git/gitlore-placeholder` and never the registered spelling. Compare
# with gitlore_is_placeholder_url, which accepts both.
GITLORE_PLACEHOLDER_URL="./.git/gitlore-placeholder"
readonly GITLORE_PLACEHOLDER_URL

# True when $1 is the placeholder in either spelling git may have produced: the
# registered form in `.gitmodules`, or the absolutized one a `submodule sync`
# writes into `remote.origin.url`. Matching the basename is what covers the
# second, since the prefix is whatever the superproject happened to live at.
# Args: $1 = a url, possibly empty (an unset remote is not a placeholder).
gitlore_is_placeholder_url() {
  case "$1" in
    "$GITLORE_PLACEHOLDER_URL"|*/"${GITLORE_PLACEHOLDER_URL##*/}") return 0 ;;
    *) return 1 ;;
  esac
}

# Marker phrase in the in-tree migration breadcrumb. Single source of truth,
# matched as a fixed string by gitlore_is_migration_stub and written into the
# stub body by gitlore_mark_migrated.
# shellcheck disable=SC2016  # literal marker text; the backticks are not a command sub
GITLORE_MIGRATION_MARKER='migrated in-tree by `/gitlore:install`'
readonly GITLORE_MIGRATION_MARKER

# cd to the repo every gitlore hook operates on: the LAUNCH repo, not whatever
# directory the session is sitting in. Claude Code's in-process EnterWorktree
# moves the session cwd into a linked worktree but freezes the launch
# environment — CLAUDE_PROJECT_DIR and the auto-memory directory both — so
# memory keeps landing in the launch repo's store (D15). A hook that followed
# cwd would read and write a different store from the one being written to, and
# from the one nudge-reset.sh clears: a once-per-episode marker would then never
# be re-armed across a compaction.
#
# Every hook calls this before it touches a repo. worktree-drift.sh is the one
# exception, because comparing the two locations IS its job.
gitlore_cd_project_root() {
  cd "${CLAUDE_PROJECT_DIR:-$PWD}" || return 1
}

# Write an executable hook wrapper that resolves the live plugin via
# `git config gitlore.hooksDir` and degrades to a clean skip (exit 0) when that
# config is unset or the target hook is missing (plugin upgraded + cache GC'd),
# so a transient plugin state never bricks a commit/push (NFR8/D5). Shared by the
# parent-hook wrappers (emit-wrappers.sh) and the submodule gate (emit-memory-gate.sh).
# Args: $1 = output file path; $2 = hook name to exec under HOOKS_DIR.
gitlore_emit_hook_wrapper() {
  local out="$1" hook="$2"
  cat > "$out" <<EOF
#!/usr/bin/env sh
HOOKS_DIR=\$(git config gitlore.hooksDir)
if [ -z "\$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
  exit 0
fi
if [ ! -x "\$HOOKS_DIR/$hook" ]; then
  echo "gitlore skipped: hooks dir is stale (plugin upgraded; cache GC'd)." >&2
  echo "Relaunch Claude Code in this repo with 'claude -c' to refresh the hooks dir, then retry." >&2
  exit 0
fi
exec "\$HOOKS_DIR/$hook" "\$@"
EOF
  chmod +x "$out"
}

# Print the memory submodule's working-tree path (relative to repo root).
# Exit 1 if the submodule is not registered.
gitlore_memory_path() {
  local path
  # No redirect: `git config --file` is silent when the file or key is absent
  # (rc=1, verified), so anything on stderr here is a genuine fault.
  path=$(git config --file .gitmodules \
    "submodule.${GITLORE_SUBMODULE_NAME}.path") || return 1
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

# Exit 0 if .gitmodules registers the gitlore-memory submodule, 1 otherwise.
gitlore_has_submodule() {
  # No stderr redirect: gitlore_memory_path is already silent on the expected
  # miss (its own comment above), so anything it sends to stderr here is the
  # genuine fault that comment describes — swallowing it would drop that.
  gitlore_memory_path >/dev/null
}

# Ref pinning the pending (divergent) commit while a merge is prepared. Under
# the detached-at-`live` branch model no named branch holds that commit, and
# `merge --abort` drops MERGE_HEAD — without this ref the only remaining handle
# would be the reflog, which is prunable. Created by gitlore_prepare_merge,
# deleted once the merge lands or is abandoned.
# shellcheck disable=SC2034  # consumed by sourcing scripts (lib/resolve.sh, resolve.sh)
readonly GITLORE_PENDING_REF="refs/gitlore/pending"

# Print abs path to the `.claude/` dir in the PARENT working tree that hosts the
# memory IPC files (message, commit trigger, notified marker). Resolves the
# superproject working tree; falls back to the memory worktree's parent dir when
# memory is not a registered submodule (or is detached). Relocated 2026-07-16
# from the submodule gitdir so the agent can write these under auto mode — the
# gitdir is unwritable via every agent tool (Write and a bash heredoc are both
# classifier/sandbox denied). Args: $1 = memory worktree path (relative or absolute).
_gitlore_ipc_dir() {
  local mempath="$1" super=""
  # Guard on the gitlink rather than suppressing stderr: without a checked-out
  # memory worktree the rev-parse would fail with an expected "not a git
  # repository", which is exactly the fallback case below. Guarding removes the
  # expected failure, so a *real* rev-parse error is no longer swallowed.
  if [ -e "$mempath/.git" ]; then
    super=$(git -C "$mempath" rev-parse --show-superproject-working-tree) || super=""
  fi
  if [ -z "$super" ]; then
    super=$(CDPATH='' cd -- "$(dirname -- "$mempath")" && pwd)
  fi
  printf '%s/.claude\n' "$super"
}

# Print abs path to the memory commit-message IPC file. The agent writes the
# approved commit summary here; gitignored (see `.gitignore`).
gitlore_commit_msg_file() {
  printf '%s/gitlore-memory-message\n' "$(_gitlore_ipc_dir "$1")"
}

# Print abs path to the commit-memory trigger file. The agent creates this
# ordinary file to ask the PostToolBatch hook (memory-commit-batch.sh) to commit
# memory on its behalf — the agent never runs git, sidestepping the sandbox and
# the auto-mode classifier. Gitignored.
gitlore_commit_trigger_file() {
  printf '%s/gitlore-commit-memory\n' "$(_gitlore_ipc_dir "$1")"
}

# Print abs path to the add-tier intent file. The agent writes the mount/create
# intent here as `key=value` lines; the PostToolBatch hook (add-tier-batch.sh)
# runs the git on its behalf. Same trigger-file route as the commit path, and for
# a second reason on top of the classifier: mounting a tier CLONES, and the
# command sandbox has no network — only the hook, which runs outside it, can
# reach the remote. Gitignored.
gitlore_add_tier_file() {
  printf '%s/gitlore-add-tier\n' "$(_gitlore_ipc_dir "$1")"
}

# Print the path to the "already nudged this dirty episode" marker. Kept in the
# memory submodule's gitdir (like gitlore_merge_state_file), NOT the working
# tree, so it never appears in `git status` and needs no `.gitignore` entry. Set
# by the PostToolUse nudge (post-tool-use.sh, a hook that writes git internals
# freely — unlike the agent, which cannot) so the summarize-memory direction
# fires once per dirty episode; cleared by gitlore_sync_memory_to_live when
# memory is committed (the episode ends). Args: $1 = memory worktree path.
gitlore_commit_notified_file() {
  git -C "$1" rev-parse --git-path gitlore-nudged
}

# Print the CC project-scoped auto-memory dir for a repo root.
# CC encodes the project dir name by replacing every non-[A-Za-z0-9] byte with
# `-` (verified empirically against ~/.claude/projects/ entries). The >200-char
# truncate+hash fallback is out of scope — repo abs paths that long are
# vanishingly rare. Args: $1 = repo root abs path.
gitlore_cc_memory_dir() {
  local root="$1" encoded
  encoded=$(printf '%s' "$root" | LC_ALL=C sed 's/[^A-Za-z0-9]/-/g')
  printf '%s\n' "$HOME/.claude/projects/$encoded/memory"
}

# Exit 0 if $1 is a CC auto-memory dir whose MEMORY.md is our migration
# breadcrumb — i.e. there is no real memory to migrate, just a leftover stub
# from a prior install/run. 1 otherwise (no dir, no MEMORY.md, or real memory).
# Args: $1 = the auto-memory dir.
gitlore_is_migration_stub() {
  local dir="$1"
  # Guard on the file instead of suppressing grep's stderr: "no such file" is the
  # expected miss, and guarding it away means a real read error still speaks up.
  [ -f "$dir/MEMORY.md" ] || return 1
  grep -qF "$GITLORE_MIGRATION_MARKER" "$dir/MEMORY.md"
}

# Replace a CC auto-memory dir with a stub MEMORY.md recording that gitlore
# migrated memory in-tree. Idempotent: if the dir already holds only our stub,
# leave it untouched. Args: $1 = the auto-memory dir.
gitlore_mark_migrated() {
  local dir="$1" stub="$1/MEMORY.md"
  if gitlore_is_migration_stub "$dir"; then
    return 0
  fi
  rm -rf "$dir"
  mkdir -p "$dir"
  cat > "$stub" <<'EOF'
# Memory migrated in-tree

This project's auto-memory was migrated in-tree by `/gitlore:install`. It now
lives in the `gitlore-memory` submodule, versioned in git alongside the code.

Do not add memory here. Launch Claude Code through the gitlore `claude` shim so
memory is redirected into the submodule. New files appearing in this directory
mean a session was started without the launcher — see the gitlore SessionStart
warning for how to activate it.
EOF
}

# Print abs path to the memory submodule's merge-state file.
# Resolves through the submodule's gitdir correctly.
# Args: $1 = memory path (working tree).
gitlore_merge_state_file() {
  local mempath="$1"
  git -C "$mempath" rev-parse --git-path gitlore-merge-state
}

# Print abs path to one of the merge's read-only briefing artifacts — the two
# side diffs and the store's file tree, written at prepare time for the merger
# sub-agent. They live beside the state file in the gitdir, so they are invisible
# to `git status` and need no `.gitignore` entry, and they are named in the state
# file rather than reconstructed: the sub-agent runs no git of its own beyond
# `add`. Args: $1 = memory path, $2 = artifact suffix (mine.diff, theirs.diff, tree).
gitlore_merge_artifact_file() {
  git -C "$1" rev-parse --git-path "gitlore-merge-$2"
}

# Remove the merge state file and every artifact that was written with it.
# One remover, so a continuation cannot drop the state and leave the briefing
# behind for the next merge to be read against. Args: $1 = memory path.
gitlore_clear_merge_state() {
  local mempath="$1" name
  rm -f "$(gitlore_merge_state_file "$mempath")"
  for name in mine.diff theirs.diff tree; do
    rm -f "$(gitlore_merge_artifact_file "$mempath" "$name")"
  done
}

# Echo '0' (clean) or '1' (dirty). Convention is string output, NOT exit status —
# callers should compare with `[ "$(gitlore_memory_dirty PATH)" = "1" ]`.
gitlore_memory_dirty() {
  local mempath="$1"
  if [ -z "$(git -C "$mempath" status --porcelain)" ]; then
    printf '0\n'
  else
    printf '1\n'
  fi
}

# Print a file's mtime as an epoch second, portably (GNU `stat -c` vs BSD/macOS
# `stat -f`). The flavor is probed ONCE, against a path that always exists, and
# memoized — rather than running the GNU form per file and discarding its stderr,
# which on BSD suppresses an expected error every call and on GNU silently
# swallows a real one (missing file, permission denied). After the probe, no stat
# error is hidden. The probe itself redirects because provoking the failure is
# how it detects the flavor. Args: $1 = file.
_gitlore_mtime() {
  if [ -z "${_GITLORE_STAT_FLAVOR:-}" ]; then
    if stat -c '%Y' . >/dev/null 2>&1; then
      _GITLORE_STAT_FLAVOR=gnu
    else
      _GITLORE_STAT_FLAVOR=bsd
    fi
  fi
  case "$_GITLORE_STAT_FLAVOR" in
    gnu) stat -c '%Y' "$1" ;;
    *)   stat -f '%m' "$1" ;;
  esac
}

# Echo "yes" if commit-msg file is fresh (mtime >= newest tracked memory file),
# else "no" or "absent".
gitlore_commit_msg_freshness() {
  local mempath="$1"
  local msgfile
  msgfile=$(gitlore_commit_msg_file "$mempath") || return 1
  [ -f "$msgfile" ] || { printf 'absent\n'; return 0; }
  local newest=0 f m
  while IFS= LC_ALL=C read -r -d '' f; do
    m=$(_gitlore_mtime "$f")
    [ "$m" -gt "$newest" ] && newest="$m"
  done < <(find "$mempath" -type f -not -path '*/.git/*' -print0)
  local msgmtime
  msgmtime=$(_gitlore_mtime "$msgfile")
  awk -v a="$msgmtime" -v b="${newest:-0}" \
      'BEGIN { print (a+0 >= b+0) ? "yes" : "no" }'
}

# Exit 0 if $1 is a writable directory, 1 otherwise. Used to detect a sandboxed
# install before it dies mid-mutation with a raw "Permission denied".
# Args: $1 = directory to test.
gitlore_probe_writable() {
  local dir="$1" probe="$1/.gitlore-write-probe.$$"
  # Redirect kept deliberately: provoking "Permission denied" IS the probe, so
  # the message is both expected and the answer. Surfacing it would be the noise.
  if ( : > "$probe" ) 2>/dev/null; then
    rm -f "$probe"
    return 0
  fi
  return 1
}

# Exit 0 if a git stderr blob signals lock contention worth retrying, 1 if not.
# Lowercases the haystack so casing in git's messages doesn't matter. See D13.
# Args: $1 = the captured stderr text.
gitlore_git_is_lock_error() {
  local err
  err=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$err" in
    *index.lock*)               return 0 ;;
    *"file exists"*)            return 0 ;;
    *"unable to create"*.lock*) return 0 ;;
    *"cannot lock ref"*)        return 0 ;;
    *"another git process"*)    return 0 ;;
  esac
  return 1
}

# Run `git "$@"`, retrying on transient lock contention with exponential
# backoff. The default schedule's waits sum to exactly 10.0s wall-clock — the
# last term (3.7) is the budget remainder, not a doubled value — and is
# overridable via GITLORE_GIT_RETRY_SCHEDULE (tests set it to zeros). Only
# lock-contention failures retry (gitlore_git_is_lock_error); every other
# failure fails fast. The final attempt's stderr and exit code are surfaced
# unchanged. Stdout passes through untouched. Apply to mutating git calls only
# (read-only ops never take the index/ref lock). See D13.
gitlore_git() {
  local -a schedule
  read -r -a schedule <<< "${GITLORE_GIT_RETRY_SCHEDULE:-0.1 0.2 0.4 0.8 1.6 3.2 3.7}"
  local errfile rc i=0
  errfile=$(mktemp "${TMPDIR:-/tmp}/gitlore-git.XXXXXX")
  while :; do
    rc=0
    git "$@" 2>"$errfile" || rc=$?               # `|| rc=$?` keeps set -e happy
    [ "$rc" -eq 0 ] && break
    gitlore_git_is_lock_error "$(cat "$errfile")" || break
    [ "$i" -lt "${#schedule[@]}" ] || break          # retries exhausted
    sleep "${schedule[$i]}"
    i=$((i + 1))
  done
  cat "$errfile" >&2
  rm -f "$errfile"
  return "$rc"
}

# Print each tier submodule's path (relative to the memory worktree), one per
# line, read from the memory store's OWN .gitmodules. Discovery is by enclosure:
# every submodule registered inside the memory store is a tier — there is no
# tier-name constant (D17). No output (exit 0) when there is no nested .gitmodules.
# Args: $1 = memory worktree path.
# Whitespace safety: `-z` emits one NUL-terminated "key\nvalue" record per match,
# so a submodule name or path containing spaces survives intact. (A field split on
# the plain output loses both: for `[submodule "a b"]` it yields `b.path`, part of
# the KEY.) Paths containing a newline are out of scope by construction — the
# activation manifest is line-oriented, so such a tier could never be listed.
# No stderr redirect: --get-regexp is silent on no-match (rc=1, verified), so any
# message here is a real failure worth seeing.
gitlore_tier_paths() {
  local mempath="$1" rec
  [ -f "$mempath/.gitmodules" ] || return 0
  # LC_ALL=C: matches gitlore_commit_msg_freshness's own NUL-delimited `read`,
  # against the bash 5.0-5.3 multibyte `read -d ''` overshoot (BP#65).
  while IFS= LC_ALL=C read -r -d '' rec; do
    printf '%s\n' "${rec#*$'\n'}"
  done < <(git config --file "$mempath/.gitmodules" -z --get-regexp '^submodule\..*\.path$')
  return 0
}

# Print the tier paths listed in the activation manifest <mempath>/.gitlore-tiers,
# in file order, one per line, whitespace-trimmed, skipping blank lines. The
# manifest is the deliberate activation + precedence surface (listed = active,
# order = precedence); a mounted but unlisted tier is dormant. No output (exit 0)
# when the manifest is absent. (D17)
# Args: $1 = memory worktree path.
gitlore_active_tiers() {
  local manifest="$1/.gitlore-tiers" line
  [ -f "$manifest" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line#"${line%%[![:space:]]*}"}"     # trim leading whitespace
    line="${line%"${line##*[![:space:]]}"}"     # trim trailing whitespace
    [ -n "$line" ] && printf '%s\n' "$line"
  done < "$manifest"
  return 0
}

# Print "<tierpath>/ — <description>" (or bare "<tierpath>/" when the tier has
# no MEMORY.md yet or no description) for every ACTIVE tier, in manifest order.
# A tier listed in the manifest but not actually mounted (`.git` missing) is
# skipped rather than reported, matching SessionStart's own guard — a stale
# manifest entry is a dangling-pointer concern, not this helper's job.
# Shared by SessionStart's routing-guidance banner and the post-mount triage
# nudge (D17 triage-automation design), so "active tiers and their scopes" has
# one definition. Depends on gitlore_get_frontmatter_description
# (scripts/lib/index-sync.sh) — callers must source that file too.
# Args: $1 = memory worktree path.
gitlore_active_tier_scopes() {
  local mempath="$1" tier tierpath desc
  while IFS= read -r tier; do
    [ -n "$tier" ] || continue
    tierpath="$mempath/$tier"
    [ -e "$tierpath/.git" ] || continue
    desc=""
    if [ -f "$tierpath/MEMORY.md" ]; then
      desc=$(gitlore_get_frontmatter_description "$tierpath/MEMORY.md") || desc=""
    fi
    if [ -n "$desc" ]; then
      printf '%s/ — %s\n' "$tierpath" "$desc"
    else
      printf '%s/\n' "$tierpath"
    fi
  done < <(gitlore_active_tiers "$mempath")
  return 0
}

# Print the memory remote's bare name: <parent-remote-base>-memory.
# Derives the base from the parent repo's origin URL when set, handling both
# https (.../owner/repo[.git]) and scp-style (git@host:owner/repo[.git]) forms,
# with or without a trailing .git. Falls back to the repo directory basename when
# there is no origin (so the name is stable regardless of the local dir name when
# a remote exists — fixing the clone-dir-rename drift).
gitlore_memory_remote_name() {
  local url base
  url=$(git config --get remote.origin.url || true)
  if [ -n "$url" ]; then
    base=${url##*/}                       # https or scp-with-slash → repo[.git]
    case "$base" in *:*) base=${base##*:};; esac  # scp without a slash
    base=${base%.git}
  else
    base=$(basename "$(git rev-parse --show-toplevel)")
  fi
  printf '%s-memory\n' "$base"
}

# Print the canonical memory-approval clause: the self-contained block every
# call site that asks the user to approve a pending memory commit appends at the
# END of its own message. It carries a literal template, so it is multi-line and
# cannot be spliced into the middle of a sentence — a call site emitting JSON
# must therefore build it with jq, never a hand-written string. One file so the
# three call sites (post-tool-use.sh, memory-commit-batch.sh, resolve.sh) cannot
# drift on what "approve" means — see docs/design.md D19.
gitlore_memory_approval_clause() {
  cat "$PLUGIN_ROOT/reference/memory-approval-clause.txt"
}

# Print the visibility to use for the memory remote: "public" or "private".
# Matches the parent repo (design: public parent → public memory). Defaults to
# "private" when there is no parent origin or gh cannot report it — the safe
# default for memory, which may contain session context.
gitlore_parent_visibility() {
  local purl v
  purl=$(git config --get remote.origin.url || true)
  if [ -n "$purl" ] && command -v gh >/dev/null 2>&1; then
    # Redirect kept: this is a best-effort lookup whose failure modes are all
    # normal and expected (no gh auth, non-GitHub remote, network down, repo not
    # visible to this token) and each already has its answer — "private", the
    # safe default. Surfacing gh's error would put a scary, actionable-looking
    # message in front of a user for whom nothing is wrong.
    v=$(gh repo view "$purl" --json visibility -q .visibility 2>/dev/null \
          | tr '[:upper:]' '[:lower:]' || true)
    [ "$v" = "public" ] && { printf 'public\n'; return 0; }
  fi
  printf 'private\n'
}
