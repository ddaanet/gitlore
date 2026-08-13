#!/usr/bin/env bats
# run-evals.sh's scenario dispatch: which assertion runs, which fixture runs,
# and what reaches the agent.
#
# Driven against stub lib/ scenarios/ asserts/ setups/ directories rather than
# the real ones. The scenario loop is worth testing on its own — a dispatch bug
# grades the wrong flow, or grades nothing, and either way the suite still says
# "passed".

# shellcheck source=tests/helpers/run-asserts.bash
source "$BATS_TEST_DIRNAME/../../helpers/run-asserts.bash"

RUN_EVALS="$BATS_TEST_DIRNAME/../run-evals.sh"

setup() {
  STUB="$BATS_TEST_TMPDIR/stub"
  mkdir -p "$STUB/lib" "$STUB/scenarios" "$STUB/asserts" "$STUB/setups"
  LOG="$BATS_TEST_TMPDIR/log"
  export LOG

  # Stub lib: no install, no API. setup_eval_repo makes just enough repo for the
  # baseline capture (a memory store with one commit).
  cat > "$STUB/lib/setup.sh" <<'EOF'
PLUGIN_ROOT="${PLUGIN_ROOT:-/nonexistent}"
setup_eval_repo() {
  EVAL_REPO="$(mktemp -d "${TMPDIR:-/tmp}/dispatch-eval.XXXXXX")"
  export EVAL_REPO
  mkdir -p "$EVAL_REPO/memory"
  git init -q -b main "$EVAL_REPO/memory"
  git -C "$EVAL_REPO/memory" config user.email e@x.com
  git -C "$EVAL_REPO/memory" config user.name E
  printf '%s\n' "$1" > "$EVAL_REPO/memory/MEMORY.md"
  git -C "$EVAL_REPO/memory" add -A
  git -C "$EVAL_REPO/memory" commit -q -m initial
}
teardown_eval_repo() { [ -z "${EVAL_REPO:-}" ] || rm -rf "$EVAL_REPO"; }
EOF

  # Stub runner: records argv, satisfies the pre-flight probe, writes nothing.
  cat > "$STUB/lib/claude-runner.sh" <<'EOF'
#!/usr/bin/env bash
case " $* " in *" --probe "*) exit 0 ;; esac
printf '%s\n' "RUNNER $*" >> "$LOG"
exit 0
EOF
  chmod +x "$STUB/lib/claude-runner.sh"
}

_scenario() { printf '%s\n' "$2" > "$STUB/scenarios/$1.json"; }

_assert() {
  # Single quotes throughout the generated bodies: $LOG and $EVAL_OUT_DIR must be
  # expanded by the stub when run-evals runs it, not here.
  # shellcheck disable=SC2016
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "ASSERT %s" >> "$LOG"\n%s\n' "$1" "${2:-exit 0}" \
    > "$STUB/asserts/$1.sh"
  chmod +x "$STUB/asserts/$1.sh"
}

_run_evals() {
  run env EVAL_K=1 LIB_DIR="$STUB/lib" SCENARIOS_DIR="$STUB/scenarios" \
      ASSERTS_DIR="$STUB/asserts" SETUPS_DIR="$STUB/setups" \
      bash "$RUN_EVALS"
}

@test "dispatch: a scenario with no assert field grades memory-commit" {
  _assert memory-commit
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p"}'
  _run_evals
  assert_ok
  assert_grep -qx "ASSERT memory-commit" "$LOG"
}

@test "dispatch: a scenario's assert field selects its assertion script" {
  _assert memory-commit
  _assert add-tier
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p","assert":"add-tier"}'
  _run_evals
  assert_ok
  assert_grep -qx "ASSERT add-tier" "$LOG"
  refute_grep -qx "ASSERT memory-commit" "$LOG"
}

# An eval that quietly grades nothing is worse than one that is red.
@test "dispatch: a scenario naming a missing assertion fails, it does not skip" {
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p","assert":"nope"}'
  _run_evals
  assert_fails "no executable assertion" "0/1 scenarios passed"
}

@test "dispatch: a non-executable assertion script fails the scenario" {
  printf '#!/usr/bin/env bash\nexit 0\n' > "$STUB/asserts/limp.sh"
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p","assert":"limp"}'
  _run_evals
  assert_fails "no executable assertion"
}

@test "dispatch: the assertion's non-zero exit fails the trial with its own text" {
  _assert memory-commit 'echo "the tier never mounted"; exit 1'
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p"}'
  _run_evals
  assert_fails "the tier never mounted"
}

@test "dispatch: a scenario's setup field runs its fixture before the agent" {
  _assert memory-commit
  # shellcheck disable=SC2016  # $PWD/$LOG belong to the generated stub
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "SETUP $PWD" >> "$LOG"\n' > "$STUB/setups/tiered.sh"
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p","setup":"tiered"}'
  _run_evals
  assert_ok
  # Ordering matters: the fixture must be in place before the agent starts.
  run grep -n "SETUP\|RUNNER" "$LOG"
  [[ "${lines[0]}" =~ SETUP ]]
  [[ "${lines[1]}" =~ RUNNER ]]
  # …and it runs inside the throwaway repo, so its paths are plain and relative.
  assert_grep -q "SETUP .*dispatch-eval" "$LOG"
}

# A broken fixture and a failed flow are different problems with different fixes;
# reporting them the same way sends the reader to the wrong place.
@test "dispatch: a failing setup is reported as a setup failure, not a flow failure" {
  _assert memory-commit
  printf '#!/usr/bin/env bash\necho "no tier remote"; exit 1\n' > "$STUB/setups/tiered.sh"
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p","setup":"tiered"}'
  _run_evals
  assert_fails "scenario setup 'tiered' failed" "no tier remote"
  # The agent must not have run against a fixture that never came up.
  refute_grep -q RUNNER "$LOG"
}

@test "dispatch: {{EVAL_REPO}} in a prompt expands to the trial's repo" {
  _assert memory-commit
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"mount {{EVAL_REPO}}/.tier-remote.git"}'
  _run_evals
  assert_ok
  assert_grep -q "mount /.*dispatch-eval.*/.tier-remote.git" "$LOG"
  refute_grep -q "{{EVAL_REPO}}" "$LOG"
}

@test "dispatch: a scenario without approval_message runs one turn" {
  _assert memory-commit
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p"}'
  _run_evals
  assert_ok
  refute_grep -q -- "--approval" "$LOG"
}

@test "dispatch: a scenario with approval_message passes it through" {
  _assert memory-commit
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p","approval_message":"go ahead"}'
  _run_evals
  assert_ok
  assert_grep -q -- "--approval go ahead" "$LOG"
}

@test "dispatch: the memory baseline is captured after the fixture, not before" {
  # shellcheck disable=SC2016  # expanded by the generated assertion, not here
  _assert memory-commit 'echo "baseline=$(cat "$EVAL_OUT_DIR/memory-baseline")" >> "$LOG"'
  cat > "$STUB/setups/tiered.sh" <<'EOF'
#!/usr/bin/env bash
printf 'fixture\n' >> memory/MEMORY.md
git -C memory add -A
git -C memory commit -q -m "fixture commit"
git -C memory rev-parse HEAD > "$LOG.fixture-head"
EOF
  _scenario 01 '{"name":"n","initial_memory":"# m","prompt":"p","setup":"tiered"}'
  _run_evals
  assert_ok
  assert_grep -qx "baseline=$(cat "$LOG.fixture-head")" "$LOG"
}
