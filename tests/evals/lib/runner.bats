#!/usr/bin/env bats
# Tests for run-evals.sh pre-flight behaviour.

EVAL_LIB_DIR="$BATS_TEST_DIRNAME"
RUN_EVALS="$BATS_TEST_DIRNAME/../run-evals.sh"

@test "run-evals: exits 1 with sandbox hint when SDK runner probe fails" {
    local fake_lib="$BATS_TEST_TMPDIR/lib"
    mkdir -p "$fake_lib"
    # Replace sdk-runner with one that always fails (simulates sandboxed env)
    printf '#!/usr/bin/env python3\nimport sys\nprint("probe: API not accessible", file=sys.stderr)\nsys.exit(1)\n' \
        > "$fake_lib/sdk-runner.py"
    chmod +x "$fake_lib/sdk-runner.py"

    run env LIB_DIR="$fake_lib" bash "$RUN_EVALS"

    [ "$status" -eq 1 ]
    [[ "$output" =~ "sandbox" ]]
}
