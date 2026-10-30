#!/usr/bin/env bash
# Readers of the sectioned commit summary: one `== <store> ==` header per store,
# each followed by that store's commit message. Bash 3.2 has no associative
# arrays, so each reader scans the summary string on every call.
# Part of lib/resolve.sh; source that, not this file.

# Print each section header's store name, one per line, in summary order.
# Args: $1 = the summary text.
gitlore_summary_headers() {
  local line name
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '== '*' ==')
        name=${line#'== '}
        printf '%s\n' "${name% ==}"
        ;;
    esac
  done <<<"$1"
}

# Print the non-blank text that precedes the first header, if any: a summary
# whose text belongs to no store.
# Args: $1 = the summary text.
gitlore_summary_preamble() {
  local line seen=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '== '*' ==') seen=1 ;;
      *)
        if [ "$seen" = 0 ] && [ -n "${line//[[:space:]]/}" ]; then
          printf '%s\n' "$line"
        fi
        ;;
    esac
  done <<<"$1"
}

# Print the body of store $2's section, verbatim, without its header line. The
# body ends at the next header. Empty output when the store has no section.
# A duplicated header is refused by the caller before this runs.
# Args: $1 = the summary text, $2 = store name.
gitlore_summary_section() {
  local line name in=0
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      '== '*' ==')
        name=${line#'== '}
        name=${name% ==}
        in=0
        [ "$name" = "$2" ] && in=1
        ;;
      *)
        if [ "$in" = 1 ]; then printf '%s\n' "$line"; fi
        ;;
    esac
  done <<<"$1"
}
