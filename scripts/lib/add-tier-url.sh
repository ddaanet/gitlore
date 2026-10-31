#!/usr/bin/env bash
# check_url: refuse a url add-tier.sh would hand to git. Part of
# scripts/add-tier.sh, which sources this and defines die; source that, not this file.

# Refuse any url that is not a plain transport or a local path.
#
# Not a shell-injection guard — the url is a quoted argument after `--`, never
# interpolated. It bounds which git TRANSPORT the url can select. Git's own
# `protocol.ext.allow` already defaults to `never` (2.47.3: `fatal: transport
# 'ext' not allowed`), so `ext::sh -c …` is dead out of the box; this makes that
# independent of the user's git config, and closes the same class for any other
# `helper::address` transport.
#
# It matters because the mount clones the url from the agent's command sandbox,
# whose network reaches only the hosts it allows. The url's host is added to
# allowed_domains for this one call (D71). A helper transport would run a command
# that reaches past that allowlist, so it is refused whatever the sandbox permits.
check_url() {
  local url="$1" head rest
  case "$url" in
    "")   die "empty url." ;;
    -*)   die "url '$url' starts with '-'; git would read it as an option." ;;
    /*|./*|../*) return 0 ;;                     # local path
  esac
  case "$url" in
    *:*) head="${url%%:*}"; rest="${url#*:}" ;;
    *)   die "url '$url' is neither a path nor a remote; use https://, ssh://, git@host:path, or an absolute path." ;;
  esac
  case "$rest" in
    //*)
      head=$(printf '%s' "$head" | tr '[:upper:]' '[:lower:]')
      case "$head" in
        http|https|ssh|git|file) return 0 ;;
        *) die "url scheme '$head' is not allowed; use https, ssh, git, or file." ;;
      esac ;;
    :*)
      # `helper::address` — git's remote-helper form, of which `ext::` runs a
      # shell command. Never needed to reach a tier remote.
      die "url '$url' selects the git transport helper '$head'; that form is not allowed." ;;
    *)
      # scp-like [user@]host:path — a host has no slash and no whitespace.
      case "$head" in
        ""|*[/[:space:]]*) die "url '$url' is not a usable remote." ;;
        *) return 0 ;;
      esac ;;
  esac
}
