#!/usr/bin/env bash
# Tier discovery/listing (gitlore_tier_paths, gitlore_active_tiers,
# gitlore_active_tier_scopes) and store remote/publishing configuration
# (gitlore_memory_remote_name, gitlore_parent_visibility). Function-only — no readonly, no top-level
# state — so unlike util.sh it is safe to source twice; definition order
# relative to util.sh does not matter, since a call only needs the
# other file's functions defined by the time it runs, not by the time
# this one is sourced.
# Part of lib/util.sh; source that, not this file.

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
  # LC_ALL=C: a NUL-delimited `read`,
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

# Print the visibility to use for the memory remote: "public" or "private".
# Matches the parent repo (design: public parent → public memory). Defaults to
# "private" when there is no parent origin or gh cannot report it — the safe
# default for memory, which may contain session context.
gitlore_parent_visibility() {
  local purl
  purl=$(git config --get remote.origin.url || true)
  if [ -n "$purl" ] && [ "$(gitlore_repo_visibility "$purl")" = "public" ]; then
    printf 'public\n'
    return 0
  fi
  printf 'private\n'
}

# Print the visibility gh reports for the repository at $1 — "public",
# "private" or "internal" — and nothing when it cannot say (empty $1, no gh, no
# auth, a non-GitHub url, network down, a repo this token cannot see). Silence
# is "unknown", which a caller must not read as private.
# Args: $1 = a url gh accepts (https, ssh, scp-style) or OWNER/REPO.
gitlore_repo_visibility() {
  [ -n "$1" ] || return 0
  command -v gh >/dev/null 2>&1 || return 0
  # Redirect kept: this is a best-effort lookup whose failure modes are all
  # normal and expected, and each already has its answer. Surfacing gh's error
  # would put a scary, actionable-looking message in front of a user for whom
  # nothing is wrong.
  gh repo view "$1" --json visibility -q .visibility 2>/dev/null \
    | tr '[:upper:]' '[:lower:]' || true
}

# Print the https form of a GitHub ssh url, so a tracked `.gitmodules` can be
# cloned with no GitHub SSH key: `git@github.com:o/r[.git]` and
# `ssh://git@github.com/o/r[.git]` become `https://github.com/o/r.git`. Any other
# url — https already, another host, a local path, an unexpected path shape — is
# printed unchanged. Only the url recorded in `.gitmodules` goes through this;
# the submodule's own remote keeps the url it was given, so pushes stay on ssh.
# Args: $1 = a url.
gitlore_github_https_url() {
  local url="$1" path
  case "$url" in
    git@github.com:*)         path="${url#git@github.com:}" ;;
    ssh://git@github.com/*)   path="${url#ssh://git@github.com/}" ;;
    *) printf '%s\n' "$url"; return 0 ;;
  esac
  path="${path%/}"
  path="${path%.git}"
  case "$path" in
    ""|/*|*/|*/*/*|*[[:space:]]*) printf '%s\n' "$url" ;;
    */*) printf 'https://github.com/%s.git\n' "$path" ;;
    *)   printf '%s\n' "$url" ;;
  esac
}

# Print url $1 as it may be shown. Userinfo in a non-ssh `scheme://` url is a
# credential whatever its shape — `https://user:token@host`, `https://TOKEN@host`
# — and goes whole. An ssh url names the login the reader needs to reach the
# host, so `ssh://user:pw@host/path` and the scp form `user:pw@host:path` keep
# the user and lose the `:pw`. A url with no userinfo, a local path and a `@`
# that sits in a path or a query are printed as given.
# Args: $1 = a url.
gitlore_url_for_display() {
  gitlore_url_without_userinfo "$1" login
}

# Print url $1 with its userinfo cut back to what $2 keeps: `login`, the user
# of an ssh url, or `none`. The scp form `[user[:pw]@]host:path` is told from a
# `@` in a plain path by the `:` that follows its `@`. Bound: a password holding
# `@` is not parsed — the text after the authority's last `@` is the host.
# Args: $1 = a url, $2 = `login` or `none`.
gitlore_url_without_userinfo() {
  local url="$1" keep="$2" scheme rest authority userinfo host path
  case "$url" in
    *://*)
      scheme=${url%%://*}
      rest=${url#*://}
      authority=${rest%%/*}
      case "$authority" in
        *@*) ;;
        *) printf '%s\n' "$url"; return 0 ;;
      esac
      userinfo=${authority%@*}
      host=${authority##*@}
      case "$rest" in
        */*) path="/${rest#*/}" ;;
        *) path="" ;;
      esac
      case "$keep:$scheme" in
        login:ssh|login:git+ssh|login:ssh+git)
          printf '%s://%s@%s%s\n' "$scheme" "${userinfo%%:*}" "$host" "$path" ;;
        *) printf '%s://%s%s\n' "$scheme" "$host" "$path" ;;
      esac ;;
    /*|./*|../*) printf '%s\n' "$url" ;;
    *@*:*)
      userinfo=${url%%@*}
      rest=${url#*@}
      if [ "$keep" = login ]; then
        printf '%s@%s\n' "${userinfo%%:*}" "$rest"
      else
        printf '%s\n' "$rest"
      fi ;;
    *) printf '%s\n' "$url" ;;
  esac
}

# Print the hint that follows a store push failure caused by missing
# credentials. A clone takes its remotes from the https `.gitmodules` urls, and
# git pushes over https only with a credential helper — which a working
# `gh auth status` does not imply. The SSH alternative is printed only when the
# store's own `remote.origin.url` is a GitHub https url, filled in from it with
# the store's absolute path, so the command runs as printed.
# Args: $1 = the store's path (a memory store or a tier).
gitlore_push_credentials_hint() {
  local store="$1" url path abs
  printf "Check the network. If this clone's remote is https (a fresh clone takes it from .gitmodules), run 'gh auth setup-git' so git uses your gh credentials"
  # Unchecked out, `git -C` would read the enclosing repository's remote.
  [ -e "$store/.git" ] && url=$(git -C "$store" config --get remote.origin.url) \
    || url=""
  case "$url" in
    https://github.com/*) path="${url#https://github.com/}" ;;
    *) path="" ;;
  esac
  path="${path%/}"
  path="${path%.git}"
  case "$path" in
    ""|*/*/*|*[[:space:]]*|*\'*|*\"*) printf '.'; return 0 ;;
    */*) ;;
    *) printf '.'; return 0 ;;
  esac
  abs=$(git -C "$store" rev-parse --show-toplevel) || abs="$store"
  printf ', or put the clone back on SSH: git -C %q remote set-url origin git@github.com:%s.git' "$abs" "$path"
}

# Warn, on one stderr line, when the repository at $2 is private while this
# repository is public. An anonymous `git clone --recurse-submodules` of a
# public repository aborts at any private submodule in the chain, whatever url
# form `.gitmodules` records. Warns only on a confirmed pair: a visibility gh
# cannot read stays silent, and visibility is never changed from here.
# Args: $1 = what the repository is ("memory remote", "tier remote");
#       $2 = its url; $3 = its visibility when already known (else looked up).
gitlore_warn_private_under_public() {
  local label="$1" url="$2" vis="${3-}"
  [ -n "$vis" ] || vis=$(gitlore_repo_visibility "$url")
  [ "$vis" = "private" ] || return 0
  [ "$(gitlore_parent_visibility)" = "public" ] || return 0
  echo "gitlore: warning: the $label $(gitlore_url_for_display "$url") is private but this repository is public, so an anonymous recursive clone of this repository fails at it whatever url .gitmodules records; making it public is the repository owner's call." >&2
}
