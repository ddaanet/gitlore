#!/usr/bin/env bash
# PATH-shadowing stand-ins for tools whose BSD/macOS build is stricter than the
# GNU one. Each stub refuses the GNU-only invocation the way the Mac would break
# on it, and execs the real tool for anything both platforms accept — so a
# Linux run fails on the GNU-ism instead of the next Mac user.
#
# Usage: make_bsd_stubs <dir> <tool>...   then   PATH="<dir>:$PATH" run …

make_bsd_stubs() {
  local dir="$1" tool real
  shift
  mkdir -p "$dir"
  for tool in "$@"; do
    real=$(command -v "$tool") || { echo "make_bsd_stubs: no real $tool on PATH" >&2; return 1; }
    case "$tool" in
      sed)    _bsd_stub_sed "$dir/sed" "$real" ;;
      mktemp) _bsd_stub_mktemp "$dir/mktemp" "$real" ;;
      grep)   _bsd_stub_grep "$dir/grep" "$real" ;;
      *)      echo "make_bsd_stubs: no stub for $tool" >&2; return 1 ;;
    esac
    chmod 755 "$dir/$tool"
  done
}

# BSD sed takes -i's backup extension as a SEPARATE argument and GNU sed takes
# it ATTACHED, so there is no spelling of -i both accept (`-i ''` is the script
# to GNU; `-i 's/x/y/'` makes `s/x/y/` the extension to BSD). The stub rejects
# every -i, and every long option — BSD sed has none.
_bsd_stub_sed() {
  # unquoted EOF: $2 (the real sed) expands now; \$ forms stay for run time
  cat > "$1" <<STUB
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    -i*) echo "sed: -i takes its extension as the next argument on BSD, attached on GNU — write to a temp file and mv instead" >&2; exit 1 ;;
    --*) echo "sed: illegal option -- -" >&2; exit 1 ;;
    -*) ;;
    *) break ;;
  esac
done
exec "$2" "\$@"
STUB
}

# BSD grep's ERE has no `\b`/`\<`/`\>` word boundaries (its spelling is
# `[[:<:]]`/`[[:>:]]`), and no -P or -z. GNU grep accepts them all, so a pattern
# using one lints and passes on Linux and silently matches nothing on a Mac.
_bsd_stub_grep() {
  cat > "$1" <<STUB
#!/bin/sh
for a in "\$@"; do
  case "\$a" in
    -P|-z|-*P*|-*z*) case "\$a" in --*) ;; *) echo "grep: invalid option -- \$a" >&2; exit 2 ;; esac ;;
    *'\\b'*|*'\\<'*|*'\\>'*) echo "grep: GNU word boundary in pattern: \$a (BSD spells it [[:<:]] / [[:>:]])" >&2; exit 2 ;;
  esac
done
exec "$2" "\$@"
STUB
}

# BSD mktemp randomises only TRAILING X's (Apple Libc find_temp_path: no
# minimum-X check, then open/mkdir with O_EXCL on whatever is left). A template
# like `name.XXXXXX.log` is therefore used literally: the first call creates
# it, the second fails with EEXIST. The stub reproduces exactly that; a
# template ending in X goes to the real tool.
_bsd_stub_mktemp() {
  cat > "$1" <<STUB
#!/bin/sh
dir=0; tmpl=
for a in "\$@"; do
  case "\$a" in -d) dir=1 ;; -*) ;; *) tmpl=\$a ;; esac
done
case "\$tmpl" in
  ''|*X) exec "$2" "\$@" ;;
esac
if [ "\$dir" -eq 1 ]; then
  mkdir "\$tmpl" 2>/dev/null || { echo "mktemp: mkdtemp failed on \$tmpl: File exists" >&2; exit 1; }
else
  (set -C; : > "\$tmpl") 2>/dev/null || { echo "mktemp: mkstemp failed on \$tmpl: File exists" >&2; exit 1; }
fi
printf '%s\n' "\$tmpl"
STUB
}
