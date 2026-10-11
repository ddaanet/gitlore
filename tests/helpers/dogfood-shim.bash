#!/usr/bin/env bash
# A fake dogfood shim ahead of a recording fake `claude` on PATH.
#
# The real shim (plugin-dev/bin/claude) exports CLAUDE_CODE_PLUGIN_DIRS and then
# execs the next `claude` on PATH, so a caller that merely unsets the variable
# still hands its child the plugin directory. This fixture reproduces that
# behaviour at <root>/plugin-dev/bin/claude.
#
# Recognition rule the tests presuppose, as a deliberate choice: a PATH entry
# whose directory is a `plugin-dev/bin` holds a dogfood shim, whichever repo
# vendors it. The tests never match this repo's own shim by identity, so a
# repo-anchored rule fails them, and neither file content nor header is
# available to match on. Not exercised: symlinked, `/./` and `//` spellings of
# the entry; only the plain and the trailing-slash spelling are.
#
# dogfood_shim_install <base> [<out>] [<option>...]
#   <base>    writable dir; the fixture root "<base>/dogfood root" has a space
#   <out>     stdout the recorder prints (default: a judge pass line); exported
#             as DOGFOOD_OUT
#   launcher  put a chaining stand-in at <root>/.gitlore/bin/claude between
#             the shim and the recorder, like the gitlore launcher: it strips
#             only its own directory from PATH and execs `claude`. It touches
#             "$DOGFOOD_RECORD.launcher" when it runs.
#   slash     spell the shim's PATH entry with a trailing slash
# Sets and exports PATH, DOGFOOD_RECORD and DOGFOOD_OUT. The recorder writes
# "$DOGFOOD_RECORD.env" ("unset" or "set:<value>") and "$DOGFOOD_RECORD.argv".

dogfood_shim_install() {
  local base="$1" out="${2:-pass looks fine}" opt launcher="" slash=""
  shift
  [ $# -eq 0 ] || shift
  for opt in "$@"; do
    case "$opt" in
      launcher) launcher=1 ;;
      slash) slash=/ ;;
    esac
  done
  local root="$base/dogfood root"
  mkdir -p "$root/plugin-dev/bin" "$root/real bin" "$root/dist/plugin"
  DOGFOOD_RECORD="$base/record file"
  DOGFOOD_OUT="$out"
  export DOGFOOD_RECORD DOGFOOD_OUT

  cat > "$root/real bin/claude" <<'REAL'
#!/usr/bin/env bash
if [ "${CLAUDE_CODE_PLUGIN_DIRS+set}" = set ]; then
  printf 'set:%s\n' "$CLAUDE_CODE_PLUGIN_DIRS" > "$DOGFOOD_RECORD.env"
else
  printf 'unset\n' > "$DOGFOOD_RECORD.env"
fi
printf '%s\n' "$*" >> "$DOGFOOD_RECORD.argv"
printf '%s\n' "$DOGFOOD_OUT"
REAL
  chmod +x "$root/real bin/claude"

  cat > "$root/plugin-dev/bin/claude" <<'SHIM'
#!/usr/bin/env bash
here="$(cd -P -- "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export CLAUDE_CODE_PLUGIN_DIRS="$here/../../dist/plugin"
out="" rest="$PATH:"
while [ -n "$rest" ]; do
  entry="${rest%%:*}"; rest="${rest#*:}"
  [ "${entry:-.}/claude" -ef "${BASH_SOURCE[0]}" ] && continue
  out="$out:$entry"
done
PATH="${out#:}"
exec claude "$@"
SHIM
  chmod +x "$root/plugin-dev/bin/claude"

  local chain="$root/real bin"
  if [ -n "$launcher" ]; then
    mkdir -p "$root/.gitlore/bin"
    cat > "$root/.gitlore/bin/claude" <<'LAUNCHER'
#!/usr/bin/env bash
: > "$DOGFOOD_RECORD.launcher"
out="" rest="$PATH:"
while [ -n "$rest" ]; do
  entry="${rest%%:*}"; rest="${rest#*:}"
  [ "${entry:-.}/claude" -ef "${BASH_SOURCE[0]}" ] && continue
  out="$out:$entry"
done
PATH="${out#:}"
exec claude "$@"
LAUNCHER
    chmod +x "$root/.gitlore/bin/claude"
    chain="$root/.gitlore/bin:$chain"
  fi
  PATH="$root/plugin-dev/bin$slash:$chain:$PATH"
  export PATH
}
