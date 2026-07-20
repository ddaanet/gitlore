#!/usr/bin/env bash
# Shared shell utilities. Source; do not exec.

# The canonical submodule name regardless of working-tree path.
GITLORE_SUBMODULE_NAME="gitlore-memory"
readonly GITLORE_SUBMODULE_NAME

# Marker phrase in the in-tree migration breadcrumb. Single source of truth,
# matched as a fixed string by gitlore_is_migration_stub and written into the
# stub body by gitlore_mark_migrated.
# shellcheck disable=SC2016  # literal marker text; the backticks are not a command sub
GITLORE_MIGRATION_MARKER='migrated in-tree by `/gitlore:install`'
readonly GITLORE_MIGRATION_MARKER

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
HOOKS_DIR=\$(git config gitlore.hooksDir 2>/dev/null)
if [ -z "\$HOOKS_DIR" ]; then
  echo "gitlore skipped: hooks not installed." >&2
  echo "Install the gitlore plugin from the Claude Code marketplace, then start Claude Code in this repo." >&2
  exit 0
fi
if [ ! -x "\$HOOKS_DIR/$hook" ]; then
  echo "gitlore skipped: hooks dir is stale (plugin upgraded; cache GC'd)." >&2
  echo "Start Claude Code in this repo to refresh the hooks dir, then retry." >&2
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
  path=$(git config --file .gitmodules \
    "submodule.${GITLORE_SUBMODULE_NAME}.path" 2>/dev/null) || return 1
  [ -n "$path" ] || return 1
  printf '%s\n' "$path"
}

# Exit 0 if .gitmodules registers the gitlore-memory submodule, 1 otherwise.
gitlore_has_submodule() {
  gitlore_memory_path >/dev/null 2>&1
}

# Print the parent worktree's branch name, or "DETACHED" if not on a branch.
# Exit 1 outside a git repo.
gitlore_parent_branch() {
  local b
  b=$(git symbolic-ref --short -q HEAD 2>/dev/null) || {
    git rev-parse --verify HEAD >/dev/null 2>&1 || return 1
    printf 'DETACHED\n'
    return 0
  }
  printf '%s\n' "$b"
}

# Print abs path to the `.claude/` dir in the PARENT working tree that hosts the
# memory IPC files (message, commit trigger, notified marker). Resolves the
# superproject working tree; falls back to the memory worktree's parent dir when
# memory is not a registered submodule (or is detached). Relocated 2026-07-16
# from the submodule gitdir so the agent can write these under auto mode — the
# gitdir is unwritable via every agent tool (Write and a bash heredoc are both
# classifier/sandbox denied). Args: $1 = memory worktree path (relative or absolute).
_gitlore_ipc_dir() {
  local mempath="$1" super
  super=$(git -C "$mempath" rev-parse --show-superproject-working-tree 2>/dev/null) || super=""
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
  grep -qF "$GITLORE_MIGRATION_MARKER" "$dir/MEMORY.md" 2>/dev/null
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

# Echo "yes" if commit-msg file is fresh (mtime >= newest tracked memory file),
# else "no" or "absent".
gitlore_commit_msg_freshness() {
  local mempath="$1"
  local msgfile
  msgfile=$(gitlore_commit_msg_file "$mempath") || return 1
  [ -f "$msgfile" ] || { printf 'absent\n'; return 0; }
  local newest=0 f m
  while IFS= LC_ALL=C read -r -d '' f; do
    m=$(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f")
    [ "$m" -gt "$newest" ] && newest="$m"
  done < <(find "$mempath" -type f -not -path '*/.git/*' -print0)
  local msgmtime
  msgmtime=$(stat -c '%Y' "$msgfile" 2>/dev/null || stat -f '%m' "$msgfile")
  awk -v a="$msgmtime" -v b="${newest:-0}" \
      'BEGIN { print (a+0 >= b+0) ? "yes" : "no" }'
}

# Exit 0 if $1 is a writable directory, 1 otherwise. Used to detect a sandboxed
# install before it dies mid-mutation with a raw "Permission denied".
# Args: $1 = directory to test.
gitlore_probe_writable() {
  local dir="$1" probe="$1/.gitlore-write-probe.$$"
  if ( : > "$probe" ) 2>/dev/null; then
    rm -f "$probe"
    return 0
  fi
  return 1
}

# Exit 0 if a git stderr blob signals lock contention worth retrying, 1 if not.
# Lowercases the haystack so casing in git's messages doesn't matter. Resolve's
# one-checkout-per-branch error ("'live' is already used by worktree at …", D3)
# is explicitly NOT a retryable lock — it must fail fast. See D13.
# Args: $1 = the captured stderr text.
gitlore_git_is_lock_error() {
  local err
  err=$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')
  case "$err" in
    *"is already used by worktree at"*) return 1 ;;   # D3 fast-fail, not a lock
  esac
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
  while IFS= read -r -d '' rec; do
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

# Print the memory remote's bare name: <parent-remote-base>-memory.
# Derives the base from the parent repo's origin URL when set, handling both
# https (.../owner/repo[.git]) and scp-style (git@host:owner/repo[.git]) forms,
# with or without a trailing .git. Falls back to the repo directory basename when
# there is no origin (so the name is stable regardless of the local dir name when
# a remote exists — fixing the clone-dir-rename drift).
gitlore_memory_remote_name() {
  local url base
  url=$(git config --get remote.origin.url 2>/dev/null || true)
  if [ -n "$url" ]; then
    base=${url##*/}                       # https or scp-with-slash → repo[.git]
    case "$base" in *:*) base=${base##*:};; esac  # scp without a slash
    base=${base%.git}
  else
    base=$(basename "$(git rev-parse --show-toplevel)")
  fi
  printf '%s-memory\n' "$base"
}

# Print the visibility to use for the memory remote: "public" or "private".
# Matches the parent repo (design: public parent → public memory). Defaults to
# "private" when there is no parent origin or gh cannot report it — the safe
# default for memory, which may contain session context.
gitlore_parent_visibility() {
  local purl v
  purl=$(git config --get remote.origin.url 2>/dev/null || true)
  if [ -n "$purl" ] && command -v gh >/dev/null 2>&1; then
    v=$(gh repo view "$purl" --json visibility -q .visibility 2>/dev/null \
          | tr '[:upper:]' '[:lower:]' || true)
    [ "$v" = "public" ] && { printf 'public\n'; return 0; }
  fi
  printf 'private\n'
}
