#!/usr/bin/env bash
# One-way index→frontmatter sync helpers (D17). Sourced by the Pre/Post hooks
# and unit-tested directly. No side effects except the one write in the setter.

# Print "path<TAB>hook" for every root-index bullet of the form
#   - [title](path) — hook
# Lines lacking the ") — " separator are skipped. All width arithmetic uses
# length() so byte-vs-char counting stays self-consistent across awk flavors.
gitlore_index_pairs() {
  awk '
    /^- \[/ {
      sep = ") — "
      d = index($0, sep)
      if (d == 0) next
      left = substr($0, 1, d)              # "...(path)"
      hook = substr($0, d + length(sep))   # everything after the first ") — "
      lp = index(left, "](")
      if (lp == 0) next
      rest = substr(left, lp + 2)          # "path)"
      rp = index(rest, ")")
      if (rp == 0) next
      path = substr(rest, 1, rp - 1)
      print path "\t" hook                 # awk "\t" is a real tab, portably
    }
  ' "$1"
}

# Print the effective value of the first `description:` line in a file's
# leading frontmatter block; return 1 if there is none. A double-quoted scalar
# is unquoted, mirroring the setter's JSON quoting, so a value that round-trips
# through the setter compares equal to the hook it came from — otherwise every
# already-synced file would look like a fresh replacement.
gitlore_get_frontmatter_description() {
  local raw
  raw=$(awk '
    BEGIN { dashes = 0 }
    /^---[[:space:]]*$/ { dashes++; if (dashes == 2) exit; next }
    (dashes == 1 && /^description:/) {
      sub(/^description:[[:space:]]*/, ""); print; exit
    }
  ' "$1") || return 1
  [ -n "$raw" ] || return 1
  case "$raw" in
    # jq parses the setter's own output; a value that only looks quoted (stray
    # inner quotes, say) falls back to verbatim rather than vanishing.
    '"'*'"') jq -r . <<<"$raw" 2>/dev/null || printf '%s\n' "$raw" ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

# Rewrite the first `description:` line inside a file's leading frontmatter
# block to a JSON-quoted (=> YAML-safe) scalar of $2. In place.
gitlore_set_frontmatter_description() {
  local file="$1" newdesc="$2" quoted repl tmp status
  quoted=$(jq -Rn --arg d "$newdesc" '$d')   # e.g. "has \"quote\": ..."
  repl="description: $quoted"
  # Inside the store's own gitdir, not beside the target — matches
  # gitlore_weld_repair's (edit-weld.sh) own scratch-file placement. The `else`
  # below already removes $tmp on a caught failure, but that cannot run at all
  # if the process is killed mid-write; placing it outside the tracked
  # worktree bounds that window to "leftover in the gitdir", never "untracked
  # neighbour the FR11 gate's `git add -A` sweeps up". `--absolute-git-dir`,
  # not `--git-path`: the latter is relative to the `-C` dir for a plain repo.
  tmp=$(git -C "$(dirname -- "$file")" rev-parse --absolute-git-dir) \
    && tmp="$tmp/gitlore-frontmatter.tmp.$$" || return 1
  # Pass repl via ENVIRON so awk does no escape processing on it. Both the
  # awk call and the mv are the condition of this `if`, so either one
  # failing (awk itself, the redirect that creates $tmp, or the mv) is
  # caught here instead of tripping errexit; on failure the (possibly
  # empty or partially-written) $tmp is removed. The original failing
  # command's status is preserved and returned so callers' `if !` guard
  # still fires.
  if GITLORE_REPL="$repl" awk '
    BEGIN { dashes = 0; done = 0 }
    /^---[[:space:]]*$/ { dashes++; print; next }
    (dashes == 1 && !done && /^description:/) {
      print ENVIRON["GITLORE_REPL"]; done = 1; next
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"; then
    return 0
  else
    # $? after a bare `if cond; then ...; fi` with no branch taken is 0, not
    # the condition's status (POSIX) — capture it here, in the else branch,
    # while it is still live.
    status=$?
    rm -f "$tmp"
    return "$status"
  fi
}

# Abs/relative path of the pre-edit MEMORY.md stash, inside the submodule
# gitdir (untracked; mirrors gitlore_commit_msg_file). $1 = memory path;
# $2 = agent id, optional. Absent or empty yields today's unsuffixed name, so
# the main thread's files do not migrate; non-empty appends `-<agent_id>` —
# see _gitlore_agent_suffix for the exact suffix and why it is sanitized.
gitlore_index_preimage_file() {
  git -C "$1" rev-parse --git-path "gitlore-index-preimage$(_gitlore_agent_suffix "${2:-}")"
}

# Abs/relative path of the compose hook's own pre-batch stamp. A second,
# independently-owned file rather than a field in the sync's stash: each
# PostToolBatch hook consumes and deletes its own baseline, so neither depends
# on running before or after the other. $1 = memory path; $2 = agent id,
# optional — same absent/empty-vs-non-empty contract as
# gitlore_index_preimage_file.
gitlore_compose_stamp_file() {
  git -C "$1" rev-parse --git-path "gitlore-compose-stamp$(_gitlore_agent_suffix "${2:-}")"
}

# Write a subagent's report toward the relay (D51). $1 = memory path;
# $2 = session id, "nosession" when empty; $3 = agent id, required; $4 = tag,
# `sync` or `compose`; $5 = systemMessage body; $6 = additionalContext body.
# Every failure path returns non-zero itself rather than leaning on errexit:
# both call sites are `if ! gitlore_relay_write …`, a condition context where
# errexit is off, and that non-zero is what routes into their own "could not
# be staged" line instead of the report being lost silently.
#
# Write-once, never merged: builds a fresh file, never reads or folds an
# existing one. Name is `gitlore-relay-<S>-<A>-<epoch>-<pid>-<H>` in the
# memory gitdir — S the sanitized session id, A the sanitized agent id
# (_gitlore_sanitize_id, shared with _gitlore_agent_suffix), epoch
# `date +%s`, pid `${BASHPID:-$$}`, H the tag. Built at `<name>.tmp` and
# installed by `mv`; refused (temp removed, return 1) when the destination
# already exists — POSIX `mv` moves a source INTO an existing directory
# destination with exit 0, so this existence check, not the `mv` itself, is
# what stops that squat. A temp that cannot be opened at all leaves nothing
# behind to clean up, so its return is bare.
#
# File format: the literal line `--- gitlore-relay-sysmsg ---`, the
# systemMessage body, the literal line `--- gitlore-relay-ctx ---`, the
# additionalContext body. Neither body is escaped: the contract is that
# neither holds a line equal to a delimiter. A body that broke that would not
# corrupt the file, but the drain would re-split there and attribute the tail
# to the wrong channel — silently, so the guarantee is the whole protection.
#
# The tag is checked against its two values rather than sanitized, because it
# is a parse anchor as well as a filename component: the drain recovers A as
# `${rest%-*-*-*}`, which holds only while the last three fields are
# dash-free. A closed set is the cheaper guarantee — no `tr` subprocess — and
# it also bounds the component's length, where a sanitizer would map an
# oversized or dashed argument to a name the filesystem or the drain rejects
# further downstream. A caller passing anything else is refused through the
# same path as any other failed write.
#
# Residual: two writes agreeing on session, agent, tag AND wall-clock second
# from ONE PROCESS collide on one name and the second is refused — `<pid>`
# only discriminates across processes. No caller writes twice from one
# process within a second: the two reporting hooks are separate processes
# carrying different tags. Stated as a bound, not fixed.
#
# `${N:-}` on every position past $1: an absent session is the same case as
# an empty one, both bodies are legitimately empty on their own (the sync
# hook's `failed` branch reports a sysmsg and no ctx), and an absent agent or
# tag is refused by the guards below — which report through the caller's
# channel, where `set -u` would instead abort the whole hook.
gitlore_relay_write() {
  local mempath="$1" session="${2:-}" agent="${3:-}" tag="${4:-}" sysmsg="${5:-}" ctx="${6:-}"
  local s a epoch pid marker
  [ -n "$agent" ] || return 1
  case "$tag" in sync|compose) ;; *) return 1 ;; esac
  if [ -n "$session" ]; then s=$(_gitlore_sanitize_id "$session"); else s=nosession; fi
  a=$(_gitlore_sanitize_id "$agent")
  epoch=$(date +%s) || return 1
  # `pid` read as a bare assignment, not expanded inside the `$(...)` below:
  # a command substitution forks, so `${BASHPID:-$$}` in the `git rev-parse`
  # argument would give the FORKED subshell's own PID — a fresh value on
  # every call, from one process or twenty alike — rather than the calling
  # process's, which is what discriminates one hook's writes from another's.
  pid=${BASHPID:-$$}
  marker=$(git -C "$mempath" rev-parse --git-path "gitlore-relay-$s-$a-$epoch-$pid-$tag") || return 1
  {
    printf -- '--- gitlore-relay-sysmsg ---\n'
    printf '%s\n' "$sysmsg"
    printf -- '--- gitlore-relay-ctx ---\n'
    printf '%s\n' "$ctx"
  } > "$marker.tmp" || return 1
  if [ -e "$marker" ]; then
    rm -f "$marker.tmp"
    return 1
  fi
  mv "$marker.tmp" "$marker"
}

# Fold every relay file for one session into GITLORE_RELAY_SYSMSG and
# GITLORE_RELAY_CTX — each block framed `--- gitlore-relay agent <A> ---` on
# both channels, in filename order (write order, since the name carries the
# writer's epoch) — then remove exactly the files read. $1 = memory path;
# $2 = session id, mapped to "nosession" when empty, the same mapping the
# write side uses. Both variables are set to the empty string when nothing is
# found. Always returns 0.
#
# `'!' -name '*.tmp'` excludes a writer's in-progress temp: a writer killed
# between opening `<name>.tmp` and its `mv` leaves that temp standing beside
# real markers, and without this exclusion it would be folded in as a report
# of its own. A temp stranded that way is never picked up here — only
# gitlore_relay_sweep collects it, by age.
#
# `${2:-}`: an absent session is the same case as an empty one, mapped to
# `nosession` the way the write side maps it, so the two meet.
gitlore_relay_drain() {
  local mempath="$1" session="${2:-}"
  local gitdir s prefix names name marker rest agent sysblock ctxblock
  GITLORE_RELAY_SYSMSG=""
  GITLORE_RELAY_CTX=""
  gitdir=$(git -C "$mempath" rev-parse --absolute-git-dir) || return 0
  if [ -n "$session" ]; then s=$(_gitlore_sanitize_id "$session"); else s=nosession; fi
  prefix="gitlore-relay-$s-"
  # `-print0` into `read -r -d ''`, never an `ls` pipeline or an unquoted
  # glob: nothing sanitizes the gitdir prefix and it may hold a space.
  # `-type f` because anything else on a relay name is not a report: framing
  # it would attribute a block to an agent that staged nothing, and `rm -f`
  # cannot remove a directory, so every later run would frame it again.
  names=""
  while IFS= read -r -d '' marker; do
    names="$names${marker##*/}"$'\n'
  done < <(find "$gitdir" -maxdepth 1 -type f -name "$prefix*" '!' -name '*.tmp' -print0)
  [ -n "$names" ] || return 0
  # Sorted, because find's own directory order is not guaranteed. Basenames
  # rather than whole paths: a name this library writes is `$prefix` followed
  # by `[A-Za-z0-9_-]` only — the sanitizer's class, a decimal epoch and pid,
  # and a tag from a closed set — so a newline-joined list is unambiguous
  # where one carrying the unsanitized gitdir prefix would not be, and that
  # prefix, identical across names, sorts nothing anyway. The bound: a file
  # some other writer put on a matching name holding a newline splits into
  # two names here, framing two empty blocks and removing neither.
  # `LC_ALL=C` for byte order: other collations ignore `-` at the first
  # level, which reorders two ids differing only there. (`sort -z` would
  # sidestep the join, but BSD sort has no `-z`.)
  while IFS= read -r name; do
    marker="$gitdir/$name"
    # A recovered by stripping the known prefix as a literal and then the
    # three trailing `-<epoch>-<pid>-<H>` fields. Unambiguous even when S or
    # A holds a dash — S is removed by length, not by pattern, and epoch, pid
    # and H are dash-free by construction: two decimals and the tag
    # gitlore_relay_write only accepts from a closed set.
    rest=${name#"$prefix"}
    agent=${rest%-*-*-*}
    sysblock=$(_gitlore_relay_sysblock "$marker") || sysblock=""
    ctxblock=$(_gitlore_relay_ctxblock "$marker") || ctxblock=""
    GITLORE_RELAY_SYSMSG="${GITLORE_RELAY_SYSMSG}--- gitlore-relay agent $agent ---
$sysblock
"
    GITLORE_RELAY_CTX="${GITLORE_RELAY_CTX}--- gitlore-relay agent $agent ---
$ctxblock
"
    # `|| true`: this is the gitdir's own writability, not the marker's mode
    # — a marker read fine here still costs its caller everything if the
    # directory refuses the remove, and nothing a caller reports may die
    # behind this call.
    rm -f "$marker" || true
  done < <(printf '%s' "$names" | LC_ALL=C sort)
  return 0
}

# Remove relay files older than 7 days (D51's SessionStart sweep), temps
# included — the same `-mtime +7 -delete` shape as _gitlore_nudge_reset. The
# `.tmp` exclusion above is a drain rule (a temp must never be folded as a
# report), not a sweep rule: this age sweep is the only way a temp stranded
# by a killed writer is ever collected. $1 = memory path. Always returns 0 —
# on a missing gitdir, and on a gitdir whose mode refuses the unlink.
gitlore_relay_sweep() {
  local mempath="$1" gitdir
  gitdir=$(git -C "$mempath" rev-parse --absolute-git-dir) || return 0
  [ -d "$gitdir" ] || return 0
  # `|| true`: `-delete` exits non-zero when the gitdir refuses the unlink.
  # Best-effort garbage collection must not abort a caller running under
  # errexit — the same degrade-don't-abort trade gitlore_relay_drain's
  # `rm -f` makes on the same directory.
  find "$gitdir" -maxdepth 1 -type f -name 'gitlore-relay-*' -mtime +7 -delete || true
  return 0
}

# Print one channel of a marker: everything between that channel's delimiter
# line and the next one, or EOF. $1 = a marker path. Only gitlore_relay_drain
# calls the pair, guarded by its own `find -type f`; that screens shape, not
# permissions, so a marker whose mode has been mangled still reaches here and
# awk exits non-zero on the open. Both its call sites degrade to an empty
# block with `|| …=""` rather than propagate: under a caller's errexit the
# alternative is aborting the hook before it emits any JSON, losing that
# run's own report to save nothing.
_gitlore_relay_sysblock() {
  awk '/^--- gitlore-relay-sysmsg ---$/ { f=1; next } /^--- gitlore-relay-ctx ---$/ { f=0 } f' "$1"
}

_gitlore_relay_ctxblock() {
  awk '/^--- gitlore-relay-ctx ---$/ { f=1; next } f' "$1"
}

# Sanitize an id — an agent id or a session id — for use as a filename
# component: every byte outside `[A-Za-z0-9-]` collapses to `_`, folding an
# embedded newline too so the result stays a single line. The id is a raw
# hook-payload field spliced into a `rev-parse --git-path` argument (which
# does no normalising of its own) or directly into a relay filename, so a `/`
# or a `..` component would otherwise walk the result out of the gitdir, to
# somewhere the consumers `cp` onto and `rm -f`. `tr -c` rather than
# `_gitlore_nudge_file`'s line-oriented `sed`, so a newline is folded too.
# Not a live exploit today — Claude Code mints both ids and uses the agent
# one as a filename itself (`agent-<id>.jsonl`) — but a hook must not write
# outside the gitdir because an upstream id format changed, and it would fail
# silently if it did.
#
# The mapping is not injective, so two ids differing only outside that class
# collide. Real agent and session ids are `[A-Za-z0-9-]` and pass through
# byte for byte, so the collision is reachable only from an id shape that
# does not occur.
_gitlore_sanitize_id() {
  printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9-' '_'
}

# The `-<agent id>` suffix gitlore_index_preimage_file and
# gitlore_compose_stamp_file append; empty for an empty or absent id, which
# is what keeps the main thread on today's names.
_gitlore_agent_suffix() {
  [ -n "${1:-}" ] || return 0
  printf -- '-%s' "$(_gitlore_sanitize_id "$1")"
}

# Print the compose trigger's stamp: one `key<TAB>checksum` line per watched
# file, with a literal `absent` for one that is not there — so a file appearing
# or vanishing registers as a change like any other. Cheap by design: it runs
# ahead of every Bash call, where keeping whole copies would not be.
# Args: $1 = root index path, $2 = tier manifest path.
gitlore_compose_stamp() {
  printf 'index\t%s\n' "$(_gitlore_file_stamp "$1")"
  printf 'manifest\t%s\n' "$(_gitlore_file_stamp "$2")"
}

_gitlore_file_stamp() {
  if [ -f "$1" ]; then cksum < "$1"; else printf 'absent'; fi
}

# Print the checksum a stamp records for key $1. Reads the stamp on stdin, so
# the same reader serves the file on disk and the one just computed.
gitlore_compose_stamp_get() {
  awk -F'\t' -v k="$1" '$1==k { sub(/^[^\t]*\t/, ""); print; exit }'
}

# --- routing-key advisories --------------------------------------------------
# The index one-liner is what CC's recall classifier matches against, and the
# sync above then overwrites the file's own `description:` with it — so a hook
# that carries no trigger degrades BOTH match surfaces at once, silently. The
# two checks below give that silence a voice. Neither can decide whether a hook
# is GOOD; each measures one thing that is countable.

# Advisory byte budget of the always-loaded index blob (25 KiB) and the fraction
# at which to speak up. Both overridable so a test drives the threshold instead
# of writing a 20KB fixture. This budget only reports; Claude Code's own loader
# is the hard cap, and it truncates lower — see commands/index-audit.md.
: "${GITLORE_INDEX_BUDGET_BYTES:=25600}"
: "${GITLORE_INDEX_BUDGET_WARN_PCT:=80}"

# Percent of that budget the index occupies, floored. BYTES, not lines: the
# blob is loaded verbatim, so a handful of paragraph-length lines costs more
# than fifty terse ones.
gitlore_index_budget_pct() {
  local bytes
  bytes=$(wc -c < "$1") || return 1
  printf '%s\n' "$(( bytes * 100 / GITLORE_INDEX_BUDGET_BYTES ))"
}

# Once-per-episode markers. A nudge that fires on every batch is noise, so each
# advisory drops a marker keyed by session in the memory gitdir — hook-owned
# state the agent must never write — and checks for it before speaking.
# Args: $1 = memory worktree path; $2 = session id; $3 = marker kind.
_gitlore_nudge_file() {
  local safe
  safe=$(printf '%s' "${2:-nosession}" | LC_ALL=C sed 's/[^A-Za-z0-9-]/_/g')
  git -C "$1" rev-parse --git-path "gitlore-$3-nudged-$safe"
}

# Clear this session's marker of that kind, and sweep markers left by sessions
# that ended without one. Args as _gitlore_nudge_file.
_gitlore_nudge_reset() {
  local mempath="$1" kind="$3" marker dir
  marker=$(_gitlore_nudge_file "$mempath" "$2" "$kind")
  rm -f "$marker"
  dir=$(dirname -- "$marker")
  [ -d "$dir" ] || return 0
  find "$dir" -maxdepth 1 -name "gitlore-$kind-nudged-*" -type f -mtime +7 -delete
  return 0
}

# Has the index byte-budget advisory already fired this episode?
# Args: $1 = memory worktree path; $2 = session id.
gitlore_index_budget_nudge_file() { _gitlore_nudge_file "$1" "$2" budget; }

# Re-arm the byte-budget advisory. Called at SessionStart and PreCompact, the
# two events that end the context a marker's "already told" claim rests on.
gitlore_index_budget_nudge_reset() { _gitlore_nudge_reset "$1" "$2" budget; }

# Has the mid-session plugin-upgrade notice already fired this episode (D21)?
# Args: $1 = memory worktree path; $2 = session id.
gitlore_upgrade_nudge_file() { _gitlore_nudge_file "$1" "$2" upgrade; }

# Re-arm the upgrade notice. A compaction re-arms it deliberately: what survives
# is a summary, and the session is still running the old plugin root.
gitlore_upgrade_nudge_reset() { _gitlore_nudge_reset "$1" "$2" upgrade; }

# "bytes<TAB>path" for the $2 (default 5) largest bullets, descending — where
# curation actually pays. LC_ALL=C so awk's length() counts bytes rather than
# characters; the separator alone is a 3-byte em-dash, so the two differ.
#
# The last stage reads to EOF instead of `head -n`: callers run with `set -o
# pipefail`, and an early-exiting consumer leaves `sort` writing into a closed
# pipe — SIGPIPE, exit 141, and the advisory lost on exactly the large indexes
# it exists to report on.
gitlore_index_largest() {
  local file="$1" n="${2:-5}"
  LC_ALL=C awk '
    /^- \[/ {
      sep = ") — "
      d = index($0, sep); if (d == 0) next
      left = substr($0, 1, d)
      lp = index(left, "]("); if (lp == 0) next
      rest = substr(left, lp + 2)
      rp = index(rest, ")"); if (rp == 0) next
      print length($0) "\t" substr(rest, 1, rp - 1)
    }
  ' "$file" | sort -rn | awk -v n="$n" 'NR <= n'
}

# Return 0 when $1 carries at least one LITERAL token — the kind of thing a
# future query actually contains: a backticked span, a flag, a path, a dotfile,
# a filename, $VAR, a key=value, a version, snake_case, camelCase, an acronym.
#
# Word-at-a-time rather than one big ERE because ERE word boundaries are not
# portable (GNU \b vs BSD [[:<:]]); splitting on whitespace makes the boundary
# safe by construction, so `well-known` is prose while `--flag` is a flag.
gitlore_index_has_literal() {
  awk '
    {
      n = split($0, w, /[[:space:]]+/)
      for (i = 1; i <= n; i++) {
        t = w[i]
        gsub(/^[[("]+/, "", t); gsub(/[])".,;:?!]+$/, "", t)
        if (t == "") continue
        if (index(t, "`") > 0)   { hit = 1; break }   # `backticked span`
        if (index(t, "/") > 0)   { hit = 1; break }   # a/path or 2>/dev/null
        if (index(t, "=") > 0)   { hit = 1; break }   # key=value
        if (t ~ /^--?[A-Za-z]/)  { hit = 1; break }   # --flag, -C
        if (t ~ /^\.[A-Za-z]/)   { hit = 1; break }   # .gitmodules
        if (t ~ /^\$/)           { hit = 1; break }   # $VAR
        if (t ~ /^[0-9]+\.[0-9]/) { hit = 1; break }  # 2.47.3
        if (t ~ /\.(md|sh|json|py|bats|toml|ya?ml|lock|git|txt)$/) { hit = 1; break }
        if (t ~ /[A-Za-z0-9]_[A-Za-z0-9]/) { hit = 1; break }   # snake_case
        if (t ~ /[a-z][A-Z]/)    { hit = 1; break }   # camelCase
        if (t ~ /^[A-Z][A-Z0-9]+$/) { hit = 1; break }          # CC, FR11, API
      }
    }
    END { exit !hit }
  ' <<<"$1"
}

# Print the effective `type:` from a memory file's leading frontmatter — the
# indented `metadata:` form and the older top-level one both. Return 1 if
# absent. `node_type:` does not match: the pattern anchors `type:` to the start
# of the line modulo indentation.
gitlore_frontmatter_type() {
  local raw
  raw=$(awk '
    BEGIN { dashes = 0 }
    /^---[[:space:]]*$/ { dashes++; if (dashes == 2) exit; next }
    (dashes == 1 && /^[[:space:]]*type:[[:space:]]/) {
      sub(/^[[:space:]]*type:[[:space:]]*/, ""); print; exit
    }
  ' "$1") || return 1
  [ -n "$raw" ] || return 1
  printf '%s\n' "$raw"
}
