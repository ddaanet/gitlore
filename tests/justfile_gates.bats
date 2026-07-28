#!/usr/bin/env bats
# Guards on this repo's own `justfile`, which is the only place the gates are
# defined now that the Makefile is gone. Like plugin_distribution.bats, these
# inspect gitlore's real files rather than a fixture: the failure they exist to
# catch is a suite that no longer runs, and a fixture cannot show that.

load helpers/setup

setup() {
  command -v just > /dev/null || {
    echo "just is not on PATH; the gate recipes cannot be inspected" >&2
    return 1
  }
  # `bats` reduced to an echo of its arguments, so a recipe can be asked what it
  # WOULD run without running it. Discovery is the thing under test.
  STUB_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-justfile-stub.XXXXXX")"
  cat > "$STUB_DIR/bats" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@"
EOF
  chmod +x "$STUB_DIR/bats"
}

teardown() {
  if [ -n "${STUB_DIR:-}" ]; then
    rm -rf "$STUB_DIR"
  fi
  if [ -n "${GATE_REPO:-}" ]; then
    rm -rf "$GATE_REPO"
  fi
}

# `env -C` is GNU-only, so every invocation below goes through a subshell cd.
just_here() {
  ( cd "$PLUGIN_ROOT" && just "$@" )
}

# A throwaway repo plus the gate helpers as the recipes actually get them:
# `just --evaluate` hands back the exact prolog text every shebang expands to,
# so these exercise the shipped code rather than a transcription of it.
setup_gate_repo() {
  GATE_REPO="$(mktemp -d "${TMPDIR:-/tmp}/gitlore-gate-repo.XXXXXX")"
  PROLOG="$GATE_REPO/prolog.bash"
  { printf '#!'; just_here --evaluate bash_prolog; } > "$PROLOG"
  git -C "$GATE_REPO" init -q
  git -C "$GATE_REPO" config user.email t@example.com
  git -C "$GATE_REPO" config user.name T
  mkdir -p "$GATE_REPO/src" "$GATE_REPO/other"
  printf 'one\n' > "$GATE_REPO/src/a.txt"
  printf 'elsewhere\n' > "$GATE_REPO/other/c.txt"
  printf 'ignored\n' > "$GATE_REPO/.gitignore"
  git -C "$GATE_REPO" add -A
  git -C "$GATE_REPO" commit -qm init
}

# Run a snippet with the prolog loaded, inside the throwaway repo. The prolog
# sets errexit, so a snippet must consume a helper's non-zero status itself.
# `GITLORE_GATE_FORCE` is cleared: this suite runs *inside* a gate, and an
# ambient value would reach every gate under test and make the skip cases
# silently unprovable.
in_gate_repo() {
  (
    cd "$GATE_REPO" || return 1
    unset GITLORE_GATE_FORCE
    # shellcheck source=/dev/null
    . "$PROLOG"
    eval "$1"
  )
}

# Ask the gate whether it would skip, exactly as a recipe's first line does.
gate_verdict() {
  in_gate_repo "if check-sentinel g $1; then echo skip; else echo run; fi"
}

# What a recipe does after its checks pass: `check-sentinel` is what names the
# sentinel and the input set, so `record-sentinel` is never reached without it.
gate_record() {
  in_gate_repo "check-sentinel g $1 || true; record-sentinel"
}

# Every .bats file the repo has, tracked or merely written — the same set the
# recipes' globs see, so a brand-new suite counts before it is added.
all_suites() {
  git -C "$PLUGIN_ROOT" ls-files --cached --others --exclude-standard -- tests \
    | grep '\.bats$' \
    | sort
}

# What `just test` would hand to bats, with bats stubbed out. Filtered to
# *.bats lines: the recipes also pass `--jobs <n>`, which the stub echoes
# like any other arg but which isn't a suite.
discovered_suites() {
  ( cd "$PLUGIN_ROOT" && PATH="$STUB_DIR:$PATH" just test-unit test-integration ) | grep '\.bats$'
}

