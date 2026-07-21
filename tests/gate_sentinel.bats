#!/usr/bin/env bats
# `scripts/run-gate.sh NAME CMD...` runs a quality gate, but only when the
# working tree has changed since that gate last passed.
#
# The point is not to maximise skips — it is to make `just prerelease` right
# after a green `just precommit` re-run only the part precommit did not cover.
# So the recorded hash covers the WHOLE tree, and it must not false-skip:
#   * content-addressed, not HEAD-addressed — committing between two gate runs
#     does not change what the gate would test, so it must not force a re-run
#     (release requires a clean tree, so this is the normal release path);
#   * untracked non-ignored files count — `make test` globs `tests/*.bats`, so
#     a new-but-unstaged suite changes what runs;
#   * a failed run records nothing, so the next run retries.
# Over-running is the acceptable direction; a stale green is not.

load helpers/setup

setup() {
  setup_tmp_repo
  # The suite runs *inside* a gate (`just precommit` → `make test`), so an
  # ambient GITLORE_GATE_FORCE would reach every gate under test and make the
  # skip cases silently unprovable.
  unset GITLORE_GATE_FORCE
  RUN_GATE="$PLUGIN_ROOT/scripts/run-gate.sh"
  # Outside the repo on purpose: a marker inside it would be an untracked file,
  # which by design invalidates the sentinel — the test would measure itself.
  MARKER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-gate-marker.XXXXXX")"
  MARKER="$MARKER_DIR/ran"
  export MARKER
  echo seed > tracked.txt
  git add tracked.txt
  git commit -q -m "seed"
}
teardown() {
  # An `&&` chain here would make teardown itself exit non-zero whenever the
  # test is set up, which bats reports as a failure.
  if [ -n "${MARKER_DIR:-}" ]; then
    rm -rf "$MARKER_DIR"
  fi
  teardown_tmp_repo
}

# A gate command that appends one line per execution, so the marker's line
# count is the number of times the gate actually ran. The path travels in the
# environment rather than interpolated into the `-c` string, which would break
# on a quote in $TMPDIR.
run_counting_gate() {
  run bash "$RUN_GATE" "${1:-demo}" bash -c 'printf "ran\n" >> "$MARKER"'
}

runs() {
  if [ -f "$MARKER" ]; then
    wc -l < "$MARKER" | tr -d ' '
  else
    printf '0\n'
  fi
}

@test "the first run executes the command" {
  run_counting_gate
  [ "$status" -eq 0 ]
  [ "$(runs)" = 1 ]
}

@test "a second run on an unchanged tree skips the command" {
  run_counting_gate
  run_counting_gate
  [ "$status" -eq 0 ]
  [ "$(runs)" = 1 ]
}

@test "the skip names the gate, so a silent no-op is not mistaken for a pass" {
  run_counting_gate
  run_counting_gate
  [[ "$output" == *"demo"* ]]
}

@test "editing a tracked file re-runs the gate" {
  run_counting_gate
  echo changed > tracked.txt
  run_counting_gate
  [ "$(runs)" = 2 ]
}

@test "deleting a tracked file re-runs the gate" {
  run_counting_gate
  rm tracked.txt
  run_counting_gate
  [ "$(runs)" = 2 ]
}

@test "a new untracked file re-runs the gate" {
  # `make test` discovers suites by glob, so an unstaged new suite changes what
  # the gate would run. Missing this is the false-skip the design rules out.
  run_counting_gate
  echo new > tests_new.bats
  run_counting_gate
  [ "$(runs)" = 2 ]
}

@test "a gitignored file does not re-run the gate" {
  echo "scratch" > .gitignore
  git add .gitignore
  git commit -q -m "ignore scratch"
  run_counting_gate
  echo noise > scratch
  run_counting_gate
  [ "$(runs)" = 1 ]
}

@test "committing an unchanged tree does not re-run the gate" {
  # The release path: precommit goes green, the work is committed, release
  # re-checks the same gate. Same content, so no re-run.
  echo changed > tracked.txt
  run_counting_gate
  git commit -q -a -m "commit the change"
  run_counting_gate
  [ "$(runs)" = 1 ]
}

@test "a failing gate records nothing, so the next run retries" {
  run bash "$RUN_GATE" demo bash -c 'printf "ran\n" >> "$MARKER"; exit 1'
  [ "$status" -eq 1 ]
  run bash "$RUN_GATE" demo bash -c 'printf "ran\n" >> "$MARKER"; exit 1'
  [ "$status" -eq 1 ]
  [ "$(runs)" = 2 ]
}

@test "gates are independent: one going green does not skip another" {
  run_counting_gate precommit
  run_counting_gate evals
  [ "$(runs)" = 2 ]
  run_counting_gate evals
  [ "$(runs)" = 2 ]
}

@test "the sentinel lives under .git and never enters the working tree" {
  run_counting_gate
  run git status --porcelain
  [ -z "$output" ]
  [ -f "$(git rev-parse --git-path gitlore/gates)/demo" ]
}

@test "GITLORE_GATE_FORCE runs the command despite a matching sentinel" {
  run_counting_gate
  GITLORE_GATE_FORCE=1 run_counting_gate
  [ "$(runs)" = 2 ]
  # And it does not linger: the next run, unforced, skips again.
  run_counting_gate
  [ "$(runs)" = 2 ]
}

@test "a tree that cannot be hashed always runs the gate, never skips it" {
  # Observed for real: under a sandbox that surfaces phantom home dotfiles,
  # `git add -A` dies with "can only add regular files" and the hash is built
  # from a half-updated index. Recording that partial hash lets the NEXT run
  # match it and skip a gate that should have run — so a failed hash must
  # record nothing at all. Stubbed rather than provoked, because which paths
  # git refuses is neither portable nor the point: the policy is.
  run_counting_gate
  [ "$(runs)" = 1 ]

  mkdir -p "$MARKER_DIR/bin"
  cat > "$MARKER_DIR/bin/git" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "add" ]; then
  echo "error: simulated refusal" >&2
  exit 128
fi
exec $(command -v git) "\$@"
EOF
  chmod +x "$MARKER_DIR/bin/git"
  PATH="$MARKER_DIR/bin:$PATH"

  run_counting_gate
  [ "$(runs)" = 2 ]
  run_counting_gate
  [ "$(runs)" = 3 ]
}

@test "run-gate.sh is executable, since the justfile invokes it as a program" {
  # The recipes call it by path, not via `bash run-gate.sh`. A 100644 mode has
  # slipped past a green suite here before.
  [ -x "$RUN_GATE" ]
  [ "$(git -C "$PLUGIN_ROOT" ls-files -s -- scripts/run-gate.sh | cut -d' ' -f1)" = 100755 ]
}

@test "the gate's exit status is the command's" {
  run bash "$RUN_GATE" demo bash -c "exit 3"
  [ "$status" -eq 3 ]
}
