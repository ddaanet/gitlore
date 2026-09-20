#!/usr/bin/env bash
# The relay-marker group (D51): write, drain and sweep the one-file-per-report
# subagent relay, and the two block extractors the drain uses.
# Part of lib/index-sync.sh; source that, not this file.

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
  local s a epoch pid gitdir marker
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
  # `--absolute-git-dir`, the form the drain and the sweep read: `--git-path`
  # prints a path relative to the store for a store whose `.git` is a
  # directory, and the write would open it relative to the caller's cwd.
  gitdir=$(git -C "$mempath" rev-parse --absolute-git-dir) || return 1
  marker="$gitdir/gitlore-relay-$s-$a-$epoch-$pid-$tag"
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