@test "every suite under tests/ is run by one of the test recipes" {
  # The regression this exists for: `make test` once hand-listed its suites and
  # five of them (21 tests) drifted off the list, including the FR11 memory-gate
  # cover. Nothing was red — they simply never ran.
  run discovered_suites
  [ "$status" -eq 0 ]
  discovered="$(printf '%s\n' "$output" | sort)"
  [ "$discovered" = "$(all_suites)" ]
}

@test "no suite is run twice" {
  run discovered_suites
  [ "$status" -eq 0 ]
  dupes="$(printf '%s\n' "$output" | sort | uniq -d)"
  [ -z "$dupes" ]
}

@test "the test recipes discover by glob, never by a hand-written list" {
  # A list is what drifts. Any literal suite name in the justfile is one.
  run grep -n '[A-Za-z_]\.bats' "$PLUGIN_ROOT/justfile"
  [ "$status" -ne 0 ]
}

@test "the recipes release and precommit depend on still exist" {
  # `release` (vendored in plugin-dev/release.just) depends on `prerelease`, and
  # just rejects the whole justfile if a dependency names a missing recipe — but
  # `precommit` reaches check-version/lint/test through a shell line, which just
  # cannot check. Renaming one of those would only surface at gate time.
  run just_here --summary
  [ "$status" -eq 0 ]
  for recipe in precommit prerelease evals check-version lint test test-unit test-integration release; do
    [[ " $output " == *" $recipe "* ]]
  done
}

@test "the Makefile is gone, so nothing can quietly still run make" {
  [ ! -e "$PLUGIN_ROOT/Makefile" ]
}

@test "every declared gate input exists in the repo" {
  # An input path that no longer exists contributes nothing to the hash and says
  # nothing about it: `git ls-files` does not complain about a pathspec that
  # matches nothing, so a stale entry here silently narrows what the gate covers.
  for var in precommit_inputs evals_inputs; do
    run just_here --evaluate "$var"
    [ "$status" -eq 0 ]
    for path in $output; do
      [ -e "$PLUGIN_ROOT/$path" ]
    done
  done
}

@test "the evals input set is a superset of precommit's, and adds the shipped plugin content" {
  # The two sets exist because the evals drive the real CLI against the
  # installed plugin: an edit to what the plugin ships must invalidate them.
  # Nothing the precommit gate reads may be missing from the wider set, or a
  # green evals run would be resting on a tree its own checks never saw.
  run just_here --evaluate precommit_inputs
  [ "$status" -eq 0 ]
  narrow="$output"
  run just_here --evaluate evals_inputs
  [ "$status" -eq 0 ]
  wide=" $output "
  for path in $narrow; do
    [[ "$wide" == *" $path "* ]]
  done
  for path in agents commands skills; do
    [[ "$wide" == *" $path "* ]]
    [[ " $narrow " != *" $path "* ]]
  done
}

@test "every top-level entry is either a gate input or a deliberate exclusion" {
  # The complement of the test above: the declaration is an allow-list, so a new
  # top-level directory holding scripts or fixtures is invisible to the hash
  # until someone names it here. Checked against the wider set — a path may be
  # deliberately absent from precommit's, but absent from both means no gate
  # sees it at all.
  run just_here --evaluate evals_inputs
  [ "$status" -eq 0 ]
  declared=" $output "
  # Excluded on purpose: no check reads them, and including them would re-run
  # the whole suite on a memory-only or docs-only commit.
  excluded=" memory docs README.md CLAUDE.md .claude .editorconfig .envrc "
  while IFS= read -r entry; do
    [[ "$declared" == *" $entry "* ]] || [[ "$excluded" == *" $entry "* ]] || {
      echo "top-level entry '$entry' is neither a declared gate input nor a deliberate exclusion" >&2
      return 1
    }
  done < <(git -C "$PLUGIN_ROOT" ls-files | sed 's#/.*##' | sort -u)
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
