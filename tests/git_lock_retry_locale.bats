#!/usr/bin/env bats
# gitlore_git matches git's English lock messages to decide on a retry, so it
# must run its git under the C locale or a localized git translates the message
# and the retry never fires.
#
# The suite does not depend on installed translations. A `git` shim first on
# PATH logs the LC_ALL it was called with, then exits 0. The environment starts
# non-C (a non-C locale and LANGUAGE=fr), so an inherited C locale cannot
# satisfy the assertion.
#
# What is asserted: LC_ALL=C on the call. gettext ignores LANGUAGE when the
# locale is C, and LC_ALL outranks LANG, so LC_ALL=C alone guarantees English.
#
# Every fixture lives in a temp directory (setup_tmp_repo); the checkout's own
# memory/ is never touched.
#
# shellcheck disable=SC2154,SC2030,SC2031
bats_require_minimum_version 1.5.0

load helpers/setup
load helpers/fixtures

setup() {
  setup_tmp_repo
  pick_non_c_locale
  export LC_ALL="$NON_C_LOCALE" LANGUAGE=fr LANG="$NON_C_LOCALE"
  GIT_LOG="$BATS_TEST_TMPDIR/git.log"
  : > "$GIT_LOG"
  install_git_shim
}
teardown() { teardown_tmp_repo; }

# fr_FR.UTF-8 where the machine has it. Elsewhere any installed non-C locale
# (a missing one makes every bash in the run warn on stderr), else fr_FR anyway.
pick_non_c_locale() {
  local cand have
  have=$(locale -a || true)
  NON_C_LOCALE=fr_FR.UTF-8
  for cand in fr_FR.UTF-8 fr_FR.utf8 en_US.UTF-8 en_US.utf8 C.UTF-8 C.utf8; do
    case "
$have
" in
      *"
$cand
"*) NON_C_LOCALE="$cand"; return 0 ;;
    esac
  done
}

# A `git` first on PATH that logs the locale variables of each call, then exits 0.
install_git_shim() {
  local dir="$BATS_TEST_TMPDIR/shim"
  mkdir -p "$dir"
  {
    printf '#!/bin/sh\nGIT_LOG=%q\n' "$GIT_LOG"
    cat <<'BODY'
printf 'LC_ALL=%s LANGUAGE=%s LANG=%s :: %s\n' \
  "${LC_ALL-<unset>}" "${LANGUAGE-<unset>}" "${LANG-<unset>}" "$*" >> "$GIT_LOG"
exit 0
BODY
  } > "$dir/git"
  chmod +x "$dir/git"
  PATH="$dir:$PATH"
  export PATH
}

@test "locale: gitlore_git runs its git under LC_ALL=C" {
  GITLORE_GIT_RETRY_SCHEDULE="0" gitlore_git status
  [ "$(wc -l < "$GIT_LOG")" -eq 1 ]
  case "$(cat "$GIT_LOG")" in
    "LC_ALL=C "*) ;;
    *) printf 'git not run under LC_ALL=C: %s\n' "$(cat "$GIT_LOG")" >&2; return 1 ;;
  esac
}

@test "locale: gitlore_git leaves the caller's LC_ALL unchanged" {
  GITLORE_GIT_RETRY_SCHEDULE="0" gitlore_git status
  [ "$LC_ALL" = "$NON_C_LOCALE" ]
  [ "$LANGUAGE" = fr ]
}
