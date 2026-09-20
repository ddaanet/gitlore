#!/usr/bin/env bats
# $status/$output are populated by bats `run`; shellcheck cannot see them.
# shellcheck disable=SC2154
# The planted scripts below carry literal `$foo` on purpose (to trigger SC2086
# in the *target*); the single-quoted printf is intentional, not a bug.
# shellcheck disable=SC2016
#
# No test here runs this script against the real repo — `just lint`, a
# sibling precommit step (`justfile`'s `precommit: check-version lint test`),
# already asserts that. Doing it again here doubled shellcheck's ~64s repo-wide
# cost inside `test-unit` for no added coverage in the gate that matters.

load helpers/setup

setup()    { setup_tmp_repo; }
teardown() { teardown_tmp_repo; }

@test "lint-shell: catches a shellcheck violation in a tracked .sh file" {
  printf '#!/usr/bin/env bash\nfoo=$(echo hi)\necho $foo\n' > bad.sh
  git add bad.sh
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *SC2086* ]]
}

@test "lint-shell: discovers extensionless tracked scripts by shebang" {
  mkdir -p hooks
  printf '#!/usr/bin/env bash\ncd /tmp\n' > hooks/pre-commit
  git add hooks/pre-commit
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *SC2164* ]]
}

@test "lint-shell: lints an untracked shell file, as the gate hash already counts it" {
  # `gate-inputs-hash` enumerates `--others --exclude-standard`, so a brand-new
  # file moves the hash; a discovery that skipped it would record a lint pass
  # over a file nothing linted.
  printf '#!/usr/bin/env bash\necho clean\n' > good.sh
  git add good.sh
  printf '#!/usr/bin/env bash\nfoo=$(echo hi)\necho $foo\n' > untracked.sh
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *untracked.sh* ]]
  [[ "$output" == *SC2086* ]]
}

@test "lint-shell: discovers an untracked extensionless script by shebang" {
  mkdir -p hooks
  printf '#!/usr/bin/env bash\ncd /tmp\n' > hooks/pre-push
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *SC2164* ]]
}

@test "lint-shell: leaves ignored shell files alone" {
  printf '#!/usr/bin/env bash\necho clean\n' > good.sh
  printf 'scratch/\n' > .gitignore
  git add good.sh .gitignore
  mkdir scratch
  printf '#!/usr/bin/env bash\nfoo=$(echo hi)\necho $foo\n' > scratch/ignored.sh
  printf '#!/usr/bin/env bash\ncd /tmp\n' > scratch/ignored-hook
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"1 files clean"* ]]
}

# The per-file cache. `shellcheck` is wrapped, never replaced: the wrapper logs
# the files each invocation was handed and then runs the real one, so these
# read what was linted without giving up the verdict.
wrap_shellcheck() {
  SC_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-sc-wrap.XXXXXX")"
  SC_LOG="$SC_DIR/log"
  real="$(command -v shellcheck)"
  cat > "$SC_DIR/shellcheck" <<WRAP
#!/usr/bin/env bash
if [ "\${1:-}" = --version ]; then
  "$real" --version
  printf '%s\n' "\${SC_VERSION_SUFFIX:-}"
  exit 0
fi
printf '%s\n' "\$@" >> "$SC_LOG"
exec "$real" "\$@"
WRAP
  chmod +x "$SC_DIR/shellcheck"
  PATH="$SC_DIR:$PATH"
  : > "$SC_LOG"
}

# a.sh -> lib1.sh -> lib2.sh, and c.sh on its own.
plant_source_chain() {
  printf '#!/usr/bin/env bash\n# shellcheck source=lib1.sh\n. ./lib1.sh\necho "$one"\n' > a.sh
  printf '#!/usr/bin/env bash\n# shellcheck source=lib2.sh\n. ./lib2.sh\none=1\nexport one\n' > lib1.sh
  printf '#!/usr/bin/env bash\ntwo=2\nexport two\n' > lib2.sh
  printf '#!/usr/bin/env bash\necho standalone\n' > c.sh
}

@test "lint-shell: a second run over an unchanged tree lints nothing and still reports clean" {
  wrap_shellcheck
  plant_source_chain
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
  : > "$SC_LOG"
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
  [[ "$output" == *"4 files clean (4 cached)"* ]]
  [ ! -s "$SC_LOG" ]
  rm -rf "$SC_DIR"
}

@test "lint-shell: an edit relints the file and everything that sources it, however indirectly, and nothing else" {
  wrap_shellcheck
  plant_source_chain
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
  : > "$SC_LOG"
  printf 'three=3\nexport three\n' >> lib2.sh
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
  linted="$(grep -v '^-' "$SC_LOG" | sort | tr '\n' ' ')"
  [ "$linted" = "a.sh lib1.sh lib2.sh " ]
  rm -rf "$SC_DIR"
}

@test "lint-shell: a file that failed is linted again, and fails again" {
  wrap_shellcheck
  printf '#!/usr/bin/env bash\nfoo=$(echo hi)\necho $foo\n' > bad.sh
  printf '#!/usr/bin/env bash\necho clean\n' > good.sh
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -ne 0 ]
  [[ "$output" == *SC2086* ]]
  rm -rf "$SC_DIR"
}

@test "lint-shell: a different shellcheck, or GITLORE_GATE_FORCE, relints everything" {
  wrap_shellcheck
  plant_source_chain
  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]

  : > "$SC_LOG"
  SC_VERSION_SUFFIX=other run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -vc '^-' "$SC_LOG")" -eq 4 ]

  run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
  : > "$SC_LOG"
  GITLORE_GATE_FORCE=1 run "$PLUGIN_ROOT/scripts/lint-shell.sh"
  [ "$status" -eq 0 ]
  [ "$(grep -vc '^-' "$SC_LOG")" -eq 4 ]
  rm -rf "$SC_DIR"
}
