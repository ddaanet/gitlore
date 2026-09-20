#!/usr/bin/env bats
# The gate sentinel itself: what invalidates a recorded pass, what does not,
# and the races a hash taken only at the end could otherwise paper over.

load helpers/setup
load helpers/justfile-gates

# Ask the gate whether it would skip, exactly as a recipe's first line does.
gate_verdict() {
  in_gate_repo "if check-sentinel g $1; then echo skip; else echo run; fi"
}

# --- the gate sentinel itself -------------------------------------------------

@test "an unchanged input set skips; a changed one re-runs" {
  setup_gate_repo
  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = run ]

  gate_record src
  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = skip ]

  printf 'two\n' > "$GATE_REPO/src/a.txt"
  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = run ]
}

@test "committing does not invalidate a recorded pass" {
  # Content-addressed, not HEAD-addressed: a release commits *after* the gate
  # goes green, and that commit must not send the next run through the suite.
  setup_gate_repo
  gate_record src
  printf 'two\n' > "$GATE_REPO/src/a.txt"
  git -C "$GATE_REPO" commit -qam change
  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = run ]

  gate_record src
  git -C "$GATE_REPO" commit -q --allow-empty -m empty
  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = skip ]
}

@test "an untracked non-ignored file invalidates, an ignored one does not" {
  # The suites are discovered by glob, so a brand-new file changes what runs
  # before anyone stages it — which is exactly when a stale pass would hurt.
  setup_gate_repo
  gate_record src
  printf 'new\n' > "$GATE_REPO/src/b.txt"
  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = run ]

  gate_record src
  printf 'noise\n' > "$GATE_REPO/src/ignored"
  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = skip ]
}

@test "a path outside the declared inputs does not invalidate" {
  # The point of declaring inputs, and the reason the declaration is guarded:
  # anything unnamed is invisible to the hash.
  setup_gate_repo
  gate_record src
  printf 'moved\n' > "$GATE_REPO/other/c.txt"
  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = skip ]
}

@test "the sentinel lives under the gitdir, never in the working tree" {
  # A gate whose own bookkeeping showed up in `git status` would land in its
  # own input hash and invalidate itself on every run.
  setup_gate_repo
  gate_record src
  [ -f "$GATE_REPO/.git/gitlore/gates/g" ]
  run git -C "$GATE_REPO" status --porcelain
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "GITLORE_GATE_FORCE never skips" {
  setup_gate_repo
  gate_record src
  run env GITLORE_GATE_FORCE=1 bash -c \
    "cd '$GATE_REPO' && . '$PROLOG' && if check-sentinel g src; then echo skip; else echo run; fi"
  [ "$status" -eq 0 ]
  [ "$output" = run ]
}

@test "an input edited while the checks ran is not recorded as a pass" {
  # The window a hash taken only at the end leaves open: a peer session's edit
  # during a long run would be sealed in as a pass for a tree nothing checked.
  # The gate must leave no sentinel and must fail, so the caller is never told
  # the tree is green.
  setup_gate_repo
  gate_record src
  run in_gate_repo "check-sentinel g src || true
    printf 'edited\n' > src/a.txt
    record-sentinel
    echo after-record"
  [ "$status" -ne 0 ]
  [[ "$output" == *"NOT recorded"* ]]
  [[ "$output" != *after-record* ]]
  [ ! -e "$GATE_REPO/.git/gitlore/gates/g" ]

  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = run ]
}

@test "an edit outside the declared inputs during a run still records the pass" {
  # The complement: the comparison is scoped to what the gate reads, so an
  # unrelated edit mid-run must not cost a nine-minute re-run.
  setup_gate_repo
  run in_gate_repo "check-sentinel g src || true
    printf 'moved\n' > other/c.txt
    record-sentinel
    echo after-record"
  [ "$status" -eq 0 ]
  [[ "$output" == *after-record* ]]

  run gate_verdict src
  [ "$status" -eq 0 ]
  [ "$output" = skip ]
}

@test "an unhashable input set records nothing, says so, and never skips" {
  # The failure the old gate had silently: a hash that cannot be computed must
  # not leave a partial one behind. A deterministic failure would otherwise
  # match itself on the next run and skip a tree nothing ever checked.
  setup_gate_repo
  gate_record src
  [ -f "$GATE_REPO/.git/gitlore/gates/g" ]

  # `bats` is one of the unpinned tool versions folded into the hash; a broken
  # one is the cheapest way to make the whole stream fail.
  cat > "$STUB_DIR/bats" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
  chmod +x "$STUB_DIR/bats"

  run env "PATH=$STUB_DIR:$PATH" bash -c \
    "cd '$GATE_REPO' && . '$PROLOG' && { check-sentinel g src || true; }; record-sentinel"
  [ "$status" -eq 0 ]
  [[ "$output" == *"NOT recorded"* ]]
  [ ! -e "$GATE_REPO/.git/gitlore/gates/g" ]

  run env "PATH=$STUB_DIR:$PATH" bash -c \
    "cd '$GATE_REPO' && . '$PROLOG' && if check-sentinel g src; then echo skip; else echo run; fi"
  [ "$status" -eq 0 ]
  [ "$output" = run ]
}
